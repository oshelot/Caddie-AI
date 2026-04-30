// Dev-only screen for trying on different theme palettes without a
// restart. Tap a card to hot-swap; the change is persisted to Hive
// so it survives cold start.
//
// Gated by `isDevMode` at the router level — production builds
// don't expose this route, and the link from Profile > Debug is
// also hidden.
//
// The preview cards render each palette inline using its own
// [ThemeData] (via nested `Theme`), so you can see what the app
// will look like *before* activating — no need to flip back and
// forth to compare.

import 'package:flutter/material.dart';

import '../../../core/theme/caddie_theme_builder.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/theme_palette.dart';

class ThemePlaygroundPage extends StatelessWidget {
  const ThemePlaygroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Theme Playground')),
      body: ValueListenableBuilder<ThemePalette>(
        valueListenable: themeController,
        builder: (context, active, _) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ThemePalette.values.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final palette = ThemePalette.values[i];
              return _PaletteCard(
                palette: palette,
                isActive: palette == active,
                onTap: () => themeController.set(palette),
              );
            },
          );
        },
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.palette,
    required this.isActive,
    required this.onTap,
  });

  final ThemePalette palette;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Build the palette's own ThemeData so the preview renders in
    // its actual colors regardless of what's currently active.
    final previewTheme = buildCaddieTheme(palette);
    final scheme = previewTheme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? scheme.primary : scheme.outlineVariant,
              width: isActive ? 3 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: palette.seedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      palette.label,
                      style: previewTheme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isActive)
                    Icon(Icons.check_circle, color: scheme.primary, size: 22),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                palette.description,
                style: previewTheme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // In-context preview. Wrapping in a nested Theme makes
              // the widget descendants use THIS palette's colors even
              // though the rest of the app is rendering something
              // different above us.
              Theme(
                data: previewTheme,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Primary'),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Outline'),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Text'),
                    ),
                    Chip(
                      label: Text(
                        'Chip',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      backgroundColor: scheme.surfaceContainer,
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Error',
                        style: TextStyle(
                          color: scheme.onError,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
