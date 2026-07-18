// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:front_porch_ai/utils/gguf_model_info.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';

// Re-export so existing consumers importing gguf_parser.dart still resolve GGUFModelInfo.
export 'gguf_model_info.dart';

/// A lightweight parser to extract architectural parameters from GGUF files
/// without loading the full model tensors into memory.
class GGUFParser {
  /// Extracts the exact number of bytes required per token for KV cache.
  ///
  /// Delegates to [getModelArchitectureInfo] and returns [GGUFModelInfo.kvBytesPerToken].
  static Future<int?> getKvCacheBytesPerToken(String filePath) async {
    final info = await getModelArchitectureInfo(filePath);
    return info?.kvBytesPerToken;
  }

  /// Returns richer architectural metadata from the GGUF file.
  ///
  /// Returns null if the file cannot be read or is not a supported GGUF.
  static Future<GGUFModelInfo?> getModelArchitectureInfo(
    String filePath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      final bytes = await raf.read(16 * 1024 * 1024);

      // Use shared reader to get raw metadata KV pairs
      final meta = GGUFFileReader.parseMetadataBytes(bytes);
      if (meta == null) return null;

      final arch = meta['general.architecture'] as String? ?? 'llama';
      final dynamic nLayersDyn = meta['$arch.block_count'];
      final dynamic nHeadsDyn = meta['$arch.attention.head_count'];
      final dynamic nKvHeadsDyn =
          meta['$arch.attention.head_count_kv'] ?? nHeadsDyn;
      final dynamic nEmbdDyn = meta['$arch.embedding_length'];
      final dynamic expertCountDyn = meta['$arch.expert_count'];
      final dynamic expertUsedDyn = meta['$arch.expert_used_count'];
      final dynamic expertFfnDyn = meta['$arch.expert_feed_forward_length'];
      final dynamic expertSharedFfnDyn =
          meta['$arch.expert_shared_feed_forward_length'];
      final dynamic ffnDimDyn = meta['$arch.feed_forward_length'];
      final dynamic slidingWindowDyn = meta['$arch.sliding_window'];
      final dynamic nVocabDyn = meta['tokenizer.ggml.tokens'];
      final dynamic keyLengthDyn = meta['$arch.attention.key_length'];
      final dynamic fullAttentionIntervalDyn =
          meta['$arch.full_attention_interval'];
      final dynamic leadingDenseBlockCountDyn =
          meta['$arch.leading_dense_block_count'];

      if (nLayersDyn != null && nHeadsDyn != null && nEmbdDyn != null) {
        final int nLayers = GGUFFileReader.toInt(nLayersDyn);
        final int nHeads = GGUFFileReader.toInt(nHeadsDyn);

        final List<int>? nKvHeadsPerLayer;
        final int nKvHeads;
        if (nKvHeadsDyn is List) {
          final list = GGUFFileReader.toIntList(nKvHeadsDyn);
          if (list.length == nLayers) {
            nKvHeadsPerLayer = list;
            nKvHeads = list.reduce((a, b) => a > b ? a : b);
          } else {
            nKvHeadsPerLayer = null;
            nKvHeads = GGUFFileReader.toInt(nKvHeadsDyn);
          }
        } else {
          nKvHeadsPerLayer = null;
          nKvHeads =
              nKvHeadsDyn != null ? GGUFFileReader.toInt(nKvHeadsDyn) : nHeads;
        }

        final int nEmbd = GGUFFileReader.toInt(nEmbdDyn);

        final int headDim;
        final int keyLength;
        if (keyLengthDyn != null) {
          keyLength = GGUFFileReader.toInt(keyLengthDyn);
          headDim = keyLength;
        } else {
          keyLength = nHeads > 0 ? (nEmbd / nHeads).round() : 0;
          headDim = (nEmbd / nHeads).round();
        }

        final int kvBytesPerToken;
        if (nKvHeadsPerLayer != null && nKvHeadsPerLayer.length == nLayers) {
          int total = 0;
          for (final kv in nKvHeadsPerLayer) {
            final effectiveKv = kv > 0 ? kv : nHeads;
            total += (4 * effectiveKv * headDim).round();
          }
          kvBytesPerToken = total;
        } else {
          kvBytesPerToken = (4 * nLayers * nKvHeads * headDim).round();
        }

        final int? expertCount =
            expertCountDyn != null ? GGUFFileReader.toInt(expertCountDyn) : null;
        final int? expertUsedCount =
            expertUsedDyn != null ? GGUFFileReader.toInt(expertUsedDyn) : null;
        final int? expertFfnDim =
            expertFfnDyn != null ? GGUFFileReader.toInt(expertFfnDyn) : null;
        final int? expertSharedFfnDim = expertSharedFfnDyn != null
            ? GGUFFileReader.toInt(expertSharedFfnDyn)
            : null;
        final int? ffnDim =
            ffnDimDyn != null ? GGUFFileReader.toInt(ffnDimDyn) : null;
        final int? slidingWindow = slidingWindowDyn != null
            ? GGUFFileReader.toInt(slidingWindowDyn)
            : null;
        final int? nVocab =
            nVocabDyn != null ? GGUFFileReader.toInt(nVocabDyn) : null;
        final int? fullAttentionInterval = fullAttentionIntervalDyn != null
            ? GGUFFileReader.toInt(fullAttentionIntervalDyn)
            : null;
        final int? leadingDenseBlockCount = leadingDenseBlockCountDyn != null
            ? GGUFFileReader.toInt(leadingDenseBlockCountDyn)
            : null;

        if (nHeads > 0) {
          final int? swaHeadDim;
          if (arch.toLowerCase().contains('gemma4') && headDim > 0) {
            swaHeadDim = headDim ~/ 2;
          } else {
            swaHeadDim = null;
          }

          return GGUFModelInfo(
            nLayers: nLayers,
            nHeads: nHeads,
            nKvHeads: nKvHeads,
            nEmbd: nEmbd,
            kvBytesPerToken: kvBytesPerToken,
            expertCount: expertCount,
            expertUsedCount: expertUsedCount,
            expertFfnDim: expertFfnDim,
            expertSharedFfnDim: expertSharedFfnDim,
            ffnDim: ffnDim,
            slidingWindow: slidingWindow,
            nVocab: nVocab,
            nKvHeadsPerLayer: nKvHeadsPerLayer,
            keyLength: headDim > 0 ? headDim : null,
            swaHeadDim: swaHeadDim,
            fullAttentionInterval: fullAttentionInterval,
            leadingDenseBlockCount: leadingDenseBlockCount,
          );
        }
      }
    } catch (e) {
      print('Failed to parse GGUF architecture info: $e');
    } finally {
      await raf.close();
    }
    return null;
  }
}
