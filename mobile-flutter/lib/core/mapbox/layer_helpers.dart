// Helpers that wrap mapbox_maps_flutter style mutations with the
// diagnostics needed to survive the upstream bugs the KAN-252 spike
// uncovered (see SPIKE_REPORT §4 Bugs 2 & 3).
//
// ## The problem
//
// On iOS, `style.addLayer(LineLayer(... lineDasharray: ...))` and
// `style.addLayer(SymbolLayer(... textFont: ...))` have been observed
// to **return success without actually adding the layer to the
// rendered style**. `getLayer(id)` then returns null, and downstream
// calls (`setStyleLayerProperty`, `updateLayer`) throw
// `PlatformException(0, "Layer ... is not in style")`.
//
// The failure is silent: `await addLayer()` does not throw. The only
// way to detect it is to `getLayer(id)` afterwards and check for null.
//
// ## Required pattern for every map story
//
// 1. Never call `style.addLayer` directly — use [tryAddLayer] so a
//    silent failure is logged with a clear `name` tag.
// 2. After all layers are added, call [verifyLayersPresent] to audit
//    which layers actually made it into the style and abort/degrade
//    gracefully if a critical layer is missing.
// 3. Every property mutation on a layer must first check with
//    [safeGetLayer] — never assume a layer exists because its
//    `addLayer` call returned.
//
// This pattern is enforced for every map-touching story in KAN-251.
// See docs/CONVENTIONS.md.

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Adds a layer and logs whether the call succeeded. Returns `true` if
/// `addLayer` returned without throwing. **Does not guarantee the
/// layer is actually in the style** — use [verifyLayersPresent] after
/// all adds to audit that.
///
/// `name` is a human-readable tag used for log output; it does not
/// have to match the layer id.
Future<bool> tryAddLayer(
  StyleManager style, {
  required String name,
  required Layer Function() build,
}) async {
  final layer = build();
  try {
    await style.addLayer(layer);
    debugPrint('[mapbox] addLayer ok  name=$name id=${layer.id}');
    return true;
  } catch (e, st) {
    debugPrint('[mapbox] addLayer ERR name=$name id=${layer.id} err=$e');
    debugPrint('$st');
    return false;
  }
}

/// Audits the current style by querying every layer id in [layerIds]
/// and returning a `{layerId: isPresent}` map. Call this immediately
/// after a batch of [tryAddLayer] calls to detect upstream silent
/// failures (Bugs 2 & 3).
///
/// The result is also logged at `debugPrint` level so it lands in
/// `flutter run` console output.
Future<Map<String, bool>> verifyLayersPresent(
  StyleManager style,
  Iterable<String> layerIds,
) async {
  final presence = <String, bool>{};
  for (final id in layerIds) {
    presence[id] = (await safeGetLayer(style, id)) != null;
  }
  debugPrint('[mapbox] layer_audit $presence');
  return presence;
}

/// Queries `style.getLayer` but swallows any `PlatformException` so the
/// caller can use a simple null check instead of wrapping every call
/// in try/catch.
Future<Layer?> safeGetLayer(StyleManager style, String layerId) async {
  try {
    return await style.getLayer(layerId);
  } catch (_) {
    return null;
  }
}
