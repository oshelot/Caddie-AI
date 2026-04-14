// ShotRecommendationCard — animated bottom sheet card that reveals
// the LLM's structured shot recommendation row by row. Each row
// has a CaddieIcon + label + value, staggered with a cascade
// animation so the user sees club first, then target, rationale,
// execution details — distracting from LLM latency.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/icons/caddie_icons.dart';

/// Parsed shot recommendation from the LLM JSON response.
class ShotRecommendation {
  final String club;
  final String target;
  final String preferredMiss;
  final String riskLevel;
  final String confidence;
  final List<String> rationale;
  final String? conservativeOption;
  final String swingThought;
  final String? ballPosition;
  final String? weightDistribution;
  final String? stanceWidth;
  final String? alignment;
  final String? clubface;
  final String? backswingLength;
  final String? followThrough;
  final String? tempo;
  final String? strikeIntention;
  final String? mistakeToAvoid;

  const ShotRecommendation({
    required this.club,
    required this.target,
    this.preferredMiss = '',
    this.riskLevel = '',
    this.confidence = '',
    this.rationale = const [],
    this.conservativeOption,
    this.swingThought = '',
    this.ballPosition,
    this.weightDistribution,
    this.stanceWidth,
    this.alignment,
    this.clubface,
    this.backswingLength,
    this.followThrough,
    this.tempo,
    this.strikeIntention,
    this.mistakeToAvoid,
  });

  /// Parse from LLM JSON response. Tolerant of missing fields.
  static ShotRecommendation? tryParse(String raw) {
    try {
      // Strip markdown code fences if present.
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
      }
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final exec = (json['executionPlan'] as Map?)?.cast<String, dynamic>();
      return ShotRecommendation(
        club: json['club'] as String? ?? '',
        target: json['target'] as String? ?? '',
        preferredMiss: json['preferredMiss'] as String? ?? '',
        riskLevel: json['riskLevel'] as String? ?? '',
        confidence: json['confidence'] as String? ?? '',
        rationale: (json['rationale'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        conservativeOption: json['conservativeOption'] as String?,
        swingThought: json['swingThought'] as String? ??
            exec?['swingThought'] as String? ??
            '',
        ballPosition: exec?['ballPosition'] as String?,
        weightDistribution: exec?['weightDistribution'] as String?,
        stanceWidth: exec?['stanceWidth'] as String?,
        alignment: exec?['alignment'] as String?,
        clubface: exec?['clubface'] as String?,
        backswingLength: exec?['backswingLength'] as String?,
        followThrough: exec?['followThrough'] as String?,
        tempo: exec?['tempo'] as String?,
        strikeIntention: exec?['strikeIntention'] as String?,
        mistakeToAvoid: exec?['mistakeToAvoid'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Shows the animated recommendation card as a bottom sheet.
Future<void> showShotRecommendationSheet({
  required BuildContext context,
  required ShotRecommendation rec,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _AnimatedRecommendationCard(rec: rec),
  );
}

class _AnimatedRecommendationCard extends StatefulWidget {
  const _AnimatedRecommendationCard({required this.rec});
  final ShotRecommendation rec;

  @override
  State<_AnimatedRecommendationCard> createState() =>
      _AnimatedRecommendationCardState();
}

class _AnimatedRecommendationCardState
    extends State<_AnimatedRecommendationCard> {
  final List<_RecRow> _allRows = [];
  int _visibleCount = 0;

  @override
  void initState() {
    super.initState();
    _buildRows();
    _revealNextRow();
  }

  void _buildRows() {
    final r = widget.rec;

    // Strategy section
    if (r.club.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.club(size: 20),
        label: 'Club',
        value: r.club,
        isHero: true,
      ));
    }
    if (r.target.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.target(size: 20),
        label: 'Target',
        value: r.target,
      ));
    }
    if (r.preferredMiss.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.flag(size: 20),
        label: 'Preferred Miss',
        value: r.preferredMiss,
      ));
    }
    if (r.riskLevel.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.hazard(size: 20),
        label: 'Risk',
        value: '${r.riskLevel}${r.confidence.isNotEmpty ? ' · ${r.confidence} confidence' : ''}',
        valueColor: _riskColor(r.riskLevel),
      ));
    }
    if (r.rationale.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.info(size: 20),
        label: 'Rationale',
        value: r.rationale.map((s) => '• $s').join('\n'),
      ));
    }
    if (r.conservativeOption != null && r.conservativeOption!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.flag(size: 20),
        label: 'Conservative Option',
        value: r.conservativeOption!,
      ));
    }

    // Execution section
    if (r.ballPosition != null && r.ballPosition!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.stance(size: 20),
        label: 'Ball Position',
        value: r.ballPosition!,
      ));
    }
    if (r.weightDistribution != null && r.weightDistribution!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.slope(size: 20),
        label: 'Weight',
        value: r.weightDistribution!,
      ));
    }
    if (r.alignment != null && r.alignment!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.target(size: 20),
        label: 'Alignment',
        value: r.alignment!,
      ));
    }
    if (r.clubface != null && r.clubface!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.club(size: 20),
        label: 'Club Face',
        value: r.clubface!,
      ));
    }
    if (r.backswingLength != null && r.backswingLength!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.tempo(size: 20),
        label: 'Backswing',
        value: r.backswingLength!,
      ));
    }
    if (r.followThrough != null && r.followThrough!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.tempo(size: 20),
        label: 'Follow Through',
        value: r.followThrough!,
      ));
    }
    if (r.tempo != null && r.tempo!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.tempo(size: 20),
        label: 'Tempo',
        value: r.tempo!,
      ));
    }
    if (r.swingThought.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.chat(size: 20),
        label: 'Swing Thought',
        value: r.swingThought,
      ));
    }
    if (r.mistakeToAvoid != null && r.mistakeToAvoid!.isNotEmpty) {
      _allRows.add(_RecRow(
        icon: CaddieIcons.warning(size: 20),
        label: 'Mistake to Avoid',
        value: r.mistakeToAvoid!,
        valueColor: Colors.orange,
      ));
    }
  }

  void _revealNextRow() {
    if (_visibleCount >= _allRows.length) return;
    Future.delayed(Duration(milliseconds: _visibleCount == 0 ? 100 : 150), () {
      if (!mounted) return;
      setState(() => _visibleCount++);
      _revealNextRow();
    });
  }

  Color _riskColor(String risk) {
    switch (risk.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            // Header
            Row(
              children: [
                const Spacer(),
                Text('Shot Recommendation',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Animated rows
            for (int i = 0; i < _allRows.length; i++)
              AnimatedOpacity(
                opacity: i < _visibleCount ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: AnimatedSlide(
                  offset: i < _visibleCount
                      ? Offset.zero
                      : const Offset(0, 0.3),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: _buildRow(_allRows[i], theme, i == 0),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRow(_RecRow row, ThemeData theme, bool isFirst) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: row.icon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.value,
                  style: row.isHero
                      ? theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        )
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: row.valueColor,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecRow {
  final Widget icon;
  final String label;
  final String value;
  final bool isHero;
  final Color? valueColor;

  const _RecRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isHero = false,
    this.valueColor,
  });
}
