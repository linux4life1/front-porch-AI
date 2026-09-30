// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Best-effort live progress over ComfyUI's WebSocket: text frames carry
/// {type:'progress', data:{value,max}} during sampling; binary frames are
/// preview images (8-byte header: int32 event type 1 = preview, int32 format,
/// then JPEG/PNG bytes) when the server runs with previews on. Null when the
/// socket cannot be opened: progress is decorative, completion is read from
/// /history.
Future<WebSocket?> openComfyProgress(
  String root,
  String clientId,
  void Function(double? progress, Uint8List? preview) onProgress,
) async {
  try {
    final wsRoot = root
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final ws = await WebSocket.connect(
      '$wsRoot/ws?clientId=$clientId',
    ).timeout(const Duration(seconds: 3));
    ws.listen(
      (frame) {
        try {
          if (frame is String) {
            final msg = jsonDecode(frame) as Map<String, dynamic>;
            if (msg['type'] == 'progress') {
              final d = msg['data'] as Map<String, dynamic>?;
              final value = (d?['value'] as num?)?.toDouble();
              final max = (d?['max'] as num?)?.toDouble();
              if (value != null && max != null && max > 0) {
                onProgress((value / max).clamp(0.0, 1.0), null);
              }
            }
          } else if (frame is List<int> && frame.length > 8) {
            final header = Uint8List.fromList(
              frame.sublist(0, 4),
            ).buffer.asByteData();
            if (header.getInt32(0) == 1) {
              onProgress(null, Uint8List.fromList(frame.sublist(8)));
            }
          }
        } catch (_) {
          // malformed frame — ignore; progress is decorative
        }
      },
      onError: (_) {},
      cancelOnError: true,
    );
    return ws;
  } catch (e) {
    debugPrint('ComfyUI: progress WebSocket unavailable ($e)');
    return null;
  }
}
