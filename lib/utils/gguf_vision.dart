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

/// Vision-relevant facts distilled from a single GGUF file's metadata header.
///
/// This is deliberately kept separate from [GGUFParser] in `gguf_parser.dart`:
/// that file is at the 500-line cap and its KV-byte math feeds VRAM/layer
/// solving, which we must not risk regressing. Vision detection is a distinct
/// concern with its own (small, self-contained) header walk.
class GgufVisionInfo {
  /// `general.architecture` as reported by the file (lower-cased), or ''.
  final String architecture;

  /// True when the file itself carries a vision projector — either `clip.*`
  /// metadata keys or vision/clip tensors (e.g. `v.blk.*`, `mm.*`,
  /// `vision_tower.*`, `multi_modal_projector.*`). Such a model can do vision
  /// with no separate mmproj file.
  final bool hasEmbeddedProjector;

  /// True when the model is multimodal in principle: it has an embedded
  /// projector, OR carries `<arch>.vision.*` / `clip.*` metadata, OR its
  /// architecture is one that is always vision-capable (e.g. `mllama`,
  /// `qwen2vl`). A multimodal model with no embedded projector needs a matching
  /// mmproj file passed to KoboldCpp to actually see images.
  final bool isMultimodal;

  const GgufVisionInfo({
    required this.architecture,
    required this.hasEmbeddedProjector,
    required this.isMultimodal,
  });

  /// True only when the model is multimodal but the projector is NOT baked in,
  /// i.e. the user must supply a matching mmproj file to unlock vision.
  bool get needsExternalProjector => isMultimodal && !hasEmbeddedProjector;

  /// True when the model has no vision capability at all (pure text model).
  bool get isTextOnly => !isMultimodal;
}

/// Reads the metadata header of a GGUF file to determine whether it is a
/// vision-capable model. Pure with respect to the app (only touches the file
/// system) so it is straightforward to unit test with synthetic GGUF bytes.
class GgufVisionParser {
  /// Architectures that are ALWAYS multimodal in llama.cpp / KoboldCpp. These
  /// are safe positives even when the main model file carries no explicit
  /// vision metadata (the vision config typically lives in the mmproj file).
  ///
  /// Deliberately conservative: architectures with common text-only variants
  /// (e.g. `gemma3`, `mistral3`) are NOT listed here — they are only treated as
  /// multimodal when actual vision metadata/tensors are present, to avoid
  /// falsely telling users a pure-text model "needs an mmproj".
  static const Set<String> alwaysMultimodalArches = {
    'clip',
    'mllama',
    'qwen2vl',
    'qwen2.5vl',
    'qwen25vl',
    'qwen3vl',
    'pixtral',
    'idefics3',
    'smolvlm',
    'llava',
    'llava_next',
    'minicpmv',
    'mobilevlm',
    'internvl',
    'cohere2vision',
  };

  /// Substrings that identify a vision/projector tensor by name.
  static const List<String> _visionTensorMarkers = [
    'v.blk',
    'mm.',
    'vision_tower',
    'multi_modal_projector',
    'mmproj',
    'vision_model',
    'vision.',
  ];

  /// Parse [filePath] and return its [GgufVisionInfo], or null when the file is
  /// missing / unreadable / not a supported GGUF.
  static Future<GgufVisionInfo?> getVisionInfo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      // The metadata header (and, for most models, the tensor-info table) lives
      // well within the first few MB; we never need the tensor data itself.
      final bytes = await raf.read(4 * 1024 * 1024);
      return _detect(bytes);
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Core detection over an in-memory GGUF header buffer. Extracted so tests can
  /// exercise the logic directly on synthetic bytes without a file.
  static GgufVisionInfo? _detect(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    int offset = 0;

    if (bytes.length < 4) return null;
    if (utf8.decode(bytes.sublist(0, 4), allowMalformed: true) != 'GGUF') {
      return null;
    }
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

    String arch = '';
    bool hasClipKey = false;
    bool hasVisionKey = false;
    bool overflowed = false;

    // ── Walk the key/value metadata ────────────────────────────────────────
    for (var i = 0; i < kvCount; i++) {
      if (offset + 8 > bytes.length) {
        overflowed = true;
        break;
      }
      final keyLen = data.getUint64(offset, Endian.little).toInt();
      offset += 8;
      if (offset + keyLen > bytes.length) {
        overflowed = true;
        break;
      }
      final key = utf8
          .decode(bytes.sublist(offset, offset + keyLen), allowMalformed: true)
          .toLowerCase();
      offset += keyLen;

      if (offset + 4 > bytes.length) {
        overflowed = true;
        break;
      }
      final valType = data.getUint32(offset, Endian.little);
      offset += 4;

      String? stringValue;
      try {
        final read = _skipValue(data, bytes, offset, valType);
        offset = read.$1;
        stringValue = read.$2;
      } catch (_) {
        overflowed = true;
        break;
      }

      if (key.startsWith('clip.')) hasClipKey = true;
      if (key.contains('.vision.') || key.contains('vision_')) {
        hasVisionKey = true;
      }
      if (key == 'general.architecture' && stringValue != null) {
        arch = stringValue.toLowerCase().trim();
      }
    }

    // ── Walk the tensor-info table for projector tensors ───────────────────
    // Only attempted when the KV walk stayed within the buffer; otherwise the
    // offset is unreliable. Missing this table simply falls back to
    // metadata/architecture signals.
    bool hasVisionTensor = false;
    if (!overflowed) {
      for (var i = 0; i < tensorCount; i++) {
        if (offset + 8 > bytes.length) break;
        final nameLen = data.getUint64(offset, Endian.little).toInt();
        offset += 8;
        if (nameLen < 0 || offset + nameLen > bytes.length) break;
        final name = utf8
            .decode(bytes.sublist(offset, offset + nameLen),
                allowMalformed: true)
            .toLowerCase();
        offset += nameLen;

        if (!hasVisionTensor &&
            _visionTensorMarkers.any((m) => name.contains(m))) {
          hasVisionTensor = true;
        }

        // Skip dims (uint32 n + n×uint64), type (uint32), offset (uint64).
        if (offset + 4 > bytes.length) break;
        final nDims = data.getUint32(offset, Endian.little);
        offset += 4;
        offset += nDims * 8; // dimensions
        offset += 4; // ggml type
        offset += 8; // tensor data offset
        if (offset > bytes.length) break;
      }
    }

    final hasEmbeddedProjector = hasClipKey || hasVisionTensor;
    final isMultimodal = hasEmbeddedProjector ||
        hasVisionKey ||
        alwaysMultimodalArches.contains(arch);

    return GgufVisionInfo(
      architecture: arch,
      hasEmbeddedProjector: hasEmbeddedProjector,
      isMultimodal: isMultimodal,
    );
  }

  /// Advance [offset] past a single GGUF metadata value of the given [valType],
  /// returning the new offset and, for string values, the decoded string.
  /// Throws (via ByteData range errors) when a value runs past the buffer; the
  /// caller treats that as a clean stop.
  static (int, String?) _skipValue(
    ByteData data,
    Uint8List bytes,
    int offset,
    int valType,
  ) {
    switch (valType) {
      case 0: // uint8
      case 1: // int8
      case 7: // bool
        return (offset + 1, null);
      case 2: // uint16
      case 3: // int16
        return (offset + 2, null);
      case 4: // uint32
      case 5: // int32
      case 6: // float32
        return (offset + 4, null);
      case 10: // uint64
      case 11: // int64
      case 12: // float64
        return (offset + 8, null);
      case 8: // string
        final len = data.getUint64(offset, Endian.little).toInt();
        offset += 8;
        final s = utf8.decode(
          bytes.sublist(offset, offset + len),
          allowMalformed: true,
        );
        return (offset + len, s);
      case 9: // array
        final arrType = data.getUint32(offset, Endian.little);
        offset += 4;
        final arrLen = data.getUint64(offset, Endian.little).toInt();
        offset += 8;
        if (arrType == 8) {
          for (var j = 0; j < arrLen; j++) {
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
        return (offset, null);
      default:
        // Unknown type — we can't know its width, so stop the walk.
        throw const FormatException('Unknown GGUF value type');
    }
  }
}
