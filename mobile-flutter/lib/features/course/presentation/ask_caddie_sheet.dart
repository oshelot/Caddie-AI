// AskCaddieSheet — on-course caddie advice from the course map.
// Port of iOS CourseMapView.swift:447-512 autoDetectAndAskCaddie().
//
// Gets the user's GPS location, calculates distance to the green,
// auto-detects shot type from distance, and calls the LLM with
// full context: hole geometry, weather, player profile, distance.

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';
import '../../../core/courses/http_transport.dart';
import '../../../core/geo/geo.dart';
import '../../../core/llm/llm_messages.dart';
import '../../../core/llm/llm_proxy_provider.dart';
import '../../../core/llm/prompt_service.dart';
import '../../../core/location/location_service.dart';
import '../../../core/storage/profile_repository.dart';
import '../../../core/weather/weather_data.dart';
import '../../../models/normalized_course.dart';
import '../../../models/player_profile.dart';

Future<void> showAskCaddieSheet({
  required BuildContext context,
  required NormalizedCourse course,
  required NormalizedHole hole,
  required String? selectedTee,
  required WeatherData? weather,
  required LocationService locationService,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _AskCaddieContent(
      course: course,
      hole: hole,
      selectedTee: selectedTee,
      weather: weather,
      locationService: locationService,
    ),
  );
}

class _AskCaddieContent extends StatefulWidget {
  const _AskCaddieContent({
    required this.course,
    required this.hole,
    required this.selectedTee,
    required this.weather,
    required this.locationService,
  });

  final NormalizedCourse course;
  final NormalizedHole hole;
  final String? selectedTee;
  final WeatherData? weather;
  final LocationService locationService;

  @override
  State<_AskCaddieContent> createState() => _AskCaddieContentState();
}

class _AskCaddieContentState extends State<_AskCaddieContent> {
  bool _locating = true;
  int? _distanceToGreenYards;
  String _shotType = 'approach';
  String? _advice;
  bool _loadingAdvice = false;
  String? _error;

  // Follow-up
  final TextEditingController _followUpController = TextEditingController();
  final List<LlmMessage> _conversationHistory = [];
  String? _followUpResponse;
  bool _loadingFollowUp = false;

  // Use the centralized S3 prompt for on-course caddie advice.
  String get _systemPrompt =>
      PromptService.shared.caddieSystemPrompt.isNotEmpty
          ? PromptService.shared.caddieSystemPrompt
          : 'You are an expert golf caddie. Give a specific club '
              'recommendation and aiming advice. Be direct, 2-3 sentences.';

  @override
  void initState() {
    super.initState();
    _detectAndAsk();
  }

  @override
  void dispose() {
    _followUpController.dispose();
    super.dispose();
  }

  Future<void> _detectAndAsk() async {
    // Step 1: Get GPS location
    LngLat? userPos;
    try {
      final loc = await widget.locationService.currentLocation();
      if (loc != null) {
        userPos = LngLat(loc.longitude, loc.latitude);
      }
    } catch (_) {}

    // Step 2: Calculate distance to green
    final greenTarget = widget.hole.green?.centroid ??
        widget.hole.pin ??
        widget.hole.lineOfPlay?.endPoint;

    if (userPos != null && greenTarget != null) {
      final meters = haversineMeters(userPos, greenTarget);
      _distanceToGreenYards = metersToYards(meters).round();
    }

    // Step 3: Infer shot type from distance
    final dist = _distanceToGreenYards ?? 0;
    if (dist > 200) {
      _shotType = 'tee shot';
    } else if (dist > 100) {
      _shotType = 'approach';
    } else if (dist > 30) {
      _shotType = 'pitch';
    } else {
      _shotType = 'chip';
    }

    if (!mounted) return;
    setState(() => _locating = false);

    // Step 4: Call LLM
    await _fetchAdvice();
  }

  Future<void> _fetchAdvice() async {
    const endpoint =
        String.fromEnvironment('LLM_PROXY_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('LLM_PROXY_API_KEY', defaultValue: '');
    if (endpoint.isEmpty || apiKey.isEmpty) {
      setState(() => _advice = _buildFallback());
      return;
    }

    setState(() => _loadingAdvice = true);

    final userMessage = _buildPrompt();
    _conversationHistory.addAll([
      LlmMessage(role: 'system', content: _systemPrompt),
      LlmMessage(role: 'user', content: userMessage),
    ]);

    try {
      final proxy = LlmProxyProvider(
        endpoint: endpoint,
        apiKey: apiKey,
        transport: DartIoHttpTransport(),
      );
      final response = await proxy.chatCompletion(LlmRequest(
        messages: _conversationHistory,
        maxTokens: 500,
      ));
      if (!mounted) return;
      _conversationHistory.add(
        LlmMessage(role: 'assistant', content: response.text),
      );
      setState(() {
        _advice = response.text;
        _loadingAdvice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _advice = _buildFallback();
        _error = '$e';
        _loadingAdvice = false;
      });
    }
  }

  String _buildPrompt() {
    final hole = widget.hole;
    final tee = widget.selectedTee;
    final buf = StringBuffer()
      ..writeln('Course: ${widget.course.name}')
      ..writeln('Hole ${hole.number}, Par ${hole.par}');

    if (_distanceToGreenYards != null) {
      buf.writeln('Distance to green: ${_distanceToGreenYards} yards');
      buf.writeln('Shot type: $_shotType');
    } else {
      buf.writeln('Distance to green: unknown (GPS unavailable)');
    }

    // Tee yardage
    if (tee != null && hole.yardages.containsKey(tee)) {
      buf.writeln('Playing from $tee tees: ${hole.yardages[tee]} yds');
    }

    buf.writeln('Lie: fairway (assumed)');

    // Hazards
    if (hole.bunkers.isNotEmpty) {
      buf.writeln('Bunkers: ${hole.bunkers.length} in play');
    }
    if (hole.water.isNotEmpty) {
      buf.writeln('Water: ${hole.water.length} hazard(s) in play');
    }

    // Weather
    final w = widget.weather;
    if (w != null) {
      final bearing = hole.teeToGreenBearing();
      final relWind = w.relativeWindDirection(bearing);
      final windDir = switch (relWind) {
        RelativeWindDirection.into => 'into',
        RelativeWindDirection.helping => 'helping',
        RelativeWindDirection.crossRightToLeft => 'cross right-to-left',
        RelativeWindDirection.crossLeftToRight => 'cross left-to-right',
      };
      buf.writeln('Weather: ${w.temperatureF.round()}\u00B0F, '
          '${w.windSpeedMph.round()} mph wind ($windDir)');
    }

    // Player profile
    try {
      final profile = ProfileRepository().loadOrDefault();
      buf.writeln();
      buf.writeln('Player: handicap ${profile.handicap.round()}, '
          'miss tendency: ${profile.missTendency}, '
          'aggressiveness: ${profile.aggressiveness}');
      if (profile.clubDistances.isNotEmpty) {
        buf.writeln('Club distances: ${profile.clubDistances}');
      }
    } catch (_) {}

    buf.writeln();
    buf.writeln('What club should I hit and where should I aim?');
    return buf.toString();
  }

  String _buildFallback() {
    final dist = _distanceToGreenYards;
    if (dist == null) return 'GPS position unavailable. Open shot input on the Caddie tab for manual entry.';
    return 'You\'re $dist yards from the green on hole ${widget.hole.number} '
        '(par ${widget.hole.par}). '
        '${widget.hole.bunkers.isNotEmpty ? "Watch for bunkers. " : ""}'
        'Pick a club that carries $dist yards and aim center-green.';
  }

  Future<void> _submitFollowUp() async {
    final question = _followUpController.text.trim();
    if (question.isEmpty || _loadingFollowUp) return;

    const endpoint =
        String.fromEnvironment('LLM_PROXY_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('LLM_PROXY_API_KEY', defaultValue: '');
    if (endpoint.isEmpty) return;

    _followUpController.clear();
    setState(() {
      _loadingFollowUp = true;
      _followUpResponse = null;
    });

    _conversationHistory.add(LlmMessage(role: 'user', content: question));

    try {
      final proxy = LlmProxyProvider(
        endpoint: endpoint,
        apiKey: apiKey,
        transport: DartIoHttpTransport(),
      );
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
        _followUpResponse = 'Sorry, couldn\'t answer: $e';
        _loadingFollowUp = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            // Header
            Row(
              children: [
                const Spacer(),
                Text('Ask Caddie',
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

            // Shot context
            Text('Hole ${widget.hole.number}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),

            if (_locating)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Getting your position...'),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  CaddieIcons.pinTarget(size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  if (_distanceToGreenYards != null)
                    Text(
                      '${_distanceToGreenYards} yds to green',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text('GPS position unavailable',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.orange)),
                  const SizedBox(width: 12),
                  if (_distanceToGreenYards != null)
                    Chip(
                      label: Text(_shotType),
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          theme.colorScheme.primaryContainer,
                    ),
                ],
              ),
              if (widget.weather != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    CaddieIcons.wind(size: 14, color: Colors.cyan),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.weather!.temperatureF.round()}\u00B0F, '
                      '${widget.weather!.windSpeedMph.round()} mph wind',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],

            // Advice
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Advice',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (_loadingAdvice) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (_advice != null)
              Text(_advice!, style: theme.textTheme.bodyMedium),

            // Follow-up
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
                      hintText: 'e.g. What about a 7-iron?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _loadingFollowUp
                    ? const SizedBox(
                        width: 40, height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _submitFollowUp,
                        icon: CaddieIcons.send(size: 20),
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
}
