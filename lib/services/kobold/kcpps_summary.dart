// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What a preset does, in plain words: one line for a list, a paragraph for
// "In plain words", and the facts about a model the editor shows.

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/utils/gguf_model_info.dart';
import 'package:front_porch_ai/utils/smart_cache_estimate.dart';

import 'kcpps_codec.dart';
import 'kobold_context_verdict.dart';
import 'kobold_launch_config.dart';

/// "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf" as "Qwen3.6 35B A3B": the file name up
/// to its quantisation.
String koboldModelName(String path) {
  final words = p
      .basenameWithoutExtension(path)
      .split(RegExp(r'[-_ ]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final quant = RegExp(
    r'^(ud|i?q\d.*|f16|f32|bf16|mxfp4|gguf)$',
    caseSensitive: false,
  );
  final cut = words.indexWhere(quant.hasMatch);
  final kept = cut <= 0 ? words : words.sublist(0, cut);
  return kept.isEmpty ? p.basename(path) : kept.join(' ');
}

/// "16k chat · fitted to the card · smart cache off".
String kcppsShortLine(KcppsRead read) {
  if (read is KcppsBroken) return 'Cannot be read: ${read.reason}';
  final ok = read as KcppsOk;
  final c = ok.config;
  final unmanaged = ok.unmanagedKeys;
  if (unmanaged.isNotEmpty) {
    final model = c.modelPath.isEmpty
        ? 'No model'
        : koboldModelName(c.modelPath);
    final n = unmanaged.length;
    return '$model · $n ${n == 1 ? 'setting' : 'settings'} this app does not '
        'manage';
  }
  final swa = c.contextMode == ContextManagementMode.slidingWindowAttention;
  final notable = [
    if (!c.layersAreAutomatic) '${c.gpuLayers} layers on the card',
    if (swa) 'sliding window on',
    if (c.kvQuant != KvQuant.f16 && c.kvQuant != KvQuant.bf16)
      '${kvQuantWords(c.kvQuant)} chat memory',
    if (!swa)
      c.smartCacheSlots > 0
          ? '${c.smartCacheSlots} smart cache slots'
          : 'smart cache off',
  ];
  return [
    '${c.contextSize ~/ 1024}k chat',
    // KoboldCpp placing it is the usual case: said only when there is room.
    if (c.layersAreAutomatic && notable.length < 2) 'fitted to the card',
    ...notable,
  ].take(3).join(' · ');
}

/// "Full", "8-bit", "5-bit", "4-bit".
String kvQuantWords(KvQuant q) => switch (q) {
  KvQuant.f16 || KvQuant.bf16 => 'Full',
  KvQuant.q8_0 => '8-bit',
  KvQuant.q5_1 => '5-bit',
  KvQuant.q4_0 => '4-bit',
};

/// 32 as "32 MB", 1024 as "1 GB".
String koboldMemoryWords(int mb) => mb >= 1024 && mb % 1024 == 0
    ? '${mb ~/ 1024} GB'
    : mb >= 1024
    ? '${(mb / 1024).toStringAsFixed(1)} GB'
    : '$mb MB';

/// The preset as a few plain sentences.
///
/// [recurrent]: the model has recurrent layers, so KoboldCpp may make more
/// smart cache slots than asked. [shortOfMemory]: no slots because the
/// computer has no room for them.
String kcppsPlainWords(
  KoboldLaunchConfig c, {
  bool recurrent = false,
  bool shortOfMemory = false,
}) {
  final model = c.modelPath.isEmpty
      ? 'the model chosen in Settings'
      : koboldModelName(c.modelPath);
  final out = <String>[];
  if (c.layersAreAutomatic) {
    final spare = c.autofitPaddingMb;
    out.add(
      'Loads $model and lets KoboldCpp fit it to your card'
      '${spare == null ? '' : ', keeping ${koboldMemoryWords(spare)} spare'}.',
    );
  } else {
    final experts = c.moeExpertsOnCpu
        ? ', with the experts of '
              '${c.moeCpuLayers == null || c.moeCpuLayers! >= 999 ? 'every layer' : 'the first ${c.moeCpuLayers} layers'}'
              ' in system memory'
        : '';
    out.add('Loads $model with ${c.gpuLayers} layers on the card$experts.');
  }
  final swa = c.contextMode == ContextManagementMode.slidingWindowAttention;
  final size = switch (c.kvQuant) {
    KvQuant.f16 || KvQuant.bf16 => 'at full size',
    final q => 'at ${kvQuantWords(q)}',
  };
  out.add(
    'It sees ${koboldTokens(c.contextSize)} tokens of chat, keeps chat '
    'memory $size, reads ${koboldTokens(c.batchSize)} tokens at a time, and '
    '${swa ? 'reads the whole chat again for every reply' : 'starts replies fast on long chats'}.',
  );
  if (!swa) {
    final slots = koboldSmartCacheSlots(
      asked: c.smartCacheSlots,
      recurrent: recurrent,
      fastForward: true,
      contextShift: c.contextShift,
    );
    out.add(
      slots > 0
          ? '$slots smart cache slots: going back to another chat is quick.'
          : 'No smart cache slots${shortOfMemory ? ': this computer is short of memory' : ''}.',
    );
  }
  if (!c.flashAttention) out.add('Flash attention is off.');
  if (c.mmq == false) out.add('MMQ is off.');
  if (c.draftModelPath.isNotEmpty) {
    out.add(
      '${koboldModelName(c.draftModelPath)} guesses ahead to write faster.',
    );
  }
  if (c.mmprojPath.isNotEmpty) {
    out.add(
      c.mmprojOnCpu
          ? 'It can see pictures, with the vision file in system memory.'
          : 'It can see pictures.',
    );
  }
  if (c.draftModelPath.isNotEmpty && c.mmprojPath.isNotEmpty) {
    out.add('A draft model and a vision file should not be used together.');
  }
  return out.join(' ');
}

/// What the editor says about a model, one fact a chip.
List<String> koboldModelFacts(GGUFModelInfo info) {
  final blocks = info.nLayers;
  final cached = info.kvLayers?.length ?? blocks;
  return [
    if (info.isMoe)
      'Mixture of experts: ${info.expertCount}, '
          '${info.expertUsedCount ?? '?'} used per token',
    if (info.recurrentStateBytes > 0 && cached < blocks)
      'Hybrid: ${blocks - cached} of $blocks layers keep no chat memory',
    info.hasSlidingWindow
        ? 'Sliding window: ${koboldTokens(info.slidingWindow!)} tokens'
        : 'No sliding window',
    if (info.contextLength != null)
      'Made for ${koboldTokens(info.contextLength!)} tokens',
  ];
}
