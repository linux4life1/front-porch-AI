// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'expression_pack_base_check.dart';

/// Decode a candidate pack base and re-emit it at a diffusion-friendly size
/// that PRESERVES the source aspect ratio — a portrait avatar yields a
/// portrait pack instead of being forced square. The long side lands on 768
/// and both dimensions snap to multiples of 64, because backends can't
/// generate at arbitrary pixel sizes and ComfyUI's img2img inherits its
/// output size from the reference image — the base must literally BE the
/// generation size. Shared by the Studio pack dialog and the creator's
/// Portrait & Avatars panel. Returns null when the bytes can't be decoded.
/// This takes a PNG only; a JPEG or WebP is made into one first by
/// [preparePackBase], which is what callers use.
///
/// The bytes are judged before any decoder sees them ([inspectPackBase]): only
/// a PNG, not an animated one, nothing over about 40 megapixels, none that
/// inflates past its size. Then null is returned, and
/// [onRefused] (when the reason is one to show) is given the refusal. A decode
/// that fails is null as well.
({Uint8List bytes, int width, int height})? normalizePackBase(
  Uint8List raw, {
  void Function(PackBaseRefusal refusal)? onRefused,
}) {
  final verdict = inspectPackBase(raw);
  if (verdict.size == null) {
    final refusal = verdict.refusal;
    if (refusal != null) onRefused?.call(refusal);
    return null;
  }
  try {
    return _normalized(raw);
  } catch (e) {
    debugPrint('[ExpressionPack] base picture could not be decoded: $e');
    return null;
  }
}

({Uint8List bytes, int width, int height})? _normalized(Uint8List raw) {
  final decoded = img.decodePng(raw);
  if (decoded == null) return null;
  final isLandscape = decoded.width >= decoded.height;
  final scale = 768 / (isLandscape ? decoded.width : decoded.height);
  int snap(num v) => ((v / 64).round() * 64).clamp(320, 768).toInt();
  final width = isLandscape ? 768 : snap(decoded.width * scale);
  final height = isLandscape ? snap(decoded.height * scale) : 768;
  final resized = img.copyResize(
    decoded,
    width: width,
    height: height,
    interpolation: img.Interpolation.cubic,
  );
  return (bytes: img.encodePng(resized), width: width, height: height);
}
