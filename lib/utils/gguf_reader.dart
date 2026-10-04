// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One entry of a GGUF file's tensor table: what the tensor is called, its
/// shape and type, and where its data starts (counted from the start of the
/// file's data section).
class GGUFTensorInfo {
  const GGUFTensorInfo(this.name, this.dims, this.type, this.offset);
  final String name;
  final List<int> dims;
  final int type;
  final int offset;
}

/// A GGUF file's header: its metadata and its tensor table.
class GGUFHeader {
  const GGUFHeader({
    required this.meta,
    required this.tensors,
    required this.dataStart,
  });

  final Map<String, dynamic> meta;

  /// Empty when the table did not fit in the bytes that were read.
  final List<GGUFTensorInfo> tensors;

  /// Where the tensor data begins in the file. 0 when [tensors] is empty.
  final int dataStart;

  /// The size in bytes of every tensor, exact, without reading any weights:
  /// the data of each tensor runs up to where the next one starts, and
  /// [fileSize] closes the last one.
  Map<String, int> tensorSizes(int fileSize) {
    final order = [...tensors]..sort((a, b) => a.offset.compareTo(b.offset));
    final sizes = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      final end = i + 1 < order.length
          ? order[i + 1].offset
          : fileSize - dataStart;
      sizes[order[i].name] = (end - order[i].offset).clamp(0, fileSize);
    }
    return sizes;
  }
}

/// Shared low-level GGUF binary reader.
///
/// Validates the header, iterates KV pairs, and decodes values. Keeps short
/// arrays of numbers and booleans (per-layer `head_count_kv`, the sliding
/// window pattern), the vocabulary's size, and the tensor table; skips the
/// tokenizer's long lists.
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
  static Map<String, dynamic>? parseMetadataBytes(Uint8List bytes) =>
      parseHeaderBytes(bytes)?.meta;

  /// Arrays of numbers or booleans up to this long are kept as lists.
  static const int _keptArrayLength = 4096;

  /// Parse the metadata and the tensor table from the start of a file.
  /// Null when [bytes] is not the start of a GGUF file.
  static GGUFHeader? parseHeaderBytes(Uint8List bytes) {
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
    final tensorCount = data.getUint64(offset, Endian.little);
    offset += 8;

    if (offset + 8 > bytes.length) return null;
    final kvCount = data.getUint64(offset, Endian.little);
    offset += 8;

    final meta = <String, dynamic>{};
    var keysRead = 0;

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

        if (arrType == 8) {
          // A list of strings. Only its length is ever wanted (the
          // vocabulary's size); the strings themselves are skipped.
          if (key == 'tokenizer.ggml.tokens') meta[key] = arrLen;
          var complete = true;
          for (var j = 0; j < arrLen; j++) {
            if (offset + 8 > bytes.length) {
              complete = false;
              break;
            }
            // A length past the end, or one over 2^63 that reads back as
            // negative and would never move the offset on.
            final len = data.getUint64(offset, Endian.little);
            if (len < 0 || len > bytes.length - offset - 8) {
              complete = false;
              break;
            }
            offset += 8 + len;
          }
          if (!complete || offset > bytes.length) break;
        } else {
          final elemSize = _scalarSize(arrType);
          if (elemSize == 0) break;
          if (offset + arrLen * elemSize > bytes.length) break;
          if (arrLen <= _keptArrayLength) {
            final values = <dynamic>[];
            for (var j = 0; j < arrLen; j++) {
              values.add(
                _readScalar(data, offset, bytes.length, arrType)!.value,
              );
              offset += elemSize;
            }
            // Whole numbers come back as a list of int, as before.
            meta[key] = values.every((v) => v is int)
                ? List<int>.from(values)
                : values.every((v) => v is double)
                ? [for (final v in values) (v as double).toInt()]
                : values;
          } else {
            offset += arrLen * elemSize;
          }
        }
      } else {
        final result = _readScalar(data, offset, bytes.length, valType);
        if (result == null) break;
        meta[key] = result.value;
        offset = result.newOffset;
      }
      keysRead++;
    }

    // The tensor table follows the metadata. It is only read when every key
    // before it was, since nothing says where it starts otherwise.
    final tensors = <GGUFTensorInfo>[];
    var tableComplete = keysRead == kvCount;
    if (tableComplete) {
      for (var i = 0; i < tensorCount; i++) {
        if (offset + 8 > bytes.length) {
          tableComplete = false;
          break;
        }
        final nameLen = data.getUint64(offset, Endian.little).toInt();
        offset += 8;
        if (offset + nameLen + 4 > bytes.length) {
          tableComplete = false;
          break;
        }
        final name = utf8.decode(
          bytes.sublist(offset, offset + nameLen),
          allowMalformed: true,
        );
        offset += nameLen;
        final nDims = data.getUint32(offset, Endian.little);
        offset += 4;
        if (offset + 8 * nDims + 12 > bytes.length) {
          tableComplete = false;
          break;
        }
        final dims = [
          for (var d = 0; d < nDims; d++)
            data.getUint64(offset + 8 * d, Endian.little),
        ];
        offset += 8 * nDims;
        final type = data.getUint32(offset, Endian.little);
        offset += 4;
        tensors.add(
          GGUFTensorInfo(
            name,
            dims,
            type,
            data.getUint64(offset, Endian.little),
          ),
        );
        offset += 8;
      }
    }
    if (!tableComplete) tensors.clear();

    final alignment = toInt(meta['general.alignment'] ?? 32);
    final align = alignment > 0 ? alignment : 32;
    return GGUFHeader(
      meta: meta,
      tensors: tensors,
      dataStart: tensors.isEmpty ? 0 : (offset + align - 1) ~/ align * align,
    );
  }

  /// Bytes one value of a GGUF scalar type takes; 0 for a type that is not
  /// a scalar.
  static int _scalarSize(int type) => switch (type) {
    0 || 1 || 7 => 1,
    2 || 3 => 2,
    4 || 5 || 6 => 4,
    10 || 11 || 12 => 8,
    _ => 0,
  };

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
        return _ScalarResult(
          data.getFloat32(offset, Endian.little),
          offset + 4,
        );
      case 7:
        if (offset + 1 > byteLength) return null;
        return _ScalarResult(data.getUint8(offset) != 0, offset + 1);
      case 8:
        {
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
        return _ScalarResult(
          data.getFloat64(offset, Endian.little),
          offset + 8,
        );
    }
    return null;
  }

  /// Convert a dynamic GGUF value to [int].
  static int toInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;

  /// Convert a dynamic GGUF value to [List<int>].
  static List<int> toIntList(dynamic v) {
    if (v is List<int>) return v;
    if (v is List) {
      if (v.every((e) => e is int)) return List<int>.from(v);
      return v
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .toList();
    }
    return [];
  }
}

class _ScalarResult {
  final dynamic value;
  final int newOffset;
  const _ScalarResult(this.value, this.newOffset);
}
