// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Shared low-level GGUF binary reader.
///
/// Validates the header, iterates KV pairs, and decodes values. Handles arrays
/// of interest (vocab size, per-layer `head_count_kv`) and skips the rest.
/// Used by [GGUFParser] methods to avoid duplicating the byte-level loop.
class GGUFFileReader {
  /// Opens [filePath], reads up to [readSize] bytes, and parses all metadata
  /// KV pairs. Returns null if the file is invalid or truncated.
  static Future<Map<String, dynamic>?> readMetadata(
    String filePath, {
    int readSize = 16 * 1024 * 1024,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      final bytes = await raf.read(readSize);
      return parseMetadataBytes(bytes);
    } finally {
      await raf.close();
    }
  }

  /// Parse metadata from an in-memory byte buffer.
  /// Public for use by [GGUFParser] which already has the file open.
  static Map<String, dynamic>? parseMetadataBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    int offset = 0;

    if (bytes.length < 4) return null;
    final magic = utf8.decode(bytes.sublist(0, 4), allowMalformed: true);
    if (magic != 'GGUF') return null;
    offset += 4;

    if (offset + 4 > bytes.length) return null;
    final version = data.getUint32(offset, Endian.little);
    offset += 4;
    if (version > 3) return null;

    if (offset + 8 > bytes.length) return null;
    offset += 8;

    if (offset + 8 > bytes.length) return null;
    final kvCount = data.getUint64(offset, Endian.little);
    offset += 8;

    final meta = <String, dynamic>{};

    for (var i = 0; i < kvCount; i++) {
      if (offset + 8 > bytes.length) break;
      final keyLen = data.getUint64(offset, Endian.little);
      offset += 8;

      if (offset + keyLen > bytes.length) break;
      final key = utf8.decode(
        bytes.sublist(offset, offset + keyLen.toInt()),
        allowMalformed: true,
      );
      offset += keyLen.toInt();

      if (offset + 4 > bytes.length) break;
      final valType = data.getUint32(offset, Endian.little);
      offset += 4;

      if (valType == 9) {
        if (offset + 4 > bytes.length) break;
        final arrType = data.getUint32(offset, Endian.little);
        offset += 4;
        if (offset + 8 > bytes.length) break;
        final arrLen = data.getUint64(offset, Endian.little).toInt();
        offset += 8;

        if (key == 'tokenizer.ggml.tokens') {
          meta[key] = arrLen;
          for (var j = 0; j < arrLen; j++) {
            if (offset + 8 > bytes.length) break;
            final l = data.getUint64(offset, Endian.little).toInt();
            offset += 8 + l;
          }
        } else if (key.endsWith('.attention.head_count_kv') &&
            arrType >= 0 && arrType <= 6) {
          // Element size by arrType: 0/1 -> 1 byte, 2/3 -> 2, 4/5/6 -> 4.
          final int elemSize = arrType <= 1 ? 1 : (arrType <= 3 ? 2 : 4);
          final values = <int>[];
          for (var j = 0; j < arrLen; j++) {
            // Stop cleanly if the array runs past the loaded header buffer,
            // matching the bounds-check pattern used for every other read here
            // (preserves the RangeError fix from Rawhide's 82dccf5).
            if (offset + elemSize > bytes.length) break;
            int v;
            if (arrType == 0) { v = data.getUint8(offset); offset += 1; }
            else if (arrType == 1) { v = data.getInt8(offset); offset += 1; }
            else if (arrType == 2) { v = data.getUint16(offset, Endian.little); offset += 2; }
            else if (arrType == 3) { v = data.getInt16(offset, Endian.little); offset += 2; }
            else if (arrType == 4) { v = data.getUint32(offset, Endian.little); offset += 4; }
            else if (arrType == 5) { v = data.getInt32(offset, Endian.little); offset += 4; }
            else { v = data.getFloat32(offset, Endian.little).toInt(); offset += 4; }
            values.add(v);
          }
          meta[key] = values;
        } else {
          if (arrType == 8) {
            for (var j = 0; j < arrLen; j++) {
              if (offset + 8 > bytes.length) break;
              final l = data.getUint64(offset, Endian.little).toInt();
              offset += 8 + l;
            }
          } else {
            int size = 0;
            if (arrType == 0 || arrType == 1 || arrType == 7) {
              size = 1;
            } else if (arrType == 2 || arrType == 3) {
              size = 2;
            } else if (arrType >= 4 && arrType <= 6) {
              size = 4;
            } else if (arrType >= 10 && arrType <= 12) {
              size = 8;
            }
            offset += arrLen * size;
          }
        }
      } else {
        final result = _readScalar(data, offset, bytes.length, valType);
        if (result != null) {
          meta[key] = result.value;
          offset = result.newOffset;
        }
      }
    }

    return meta;
  }

  static _ScalarResult? _readScalar(
    ByteData data,
    int offset,
    int byteLength,
    int valType,
  ) {
    switch (valType) {
      case 0:
        if (offset + 1 > byteLength) return null;
        return _ScalarResult(data.getUint8(offset), offset + 1);
      case 1:
        if (offset + 1 > byteLength) return null;
        return _ScalarResult(data.getInt8(offset), offset + 1);
      case 2:
        if (offset + 2 > byteLength) return null;
        return _ScalarResult(data.getUint16(offset, Endian.little), offset + 2);
      case 3:
        if (offset + 2 > byteLength) return null;
        return _ScalarResult(data.getInt16(offset, Endian.little), offset + 2);
      case 4:
        if (offset + 4 > byteLength) return null;
        return _ScalarResult(data.getUint32(offset, Endian.little), offset + 4);
      case 5:
        if (offset + 4 > byteLength) return null;
        return _ScalarResult(data.getInt32(offset, Endian.little), offset + 4);
      case 6:
        if (offset + 4 > byteLength) return null;
        return _ScalarResult(data.getFloat32(offset, Endian.little), offset + 4);
      case 7:
        if (offset + 1 > byteLength) return null;
        return _ScalarResult(data.getUint8(offset) != 0, offset + 1);
      case 8: {
        if (offset + 8 > byteLength) return null;
        final strLen = data.getUint64(offset, Endian.little).toInt();
        offset += 8;
        if (offset + strLen > byteLength) return null;
        return _ScalarResult(
          utf8.decode(
            // offset is relative to the ByteData view, so add its base offset
            // to address the underlying buffer correctly even for sub-views.
            data.buffer.asUint8List(data.offsetInBytes + offset, strLen),
            allowMalformed: true,
          ),
          offset + strLen,
        );
      }
      case 10:
        if (offset + 8 > byteLength) return null;
        return _ScalarResult(data.getUint64(offset, Endian.little), offset + 8);
      case 11:
        if (offset + 8 > byteLength) return null;
        return _ScalarResult(data.getInt64(offset, Endian.little), offset + 8);
      case 12:
        if (offset + 8 > byteLength) return null;
        return _ScalarResult(data.getFloat64(offset, Endian.little), offset + 8);
    }
    return null;
  }

  /// Convert a dynamic GGUF value to [int].
  static int toInt(dynamic v) =>
      v is int ? v : int.tryParse(v.toString()) ?? 0;

  /// Convert a dynamic GGUF value to [List<int>].
  static List<int> toIntList(dynamic v) {
    if (v is List<int>) return v;
    if (v is List) {
      if (v.every((e) => e is int)) return List<int>.from(v);
      return v.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).toList();
    }
    return [];
  }
}

class _ScalarResult {
  final dynamic value;
  final int newOffset;
  const _ScalarResult(this.value, this.newOffset);
}
