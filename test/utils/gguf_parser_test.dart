// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

/// Build a minimal GGUF v3 file in memory with the given key-value pairs.
Uint8List _buildGgufV3(Map<String, dynamic> kvPairs) {
  final builder = BytesBuilder();

  // Magic: "GGUF"
  builder.add(utf8.encode('GGUF'));

  // Version: 3 (uint32 LE)
  builder.add(_uint32(3));

  // Tensor count: 0 (uint64 LE)
  builder.add(_uint64(0));

  // KV count
  builder.add(_uint64(kvPairs.length.toInt()));

  // Key-value pairs
  for (final entry in kvPairs.entries) {
    final keyBytes = utf8.encode(entry.key);
    builder.add(_uint64(keyBytes.length));
    builder.add(keyBytes);

    // Value type: 8 (string)
    builder.add(_uint32(8));

    final valueBytes = utf8.encode(entry.value.toString());
    builder.add(_uint64(valueBytes.length));
    builder.add(valueBytes);
  }

  return Uint8List.fromList(builder.takeBytes());
}

Uint8List _uint32(int value) {
  return Uint8List(4)..buffer.asUint32List()[0] = value;
}

Uint8List _uint64(int value) {
  return Uint8List(8)..buffer.asUint64List()[0] = value;
}

void main() {
  group('GGUFParser', () {
    test('returns null for non-existent file', () async {
      final result = await GGUFParser.getKvCacheBytesPerToken('/nonexistent/path/model.gguf');
      expect(result, isNull);
    });

    test('returns null for empty file', () async {
      final file = File('${Directory.systemTemp.path}/gguf_empty_test.gguf');
      await file.writeAsBytes([]);
      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);
      expect(result, isNull);
      await file.delete();
    });

    test('returns null for file without GGUF magic', () async {
      final file = File('${Directory.systemTemp.path}/gguf_nomagic_test.gguf');
      await file.writeAsBytes(utf8.encode('not a gguf file'));
      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);
      expect(result, isNull);
      await file.delete();
    });

    test('returns null for truncated GGUF header', () async {
      final file = File('${Directory.systemTemp.path}/gguf_truncated_test.gguf');
      await file.writeAsBytes(Uint8List(2));
      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);
      expect(result, isNull);
      await file.delete();
    });

    test('parses valid GGUF file with llama architecture', () async {
      final data = _buildGgufV3({
        'general.architecture': 'llama',
        'llama.block_count': '32',
        'llama.attention.head_count': '32',
        'llama.attention.head_count_kv': '8',
        'llama.embedding_length': '4096',
      });

      final file = File('${Directory.systemTemp.path}/gguf_llama_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);

      // head_dim = 4096/32 = 128
      // bytesPerToken = 4 * 32 * 8 * 128 = 131072
      expect(result, equals(131072));

      await file.delete();
    });

    test('parses GGUF with mistral architecture', () async {
      final data = _buildGgufV3({
        'general.architecture': 'mistral',
        'mistral.block_count': '32',
        'mistral.attention.head_count': '32',
        'mistral.attention.head_count_kv': '8',
        'mistral.embedding_length': '4096',
      });

      final file = File('${Directory.systemTemp.path}/gguf_mistral_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);

      expect(result, equals(131072));

      await file.delete();
    });

    test('parses GGUF with qwen architecture', () async {
      final data = _buildGgufV3({
        'general.architecture': 'qwen2',
        'qwen2.block_count': '24',
        'qwen2.attention.head_count': '24',
        'qwen2.attention.head_count_kv': '8',
        'qwen2.embedding_length': '2048',
      });

      final file = File('${Directory.systemTemp.path}/gguf_qwen_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);

      // head_dim = 2048/24 = 85.333...
      // bytesPerToken = 4 * 24 * 8 * 85.333 = 65536 (rounded)
      expect(result, isNotNull);
      expect(result!, greaterThan(0));

      await file.delete();
    });

    test('returns null when head_count is zero', () async {
      final data = _buildGgufV3({
        'general.architecture': 'llama',
        'llama.block_count': '32',
        'llama.attention.head_count': '0',
        'llama.attention.head_count_kv': '8',
        'llama.embedding_length': '4096',
      });

      final file = File('${Directory.systemTemp.path}/gguf_zero_heads_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);
      expect(result, isNull);

      await file.delete();
    });

    test('defaults to llama architecture when general.architecture is missing', () async {
      // The parser defaults to 'llama' when general.architecture is not present,
      // so it still computes a result using llama.* keys
      final data = _buildGgufV3({
        'llama.block_count': '32',
        'llama.attention.head_count': '32',
        'llama.embedding_length': '4096',
      });

      final file = File('${Directory.systemTemp.path}/gguf_noarch_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);

      // head_count_kv defaults to head_count = 32
      // head_dim = 4096/32 = 128
      // bytesPerToken = 4 * 32 * 32 * 128 = 524288
      expect(result, equals(524288));

      await file.delete();
    });

    test('returns null for truncated KV data', () async {
      final data = _buildGgufV3({
        'general.architecture': 'llama',
      });

      // Truncate the data mid-stream
      final truncated = Uint8List(data.length ~/ 2);
      truncated.setRange(0, data.length ~/ 2, data);

      final file = File('${Directory.systemTemp.path}/gguf_trunc_kv_test.gguf');
      await file.writeAsBytes(truncated);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);
      expect(result, isNull);

      await file.delete();
    });

    test('returns null when kv_count is zero', () async {
      final builder = BytesBuilder();
      builder.add(utf8.encode('GGUF'));
      builder.add(_uint32(3));
      builder.add(_uint64(0)); // KV count = 0
      builder.add(_uint64(0)); // Tensor count = 0

      final file = File('${Directory.systemTemp.path}/gguf_zero_kv_test.gguf');
      await file.writeAsBytes(Uint8List.fromList(builder.takeBytes()));

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);
      expect(result, isNull);

      await file.delete();
    });

    test('handles large model parameters', () async {
      final data = _buildGgufV3({
        'general.architecture': 'llama',
        'llama.block_count': '96',
        'llama.attention.head_count': '96',
        'llama.attention.head_count_kv': '8',
        'llama.embedding_length': '12288',
      });

      final file = File('${Directory.systemTemp.path}/gguf_large_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);

      // head_dim = 12288/96 = 128
      // bytesPerToken = 4 * 96 * 8 * 128 = 393216
      expect(result, equals(393216));

      await file.delete();
    });

    test('uses head_count_kv default to head_count when missing', () async {
      final data = _buildGgufV3({
        'general.architecture': 'llama',
        'llama.block_count': '32',
        'llama.attention.head_count': '32',
        'llama.embedding_length': '4096',
      });

      final file = File('${Directory.systemTemp.path}/gguf_no_kvheads_test.gguf');
      await file.writeAsBytes(data);

      final result = await GGUFParser.getKvCacheBytesPerToken(file.path);

      // head_count_kv defaults to head_count = 32
      // head_dim = 4096/32 = 128
      // bytesPerToken = 4 * 32 * 32 * 128 = 524288
      expect(result, equals(524288));

      await file.delete();
    });
  });
}
