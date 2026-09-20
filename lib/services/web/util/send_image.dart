// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Optional photo on POST /api/chat/send. Additive JSON key `imageBase64`.

import 'dart:convert';
import 'dart:typed_data';

Uint8List? decodeChatSendImage(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final b64 = s.contains(',') ? s.split(',').last.trim() : s;
  try {
    final bytes = base64Decode(b64);
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}
