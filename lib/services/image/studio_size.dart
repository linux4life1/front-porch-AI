// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Nearest multiple of 64, each side clamped to 256–2048.
({int width, int height}) snapStudioSize(int width, int height) {
  int snap(int n) {
    final x = (n / 64).round() * 64;
    if (x < 256) return 256;
    if (x > 2048) return 2048;
    return x;
  }

  return (width: snap(width), height: snap(height));
}

/// [size] (`1024x1024`) with each side snapped, as the desk sends it. A value
/// that is not `WxH` is returned as it came.
String snappedStudioSize(String size) {
  final match = RegExp(
    r'^\s*(\d{1,5})\s*[x×]\s*(\d{1,5})\s*$',
  ).firstMatch(size);
  if (match == null) return size;
  final snapped = snapStudioSize(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
  );
  return '${snapped.width}x${snapped.height}';
}
