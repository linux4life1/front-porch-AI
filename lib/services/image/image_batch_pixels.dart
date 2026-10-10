// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/services/services.dart';

Future<Uint8List?> imageBatchPixels(Uint8List raw) async {
  var png = raw;
  if (packPictureKind(raw) != PackPictureKind.png) {
    final converted = await convertPackBase(raw);
    if (converted.png == null) return null;
    png = converted.png!;
  }
  if (inspectPackBase(png).size == null) return null;
  return compute(_pixels, png);
}

Uint8List? _pixels(Uint8List png) {
  final decoded = img.decodePng(png);
  return decoded == null ? null : Uint8List.fromList(img.encodePng(decoded));
}
