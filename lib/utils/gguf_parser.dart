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

  /// How much of the file is read for the header. The metadata and the
  /// tensor table of current models take 5 to 16 MB; when the first read
  /// does not reach the end of the tensor table, the larger one is tried.
  static const List<int> _headerReads = [16 * 1024 * 1024, 64 * 1024 * 1024];

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
      final fileSize = await raf.length();
      GGUFHeader? header;
      for (final size in _headerReads) {
        await raf.setPosition(0);
        header = GGUFFileReader.parseHeaderBytes(await raf.read(size));
        if (header == null) return null;
        if (header.tensors.isNotEmpty || fileSize <= size) break;
      }
      return modelInfoFromHeader(header!, fileSize: fileSize);
    } catch (e) {
      print('Failed to parse GGUF architecture info: $e');
    } finally {
      await raf.close();
    }
    return null;
  }

  /// The model info a parsed [header] gives. [fileSize] is the size of the
  /// whole file; it closes the last tensor, so the weights add up exactly.
  static GGUFModelInfo? modelInfoFromHeader(
    GGUFHeader header, {
    required int fileSize,
  }) {
    final meta = header.meta;
    final arch = meta['general.architecture'] as String? ?? 'llama';
    int? number(String key) {
      final v = meta['$arch.$key'];
      return v == null || v is List ? null : GGUFFileReader.toInt(v);
    }

    // Some models give a value per layer; the largest is what sizes memory.
    int? largest(String key) {
      final v = meta['$arch.$key'];
      if (v is! List) return number(key);
      final values = GGUFFileReader.toIntList(v);
      return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
    }

    final blockCount = number('block_count');
    final nHeads = largest('attention.head_count');
    final nEmbd = number('embedding_length');
    if (blockCount == null || nHeads == null || nEmbd == null || nHeads <= 0) {
      return null;
    }
    // Real models have fewer than 200 blocks. A count far past that is a
    // broken or hostile file, and every per-layer list below would follow it.
    if (blockCount <= 0 || blockCount > 4096) return null;

    final kvHeadsRaw = meta['$arch.attention.head_count_kv'];
    final kvHeadsPerLayer = kvHeadsRaw is List
        ? GGUFFileReader.toIntList(kvHeadsRaw)
        : null;
    final nKvHeads = kvHeadsPerLayer != null
        ? kvHeadsPerLayer.fold(0, (a, b) => a > b ? a : b)
        : (number('attention.head_count_kv') ?? nHeads);

    final keyLength = number('attention.key_length') ?? (nEmbd ~/ nHeads);
    final valueLength = number('attention.value_length') ?? keyLength;
    final keyLengthSwa = number('attention.key_length_swa') ?? keyLength;
    final valueLengthSwa = number('attention.value_length_swa') ?? valueLength;
    // The real key. `<arch>.sliding_window`, without "attention", is in no
    // model file; reading that one meant sliding window was never seen.
    final slidingWindow = number('attention.sliding_window');
    final pattern = meta['$arch.attention.sliding_window_pattern'];
    final interval = number('full_attention_interval') ?? 0;
    final recurrent = meta['$arch.attention.recurrent_layers'];
    // Blocks that only predict draft tokens come last and keep no cache of
    // their own. A count outside the model's own blocks is a broken or
    // hostile file, and the loop below runs on what is left.
    final draftHeads = (number('nextn_predict_layers') ?? 0).clamp(
      0,
      blockCount,
    );
    final layers = blockCount - draftHeads;
    // Gemma 4's smaller models reuse earlier layers' cache in their last
    // layers (E4B: the last 18 of 42), which keep none of their own.
    final ownCache =
        layers - (number('attention.shared_kv_layers') ?? 0).clamp(0, layers);
    // A compressed-attention model (DeepSeek's MLA: Kimi, DeepSeek V2/V3)
    // caches one latent row per layer; its values are read from the same
    // row, so they take nothing. Kimi-VL-A3B: 576 x 2 bytes a cell, 27
    // layers, 493.59 MiB at 16k.
    final latentOnly = (number('attention.kv_lora_rank') ?? 0) > 0;

    bool flag(dynamic list, int i) =>
        list is List && i < list.length && (list[i] == true || list[i] == 1);

    final kvLayers = <GGUFKvLayer>[];
    var recurrentLayers = 0;
    var convLayers = 0;
    for (var i = 0; i < layers; i++) {
      // A recurrent layer has no attention cache. Newer Qwen models say
      // which layers attend with an interval: every Nth one does.
      final isRecurrent = recurrent is List
          ? flag(recurrent, i)
          : interval > 1 && (i + 1) % interval != 0;
      if (isRecurrent) {
        recurrentLayers++;
        continue;
      }
      final heads = kvHeadsPerLayer != null
          ? (i < kvHeadsPerLayer.length ? kvHeadsPerLayer[i] : 0)
          : nKvHeads;
      // No heads: a layer without attention (LFM's convolution layers).
      if (heads <= 0) {
        convLayers++;
        continue;
      }
      if (i >= ownCache) continue;
      final sliding =
          (slidingWindow ?? 0) > 0 &&
          (pattern is List ? flag(pattern, i) : _slidesByDefault(arch, i));
      final k = sliding ? keyLengthSwa : keyLength;
      final v = sliding ? valueLengthSwa : valueLength;
      kvLayers.add(
        GGUFKvLayer(
          k * heads * 2,
          latentOnly ? 0 : v * heads * 2,
          sliding: sliding,
          block: i,
        ),
      );
    }

    final sizes = header.tensors.isEmpty ? null : header.tensorSizes(fileSize);
    final embedding = header.tensors
        .where((t) => t.name == 'token_embd.weight' && t.dims.length == 2)
        .firstOrNull;
    final tokens = meta['tokenizer.ggml.tokens'];

    return GGUFModelInfo(
      nLayers: blockCount,
      nHeads: nHeads,
      nKvHeads: nKvHeads,
      nEmbd: nEmbd,
      kvBytesPerToken: kvLayers.fold(0, (sum, l) => sum + l.bytesPerCell),
      expertCount: number('expert_count'),
      expertUsedCount: number('expert_used_count'),
      expertFfnDim: number('expert_feed_forward_length'),
      expertSharedFfnDim: number('expert_shared_feed_forward_length'),
      ffnDim: largest('feed_forward_length'),
      slidingWindow: slidingWindow,
      draftHeads: draftHeads,
      // The vocabulary is the embedding's second dimension; the tokenizer's
      // own list says the same when it was within the bytes read.
      nVocab: embedding != null
          ? embedding.dims[1]
          : (tokens == null ? null : GGUFFileReader.toInt(tokens)),
      keyLength: keyLength > 0 ? keyLength : null,
      swaHeadDim: keyLengthSwa != keyLength ? keyLengthSwa : null,
      leadingDenseBlockCount: number('leading_dense_block_count'),
      weights: sizes == null ? null : GGUFWeights.fromTensorSizes(sizes),
      kvLayers: kvLayers,
      recurrentStateBytes:
          recurrentLayers * _recurrentStateBytes(number) +
          convLayers * _convStateBytes(number, nEmbd),
      perLayerInputDim: number('embedding_length_per_layer_input'),
      architecture: arch,
      contextLength: number('context_length'),
    );
  }

  /// What one recurrent layer keeps between tokens: its state (inner size x
  /// state size) and the tail of its convolution, as 32-bit numbers. Seen
  /// on a real engine: 30 such layers took 60.00 + 2.81 MiB, which is this.
  static int _recurrentStateBytes(int? Function(String key) number) {
    final inner = number('ssm.inner_size') ?? 0;
    final state = number('ssm.state_size') ?? 0;
    final kernel = number('ssm.conv_kernel') ?? 0;
    final groups = number('ssm.group_count') ?? 0;
    if (inner <= 0 || state <= 0) return 0;
    final conv = kernel > 1 ? (kernel - 1) * (inner + 2 * groups * state) : 0;
    return (inner * state + conv) * 4;
  }

  /// What one short-convolution layer keeps between tokens (LFM): the last
  /// few inputs, as 32-bit numbers. LFM2.5-8B-A1B's 18 such layers: 0.28
  /// MiB.
  static int _convStateBytes(int? Function(String key) number, int nEmbd) {
    final cache = number('shortconv.l_cache') ?? 0;
    return cache > 1 ? (cache - 1) * nEmbd * 4 : 0;
  }

  /// Sliding-window layers for a model that has a window but lists no
  /// pattern, as KoboldCpp's engine sets them: of every N layers, all but
  /// the last slide. gpt-oss alternates (seen: 12 sliding layers of 24).
  /// Gemma 4 files carry their pattern (five in six); this is the fallback.
  static bool _slidesByDefault(String arch, int layer) {
    final n = switch (arch) {
      'gemma2' || 'gpt-oss' => 2,
      'cohere2' => 4,
      _ => arch.startsWith('gemma3') || arch == 'gemma4' ? 6 : 0,
    };
    return n > 0 && layer % n < n - 1;
  }
}
