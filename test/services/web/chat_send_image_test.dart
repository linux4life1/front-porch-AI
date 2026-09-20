// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phone send may attach a photo the model can see. JSON `imageBase64` is
// additive; text-only clients keep working.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/util/send_image.dart';

void main() {
  test('decodes raw and data-URL base64', () {
    final raw = Uint8List.fromList([1, 2, 3, 4]);
    final b64 = base64Encode(raw);
    expect(decodeChatSendImage(b64), raw);
    expect(decodeChatSendImage('data:image/png;base64,$b64'), raw);
  });

  test('blank or junk is no image, not a throw', () {
    expect(decodeChatSendImage(null), isNull);
    expect(decodeChatSendImage(''), isNull);
    expect(decodeChatSendImage('not-base64!!!'), isNull);
  });
}
