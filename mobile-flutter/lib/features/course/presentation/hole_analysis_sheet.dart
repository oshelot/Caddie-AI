// HoleAnalysisSheet — full port of iOS CourseMapView.swift:582-867.
// Bottom sheet with 4 sections: Header, Quick Facts, Strategy,
// and Ask a follow-up.

import 'package:flutter/material.dart';

import '../../../core/courses/hole_analysis_engine.dart';
import '../../../core/courses/http_transport.dart';
import '../../../core/llm/llm_messages.dart';
import '../../../core/llm/llm_proxy_provider.dart';
import '../../../core/weather/weather_data.dart';
import '../../../models/normalized_course.dart';

Future<void> showHoleAnalysisSheet({
  required BuildContext context,
  required NormalizedCourse course,
  required NormalizedHole hole,
  required String? selectedTee,
  required WeatherData? weather,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _HoleAnalysisContent(
      course: course,
      hole: hole,
      selectedTee: selectedTee,
      weather: weather,
    ),
  );
}

class _HoleAnalysisContent extends StatefulWidget {
  const _HoleAnalysisContent({
    required this.course,
    required this.hole,
    required this.selectedTee,
    required this.weather,
  });

  final NormalizedCourse course;
  final NormalizedHole hole;
  final String? selectedTee;
  final WeatherData? weather;

  @override
  State<_HoleAnalysisContent> createState() => _HoleAnalysisContentState();
}

class _HoleAnalysisContentState extends State<_HoleAnalysisContent> {
  late final HoleAnalysis _analysis;
  String? _strategyAdvice;
  bool _loadingStrategy = false;
  String? _strategyError;

  // Follow-up conversation state
  final TextEditingController _followUpController = TextEditingController();
  final List<LlmMessage> _conversationHistory = [];
  String? _followUpResponse;
  bool _loadingFollowUp = false;

  static const _systemPrompt =
      'You are an expert golf caddie with 20+ years of PGA Tour '
      'experience. Standing on the tee box with your player, give a '
      'focused tee shot recommendation. Be specific and actionable in '
      'a natural, conversational caddie tone. Cover ONLY the tee shot: '
      'what club to hit and why, where to aim, what to avoid. If '
      'weather data is provided, factor wind into club selection. Keep '
      'it to 2-3 short sentences. Do NOT use markdown. Speak directly '
      'to the player.';

  @override
  void initState() {
    super.initState();
    _analysis = HoleAnalysisEngine.analyze(
      hole: widget.hole,
      selectedTee: widget.selectedTee,
      weather: widget.weather,
    );
    _fetchStrategy();
  }

  @override
  void dispose() {
    _followUpController.dispose();
    super.dispose();
  }

  LlmProxyProvider? _buildProxy() {
    const endpoint =
        String.fromEnvironment('LLM_PROXY_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('LLM_PROXY_API_KEY', defaultValue: '');
    if (endpoint.isEmpty || apiKey.isEmpty) return null;
    return LlmProxyProvider(
      endpoint: endpoint,
      apiKey: apiKey,
      transport: DartIoHttpTransport(),
    );
  }

  Future<void> _fetchStrategy() async {
    final proxy = _buildProxy();
    if (proxy == null) {
      setState(() => _strategyAdvice = _analysis.deterministicSummary);
      return;
    }

    setState(() => _loadingStrategy = true);

    final userMessage = _buildAnalysisPrompt();
    _conversationHistory.addAll([
      const LlmMessage(role: 'system', content: _systemPrompt),
      LlmMessage(role: 'user', content: userMessage),
    ]);

    try {
      final response = await proxy.chatCompletion(LlmRequest(
        messages: _conversationHistory,
        maxTokens: 500,
      ));
      if (!mounted) return;
      _conversationHistory.add(
        LlmMessage(role: 'assistant', content: response.text),
      );
      setState(() {
        _strategyAdvice = response.text;
        _loadingStrategy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _strategyAdvice = _analysis.deterministicSummary;
        _strategyError = '$e';
        _loadingStrategy = false;
      });
    }
  }

  Future<void> _submitFollowUp() async {
    final question = _followUpController.text.trim();
    if (question.isEmpty || _loadingFollowUp) return;

    final proxy = _buildProxy();
    if (proxy == null) return;

    _followUpController.clear();
    setState(() {
      _loadingFollowUp = true;
      _followUpResponse = null;
    });

    _conversationHistory.add(LlmMessage(role: 'user', content: question));

    try {
      final response = await proxy.chatCompletion(LlmRequest(
        messages: _conversationHistory,
        maxTokens: 500,
      ));
      if (!mounted) return;
      _conversationHistory.add(
        LlmMessage(role: 'assistant', content: response.text),
      );
      setState(() {
        _followUpResponse = response.text;
        _loadingFollowUp = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _followUpResponse = 'Sorry, I couldn\'t answer that: $e';
        _loadingFollowUp = false;
      });
    }
  }

  String _buildAnalysisPrompt() {
    final a = _analysis;
    final buf = StringBuffer()
      ..writeln('Course: ${widget.course.name}')
      ..writeln('Hole ${a.holeNumber}, Par ${a.par ?? "?"}')
      ..writeln();

    if (a.yardagesByTee != null && a.yardagesByTee!.isNotEmpty) {
      for (final e in a.yardagesByTee!.entries) {
        buf.writeln('${e.key} tees: ${e.value} yds');
      }
    } else if (a.totalDistanceYards != null) {
      buf.writeln('Distance: ~${a.totalDistanceYards} yds');
    }

    if (a.dogleg != null) {
      buf.writeln('Dogleg ${a.dogleg!.direction} at '
          '${a.dogleg!.distanceFromTeeYards} yds '
          '(${a.dogleg!.bendAngleDegrees.round()}\u00B0)');
    }
    if (a.fairwayWidthAtLandingYards != null) {
      buf.writeln('Fairway width: ~${a.fairwayWidthAtLandingYards} yds '
          'at landing zone');
    }
    if (a.greenDepthYards != null && a.greenWidthYards != null) {
      buf.writeln('Green: ${a.greenDepthYards} yds deep x '
          '${a.greenWidthYards} yds wide');
    }
    for (final h in a.hazards) {
      buf.writeln('${h.type}: ${h.description}');
    }
    if (a.weather != null) {
      buf.writeln('Weather: ${a.weather!.summaryText}');
    }
    buf.writeln();
    buf.writeln('What should I hit off the tee and where should I aim?');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = _analysis;

    // Yardage display: prefer selected tee
    int? displayYds;
    if (a.yardagesByTee != null && a.yardagesByTee!.isNotEmpty) {
      displayYds = a.yardagesByTee!.values.first;
    }
    displayYds ??= a.totalDistanceYards;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            // ── HEADER ──────────────────────────────────
            Row(
              children: [
                const Spacer(),
                Text('Hole Analysis',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Hole ${a.holeNumber}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (a.par != null) ...[
                  const Icon(Icons.flag, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Par ${a.par}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                ],
                if (displayYds != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.straighten, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('$displayYds yds',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                ],
                if (a.dogleg != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    a.dogleg!.direction == 'left'
                        ? Icons.turn_left
                        : Icons.turn_right,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text('Dogleg ${a.dogleg!.direction}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                ],
              ],
            ),

            // ── QUICK FACTS ─────────────────────────────
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('Quick Facts',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._buildQuickFacts(theme, a),

            // ── STRATEGY ────────────────────────────────
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Strategy',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (_loadingStrategy) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (_strategyAdvice != null)
              Text(_strategyAdvice!, style: theme.textTheme.bodyMedium)
            else if (!_loadingStrategy && _strategyError != null)
              Text(_analysis.deterministicSummary,
                  style: theme.textTheme.bodyMedium),

            // ── FOLLOW-UP ───────────────────────────────
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('Ask a follow-up',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _followUpController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitFollowUp(),
                    decoration: InputDecoration(
                      hintText: 'e.g. What if it\'s windy?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _loadingFollowUp
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _submitFollowUp,
                        icon: const Icon(Icons.arrow_upward_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                      ),
              ],
            ),
            if (_followUpResponse != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_followUpResponse!,
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildQuickFacts(ThemeData theme, HoleAnalysis a) {
    final facts = <Widget>[];

    // Per-tee yardages — filtered with the same combo-tee logic
    // as the map screen's tee picker (KAN-182).
    if (a.yardagesByTee != null && a.yardagesByTee!.isNotEmpty) {
      final filtered = _filterComboTees(a.yardagesByTee!);
      final sorted = filtered.entries.toList()
        ..sort((x, y) => y.value.compareTo(x.value));
      for (final e in sorted) {
        facts.add(_factRow(
          label: e.key,
          value: '${e.value} yds',
          color: Colors.green,
          theme: theme,
        ));
      }
    } else if (a.totalDistanceYards != null) {
      facts.add(_factRow(
        label: 'Distance',
        value: '~${a.totalDistanceYards} yds',
        color: Colors.green,
        theme: theme,
      ));
    }

    // Dogleg
    if (a.dogleg != null) {
      final d = a.dogleg!;
      facts.add(_factRow(
        label: 'Dogleg',
        value: '${d.direction[0].toUpperCase()}${d.direction.substring(1)} '
            'at ${d.distanceFromTeeYards} yds '
            '(${d.bendAngleDegrees.round()}\u00B0)',
        color: Colors.green,
        theme: theme,
      ));
    }

    // Fairway width
    if (a.fairwayWidthAtLandingYards != null) {
      facts.add(_factRow(
        label: 'Fairway width',
        value: '~${a.fairwayWidthAtLandingYards} yds at landing zone',
        color: Colors.green,
        theme: theme,
      ));
    }

    // Green dimensions
    if (a.greenDepthYards != null && a.greenWidthYards != null) {
      facts.add(_factRow(
        label: 'Green',
        value:
            '${a.greenDepthYards} yds deep \u00D7 ${a.greenWidthYards} yds wide',
        color: Colors.green,
        theme: theme,
      ));
    }

    // Hazards
    for (final h in a.hazards) {
      facts.add(_factRow(
        label: h.type,
        value: h.description,
        color: h.type == 'Water' ? Colors.blue : Colors.orange,
        theme: theme,
      ));
    }

    // Weather
    if (a.weather != null) {
      facts.add(_factRow(
        label: 'Weather',
        value: a.weather!.summaryText,
        icon: Icons.air,
        color: Colors.cyan,
        theme: theme,
      ));
    }

    return facts;
  }

  /// KAN-182: filter combo tees (e.g. "Bronze/Gold") when both
  /// standalone components exist.
  Map<String, int> _filterComboTees(Map<String, int> yardagesByTee) {
    final standalones = yardagesByTee.keys
        .where((t) => !t.contains('/'))
        .map((t) => t.toLowerCase())
        .toSet();
    return Map.fromEntries(
      yardagesByTee.entries.where((e) {
        if (!e.key.contains('/')) return true;
        final parts = e.key.split('/').map((p) => p.trim().toLowerCase());
        return !parts.every((p) => standalones.contains(p));
      }),
    );
  }

  Widget _factRow({
    required String label,
    required String value,
    required ThemeData theme,
    Color? color,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: icon != null
                ? Icon(icon, size: 14, color: color ?? Colors.green)
                : Icon(Icons.circle, size: 10, color: color ?? Colors.green),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey)),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
