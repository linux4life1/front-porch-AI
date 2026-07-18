// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/gguf_vision.dart';

/// Build a minimal GGUF v3 file with string key/value metadata and an optional
/// list of tensor names (their dims/type/offset are stubbed — only names matter
/// for vision detection).
Uint8List _buildGguf({
  required Map<String, String> kv,
  List<String> tensorNames = const [],
}) {
  final builder = BytesBuilder();
  builder.add(utf8.encode('GGUF'));
  builder.add(_u32(3));
  builder.add(_u64(tensorNames.length)); // tensor count
  builder.add(_u64(kv.length)); // kv count

  for (final entry in kv.entries) {
    final keyBytes = utf8.encode(entry.key);
    builder.add(_u64(keyBytes.length));
    builder.add(keyBytes);
    builder.add(_u32(8)); // string type
    final valBytes = utf8.encode(entry.value);
    builder.add(_u64(valBytes.length));
    builder.add(valBytes);
  }

  // Tensor info table: name (str), n_dims (u32)=1, dims[1] (u64)=1,
  // type (u32)=0, offset (u64)=0.
  for (final name in tensorNames) {
    final nameBytes = utf8.encode(name);
    builder.add(_u64(nameBytes.length));
    builder.add(nameBytes);
    builder.add(_u32(1)); // n_dims
    builder.add(_u64(1)); // dim 0
    builder.add(_u32(0)); // ggml type
    builder.add(_u64(0)); // data offset
  }

  return Uint8List.fromList(builder.takeBytes());
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asUint32List()[0] = v;
Uint8List _u64(int v) => Uint8List(8)..buffer.asUint64List()[0] = v;

Future<GgufVisionInfo?> _parse(Uint8List bytes, String name) async {
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(bytes);
  try {
    return await GgufVisionParser.getVisionInfo(file.path);
  } finally {
    if (await file.exists()) await file.delete();
  }
}

void main() {
  group('GgufVisionParser', () {
    test('returns null for a missing file', () async {
      final result =
          await GgufVisionParser.getVisionInfo('/no/such/model.gguf');
      expect(result, isNull);
    });

    test('returns null for non-GGUF bytes', () async {
      final result = await _parse(
        Uint8List.fromList(utf8.encode('not a gguf')),
        'vision_nomagic.gguf',
      );
      expect(result, isNull);
    });

    test('plain llama text model is text-only', () async {
      final info = await _parse(
        _buildGguf(kv: {'general.architecture': 'llama'}),
        'vision_llama.gguf',
      );
      expect(info, isNotNull);
      expect(info!.architecture, 'llama');
      expect(info.hasEmbeddedProjector, isFalse);
      expect(info.isMultimodal, isFalse);
      expect(info.isTextOnly, isTrue);
      expect(info.needsExternalProjector, isFalse);
    });

    test('always-multimodal arch (mllama) needs an external projector',
        () async {
      final info = await _parse(
        _buildGguf(kv: {'general.architecture': 'mllama'}),
        'vision_mllama.gguf',
      );
      expect(info, isNotNull);
      expect(info!.isMultimodal, isTrue);
      expect(info.hasEmbeddedProjector, isFalse);
      expect(info.needsExternalProjector, isTrue);
    });

    test('qwen2vl arch is detected as multimodal', () async {
      final info = await _parse(
        _buildGguf(kv: {'general.architecture': 'qwen2vl'}),
        'vision_qwen2vl.gguf',
      );
      expect(info!.isMultimodal, isTrue);
      expect(info.needsExternalProjector, isTrue);
    });

    test('clip.* metadata key implies an embedded projector', () async {
      final info = await _parse(
        _buildGguf(kv: {
          'general.architecture': 'clip',
          'clip.has_vision_encoder': 'true',
        }),
        'vision_clipkey.gguf',
      );
      expect(info!.hasEmbeddedProjector, isTrue);
      expect(info.isMultimodal, isTrue);
      expect(info.needsExternalProjector, isFalse);
    });

    test('vision tensor names imply an embedded projector', () async {
      final info = await _parse(
        _buildGguf(
          kv: {'general.architecture': 'llama'},
          tensorNames: [
            'token_embd.weight',
            'v.blk.0.attn_q.weight',
            'mm.0.weight',
          ],
        ),
        'vision_tensors.gguf',
      );
      expect(info!.hasEmbeddedProjector, isTrue);
      expect(info.isMultimodal, isTrue);
    });

    test('vision metadata key (arch.vision.*) implies multimodal', () async {
      final info = await _parse(
        _buildGguf(kv: {
          'general.architecture': 'gemma3',
          'gemma3.vision.block_count': '27',
        }),
        'vision_gemma3.gguf',
      );
      // gemma3 is intentionally NOT in the always-multimodal set, so this proves
      // the vision-key signal is what flips it.
      expect(info!.isMultimodal, isTrue);
      expect(info.needsExternalProjector, isTrue);
    });

    test('bare gemma3 with no vision metadata stays text-only', () async {
      final info = await _parse(
        _buildGguf(kv: {'general.architecture': 'gemma3'}),
        'vision_gemma3_text.gguf',
      );
      expect(info!.isTextOnly, isTrue);
    });
  });
}
