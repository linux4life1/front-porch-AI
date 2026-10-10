// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:image/image.dart' as img;

/// Shared PNG tEXt / iTXt chunk utilities for character cards and group cards.
///
/// These helpers provide reliable extraction that works even for cards created
/// by external tools (the `image` package's textData handling is not always
/// sufficient for third-party PNGs).
class PngMetadataUtils {
  /// Extracts the text payload for a given keyword from a PNG's tEXt or iTXt chunks.
  ///
  /// Returns null if the PNG signature is invalid, the keyword is not found,
  /// or the chunk is malformed.
  ///
  /// Supports both uncompressed tEXt and iTXt (international text) chunks.
  static String? extractTextChunk(List<int> bytes, String keyword) {
    if (bytes.length < 8) return null;

    // PNG signature
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return null;
    }

    int offset = 8;

    while (offset + 12 <= bytes.length) {
      final length =
          (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;

      final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;

      final dataStart = offset;
      final dataEnd = offset + length;

      if (dataEnd + 4 > bytes.length) break;

      if (type == 'tEXt' || type == 'iTXt') {
        final text = _parseTextChunk(
          bytes.sublist(dataStart, dataEnd),
          type,
          keyword,
        );
        if (text != null) return text;
      }

      offset = dataEnd + 4;

      if (type == 'IEND') break;
    }

    return null;
  }

  /// Decodes ONE tEXt/iTXt chunk's payload, returning its text when the chunk
  /// carries [keyword]. Shared by the in-memory walker above and the seeking
  /// file walker below so the two can never disagree about how a chunk decodes.
  static String? _parseTextChunk(List<int> data, String type, String keyword) {
    final nullIndex = data.indexOf(0);
    if (nullIndex == -1) return null;
    final chunkKeyword = String.fromCharCodes(data.sublist(0, nullIndex));
    if (chunkKeyword != keyword) return null;

    if (type == 'tEXt') {
      return String.fromCharCodes(data.sublist(nullIndex + 1));
    }

    // iTXt layout after keyword\0:
    // compressionFlag(1), compressionMethod(1), languageTag\0,
    // translatedKeyword\0, text
    int pos = nullIndex + 1;
    if (pos + 2 > data.length) return null;
    pos += 2; // skip flags
    while (pos < data.length && data[pos] != 0) {
      pos++;
    }
    pos++; // skip language null
    while (pos < data.length && data[pos] != 0) {
      pos++;
    }
    pos++; // skip translated keyword null
    if (pos >= data.length) return null;
    return utf8.decode(data.sublist(pos));
  }

  /// Extracts [keyword]'s text payload by SEEKING through the PNG's chunk table
  /// instead of loading the file.
  ///
  /// A character card's `chara` chunk is a few KB of JSON sitting in a header
  /// chunk, but the file around it is a multi-megabyte image. Reading the whole
  /// thing to reach it made opening the library pull ~142 MB off disk for 120
  /// cards — measured at 501-743 ms, and worse on Windows where the antivirus
  /// inspects every one of those megabyte reads. Walking the chunk table reads
  /// only 8-byte headers and the matching chunk, skipping IDAT entirely, which
  /// measured ~9x faster and does not grow with the artwork's size.
  ///
  /// Returns null on a non-PNG, a truncated file, or a missing keyword — the
  /// same contract as [extractTextChunk], so callers can fall back to the
  /// whole-file path unchanged.
  static Future<String?> extractTextChunkFromFile(
    String path,
    String keyword,
  ) async {
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      final signature = await handle.read(8);
      if (signature.length < 8) return null;
      const expected = [137, 80, 78, 71, 13, 10, 26, 10];
      for (var i = 0; i < 8; i++) {
        if (signature[i] != expected[i]) return null;
      }

      final length = await handle.length();
      var offset = 8;
      while (offset + 12 <= length) {
        final header = await handle.read(8);
        if (header.length < 8) return null;
        final dataLength =
            (header[0] << 24) |
            (header[1] << 16) |
            (header[2] << 8) |
            header[3];
        final type = String.fromCharCodes(header.sublist(4, 8));
        final dataStart = offset + 8;
        if (dataStart + dataLength + 4 > length) return null;

        if (type == 'tEXt' || type == 'iTXt') {
          final data = await handle.read(dataLength);
          if (data.length < dataLength) return null;
          final text = _parseTextChunk(data, type, keyword);
          if (text != null) return text;
        } else if (type == 'IEND') {
          return null;
        }

        // Seek past this chunk's payload + CRC. Non-text payloads are never
        // read at all — that is the whole point: IDAT stays on disk.
        offset = dataStart + dataLength + 4;
        await handle.setPosition(offset);
      }
      return null;
    } catch (_) {
      // Unreadable/malformed: let the caller fall back to the byte path.
      return null;
    } finally {
      await handle?.close();
    }
  }

  /// Encodes an [image] as PNG with an additional uncompressed tEXt chunk.
  ///
  /// The [keyword] (max 79 bytes, ASCII) and [text] payload are stored in a
  /// standard tEXt chunk so tools like SillyTavern ignore it (they only look
  /// for the 'chara' chunk). Front Porch group cards use the 'fpa_group' keyword.
  ///
  /// This re-uses the `image` package's built-in textData support for maximum
  /// compatibility with how V2 character cards are already written.
  static List<int> encodeWithTextChunk(
    img.Image image,
    String keyword,
    String text,
  ) {
    image.textData ??= {};
    image.textData![keyword] = text;
    return img.encodePng(image);
  }

  /// Replaces the text of the first tEXt/iTXt chunk carrying [keyword] — the
  /// chunk [extractTextChunk] reads — without decoding the image: every other
  /// chunk, IDAT included, is copied byte for byte and in order. Returns null
  /// when that chunk is missing, is iTXt, or the PNG is malformed. [text] is
  /// Latin-1 (base64 card data), as tEXt requires.
  static Uint8List? replaceTextChunk(
    List<int> bytes,
    String keyword,
    String text,
  ) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8) return null;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length =
          (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final next = dataStart + length + 4;
      if (next > bytes.length) return null;
      if (type == 'tEXt' || type == 'iTXt') {
        final data = bytes.sublist(dataStart, dataStart + length);
        if (_parseTextChunk(data, type, keyword) != null) {
          if (type == 'iTXt') return null;
          final body = [...latin1.encode(keyword), 0, ...latin1.encode(text)];
          final typed = [...ascii.encode('tEXt'), ...body];
          final crc = getCrc32(typed);
          return Uint8List.fromList([
            ...bytes.sublist(0, offset),
            ..._u32(body.length),
            ...typed,
            ..._u32(crc),
            ...bytes.sublist(next),
          ]);
        }
      }
      if (type == 'IEND') return null;
      offset = next;
    }
    return null;
  }

  static List<int> _u32(int v) => [
    (v >> 24) & 0xff,
    (v >> 16) & 0xff,
    (v >> 8) & 0xff,
    v & 0xff,
  ];
}
