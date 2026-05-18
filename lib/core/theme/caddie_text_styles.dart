// Named text styles — KAN-432 (UI redesign Phase 1).
//
// Single source of truth for the type ramp in the redesign plan §5.
// Numeric styles enable tabular figures so distances don't jitter as
// the GPS updates. Color and font family are intentionally omitted —
// consumers apply color from context, and family is inherited from
// the app theme (a dedicated display family is a later change).
//
// Registered in `caddie_theme_builder.dart` as a [ThemeExtension].
// Consume via `context.caddieText` or
// `Theme.of(context).extension<CaddieTextStyles>()`.

import 'package:flutter/material.dart';

@immutable
class CaddieTextStyles extends ThemeExtension<CaddieTextStyles> {
  const CaddieTextStyles({
    required this.distanceXL,
    required this.distanceMd,
    required this.decision,
    required this.body,
    required this.label,
    required this.caption,
  });

  /// F/C/B center number, current shot distance. 72/64, weight 700.
  final TextStyle distanceXL;

  /// Front/back yardage, plays-like delta. 20/24, weight 600.
  final TextStyle distanceMd;

  /// The Club recommendation in the Caddie panel. 40/44, weight 700.
  final TextStyle decision;

  /// Advice text, descriptions. 16/24, weight 400.
  final TextStyle body;

  /// Section labels (CLUB · TARGET · ADJUST · RISK). 11/14, weight
  /// 600, +0.08em tracking. Uppercase the string at the call site.
  final TextStyle label;

  /// Hole par/handicap, weather chip. 13/16, weight 500.
  final TextStyle caption;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// The standard ramp. Brightness-independent — no colors are baked
  /// in — so a single instance serves every palette.
  static const standard = CaddieTextStyles(
    distanceXL: TextStyle(
      fontSize: 72,
      height: 64 / 72,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      fontFeatures: _tabular,
    ),
    distanceMd: TextStyle(
      fontSize: 20,
      height: 24 / 20,
      fontWeight: FontWeight.w600,
      fontFeatures: _tabular,
    ),
    decision: TextStyle(
      fontSize: 40,
      height: 44 / 40,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
    ),
    body: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
    ),
    label: TextStyle(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.88, // 0.08em at 11px
    ),
    caption: TextStyle(
      fontSize: 13,
      height: 16 / 13,
      fontWeight: FontWeight.w500,
    ),
  );

  @override
  CaddieTextStyles copyWith({
    TextStyle? distanceXL,
    TextStyle? distanceMd,
    TextStyle? decision,
    TextStyle? body,
    TextStyle? label,
    TextStyle? caption,
  }) {
    return CaddieTextStyles(
      distanceXL: distanceXL ?? this.distanceXL,
      distanceMd: distanceMd ?? this.distanceMd,
      decision: decision ?? this.decision,
      body: body ?? this.body,
      label: label ?? this.label,
      caption: caption ?? this.caption,
    );
  }

  @override
  CaddieTextStyles lerp(ThemeExtension<CaddieTextStyles>? other, double t) {
    if (other is! CaddieTextStyles) return this;
    return CaddieTextStyles(
      distanceXL: TextStyle.lerp(distanceXL, other.distanceXL, t)!,
      distanceMd: TextStyle.lerp(distanceMd, other.distanceMd, t)!,
      decision: TextStyle.lerp(decision, other.decision, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
    );
  }
}

extension CaddieTextStylesX on BuildContext {
  /// Named text styles for the active theme. Falls back to the
  /// standard ramp if the extension somehow isn't registered.
  CaddieTextStyles get caddieText =>
      Theme.of(this).extension<CaddieTextStyles>() ?? CaddieTextStyles.standard;
}
