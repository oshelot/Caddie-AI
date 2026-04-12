// HoleAnalysisSheet — bottom sheet showing hole analysis with
// Quick Facts (computed from geometry) and LLM Strategy text.
// Port of iOS CourseMapView.swift:582-867 HoleAnalysisSheet.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/courses/http_transport.dart';
import '../../../core/geo/geo.dart';
import '../../../core/llm/llm_messages.dart';
import '../../../core/llm/llm_proxy_provider.dart';
import '../../../core/weather/weather_data.dart';
import '../../../models/normalized_course.dart';

/// Shows the hole analysis bottom sheet. Call from the course map
/// screen's Analyze button.
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
  String? _strategy;
  bool _loadingStrategy = false;
  String? _strategyError;

  @override
  void initState() {
    super.initState();
    _fetchStrategy();
  }

  Future<void> _fetchStrategy() async {
    const endpoint =
        String.fromEnvironment('LLM_PROXY_ENDPOINT', defaultValue: '');
    const apiKey =
        String.fromEnvironment('LLM_PROXY_API_KEY', defaultValue: '');
    if (endpoint.isEmpty || apiKey.isEmpty) {
      setState(() => _strategy = _buildDeterministicSummary());
      return;
    }

    setState(() => _loadingStrategy = true);

    try {
      final proxy = LlmProxyProvider(
        endpoint: endpoint,
        apiKey: apiKey,
        transport: DartIoHttpTransport(),
      );
      final facts = _computeQuickFacts();
      final prompt = _buildStrategyPrompt(facts);
      final response = await proxy.chatCompletion(LlmRequest(
        messages: [
          const LlmMessage(
            role: 'system',
            content: 'You are an expert golf caddie with 20+ years of '
                'PGA Tour experience. Standing on the tee box with your '
                'player, give a focused tee shot recommendation. Be '
                'specific and actionable in a natural, conversational '
                'caddie tone. Cover ONLY the tee shot: what club to hit '
                'and why, where to aim, what to avoid. If weather data '
                'is provided, factor wind into club selection. Keep it '
                'to 2-3 short sentences. Do NOT use markdown.',
          ),
          LlmMessage(role: 'user', content: prompt),
        ],
        maxTokens: 500,
      ));
      if (!mounted) return;
      setState(() {
        _strategy = response.text;
        _loadingStrategy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _strategy = _buildDeterministicSummary();
        _strategyError = '$e';
        _loadingStrategy = false;
      });
    }
  }

  List<_QuickFact> _computeQuickFacts() {
    final hole = widget.hole;
    final tee = widget.selectedTee;
    final facts = <_QuickFact>[];

    // Tee yardage
    if (tee != null && hole.yardages.containsKey(tee)) {
      facts.add(_QuickFact(
        label: tee,
        value: '${hole.yardages[tee]} yds',
        color: Colors.green,
      ));
    } else if (hole.yardages.isNotEmpty) {
      final first = hole.yardages.entries.first;
      facts.add(_QuickFact(
        label: first.key,
        value: '${first.value} yds',
        color: Colors.green,
      ));
    }

    // Fairway width estimate from line of play
    final lop = hole.lineOfPlay;
    if (lop != null && lop.points.length >= 2) {
      final totalMeters = _lineDistanceMeters(lop);
      final totalYards = metersToYards(totalMeters).round();
      if (totalYards > 0) {
        // Estimate fairway width at landing zone — simplified
        // version of iOS HoleAnalysisEngine.swift:148-184.
        // We approximate using the average spacing between the
        // line-of-play points if there are enough.
        facts.add(_QuickFact(
          label: 'Hole length',
          value: '$totalYards yds (measured)',
          color: Colors.green,
        ));
      }
    }

    // Green dimensions
    final green = hole.green;
    if (green != null && green.outerRing.length >= 3) {
      final dims = _greenDimensions(green);
      if (dims != null) {
        facts.add(_QuickFact(
          label: 'Green',
          value: '${dims.depthYds} yds deep x ${dims.widthYds} yds wide',
          color: Colors.green,
        ));
      }
    }

    // Bunkers
    if (hole.bunkers.isNotEmpty) {
      for (final bunker in hole.bunkers) {
        final desc = _hazardDescription(bunker, hole, 'Bunker');
        facts.add(_QuickFact(label: 'Bunker', value: desc, color: Colors.orange));
      }
    }

    // Water
    for (final water in hole.water) {
      final desc = _hazardDescription(water, hole, 'Water');
      facts.add(_QuickFact(label: 'Water', value: desc, color: Colors.orange));
    }

    // Weather
    final w = widget.weather;
    if (w != null) {
      final bearing = hole.teeToGreenBearing();
      final relWind = w.relativeWindDirection(bearing);
      final windDir = switch (relWind) {
        RelativeWindDirection.into => 'into',
        RelativeWindDirection.helping => 'helping',
        RelativeWindDirection.crossRightToLeft => 'cross R-to-L',
        RelativeWindDirection.crossLeftToRight => 'cross L-to-R',
      };
      facts.add(_QuickFact(
        label: 'Weather',
        value: '${w.temperatureF.round()}\u00B0F, '
            '${w.windSpeedMph.round()} mph wind ($windDir on this hole)',
        icon: Icons.air,
      ));
    }

    return facts;
  }

  String _buildStrategyPrompt(List<_QuickFact> facts) {
    final hole = widget.hole;
    final buf = StringBuffer()
      ..writeln('Course: ${widget.course.name}')
      ..writeln('Hole ${hole.number}, Par ${hole.par}');
    for (final f in facts) {
      buf.writeln('${f.label}: ${f.value}');
    }
    buf.writeln();
    buf.writeln('What should I hit off the tee and where should I aim?');
    return buf.toString();
  }

  String _buildDeterministicSummary() {
    final hole = widget.hole;
    final tee = widget.selectedTee;
    final yds = (tee != null && hole.yardages.containsKey(tee))
        ? hole.yardages[tee]
        : (hole.yardages.isNotEmpty ? hole.yardages.values.first : null);
    final buf = StringBuffer()
      ..write('Hole ${hole.number} is a par ${hole.par}');
    if (yds != null) buf.write(' playing $yds yards');
    buf.write('.');
    if (hole.bunkers.isNotEmpty) {
      buf.write(' ${hole.bunkers.length} bunker(s) in play.');
    }
    if (hole.water.isNotEmpty) {
      buf.write(' Water in play.');
    }
    return buf.toString();
  }

  // ── geometry helpers ──────────────────────────────────────────

  double _lineDistanceMeters(LineString line) {
    double total = 0;
    for (int i = 1; i < line.points.length; i++) {
      total += haversineMeters(line.points[i - 1], line.points[i]);
    }
    return total;
  }

  ({int depthYds, int widthYds})? _greenDimensions(Polygon green) {
    if (green.outerRing.length < 3) return null;
    // Compute bounding dimensions using lat/lon span.
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in green.outerRing) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    final depthMeters =
        haversineMeters(LngLat(minLon, minLat), LngLat(minLon, maxLat));
    final widthMeters =
        haversineMeters(LngLat(minLon, minLat), LngLat(maxLon, minLat));
    final depth = metersToYards(depthMeters).round();
    final width = metersToYards(widthMeters).round();
    if (depth < 1 || width < 1) return null;
    return (depthYds: depth, widthYds: width);
  }

  String _hazardDescription(Polygon hazard, NormalizedHole hole, String type) {
    final hc = hazard.centroid;
    final gc = hole.green?.centroid;
    if (hc == null) return type;
    if (gc != null) {
      final distToGreen = haversineMeters(hc, gc);
      if (distToGreen < 27) return '$type greenside';
    }
    // Rough side detection using line of play
    final lop = hole.lineOfPlay;
    if (lop != null && lop.points.length >= 2) {
      final start = lop.startPoint!;
      final end = lop.endPoint!;
      // Cross product to determine left/right of line
      final cross = (end.lon - start.lon) * (hc.lat - start.lat) -
          (end.lat - start.lat) * (hc.lon - start.lon);
      final side = cross > 0 ? 'left' : 'right';
      return '$type $side side';
    }
    return type;
  }

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hole = widget.hole;
    final tee = widget.selectedTee;
    final yds = (tee != null && hole.yardages.containsKey(tee))
        ? hole.yardages[tee]
        : (hole.yardages.isNotEmpty ? hole.yardages.values.first : null);
    final facts = _computeQuickFacts();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // Header
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
            // Hole info
            Text('Hole ${hole.number}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.flag, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Par ${hole.par}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey)),
                if (yds != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.straighten, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('$yds yds',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                ],
                if (hole.strokeIndex != null) ...[
                  const SizedBox(width: 12),
                  Text('SI ${hole.strokeIndex}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            // Quick Facts
            const SizedBox(height: 8),
            Text('Quick Facts',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fact.icon != null)
                      Icon(fact.icon, size: 14, color: fact.color ?? Colors.green)
                    else
                      Icon(Icons.circle, size: 10,
                          color: fact.color ?? Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fact.label,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey)),
                          Text(fact.value,
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Divider(),
            // Strategy
            const SizedBox(height: 8),
            Text('Strategy',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loadingStrategy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_strategy != null)
              Text(_strategy!, style: theme.textTheme.bodyMedium)
            else if (_strategyError != null)
              Text('Strategy unavailable: $_strategyError',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
          ],
        );
      },
    );
  }
}

class _QuickFact {
  const _QuickFact({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
}
