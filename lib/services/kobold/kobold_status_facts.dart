// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'kobold_app_config.dart';
import 'kobold_backend_choice.dart';
import 'kobold_context_verdict.dart';
import 'kobold_fit.dart';

/// What the local model card says in auto mode, worked out once for each
/// change of model, settings or machine: never on a rebuild.
class KoboldStatusFacts {
  const KoboldStatusFacts({
    required this.lines,
    required this.choices,
    required this.verdicts,
    required this.largestGood,
    this.warning,
  });

  /// The plain sentences: how it is set up, long chats, other chats.
  final List<String> lines;
  final List<int> choices;
  final Map<int, KoboldContextVerdict> verdicts;
  final int? largestGood;

  /// The model was made for less chat than the app needs
  /// ([koboldShortModelWarning]); null when it was not.
  final String? warning;

  /// For the app's own settings, the model at [model] read as [info] of
  /// [bytes], on this machine.
  static KoboldStatusFacts? of({
    required StorageService storage,
    required HardwareInfo? hardware,
    required FreeMemoryMb? free,
    required GGUFModelInfo? info,
    required int? bytes,
    bool? unified,
  }) {
    if (info == null || bytes == null || hardware == null) return null;
    final b = storage.backendSettings;
    // The backend a launch runs here, so the verdicts are about it.
    final gpu = koboldBackendFor(
      hardware: hardware,
      cublas: b.useCublas,
      vulkan: b.useVulkan,
      rocm: b.useRocm,
      metal: b.useMetal,
      gpuId: b.gpuId,
      unified: unified,
    );
    final config = koboldAppConfig(
      modelPath: '',
      settings: KoboldAppSettings(
        contextSize: b.contextSize,
        batchSize: b.blasBatchSize,
        layersManual: false,
        manualLayers: 0,
        backend: gpu.backend,
        gpuId: gpu.gpuId,
        rocm: gpu.rocm,
        flashAttention: b.flashAttentionEnabled,
        kvQuant: b.kvQuant,
        mlock: false,
        rocmFlashAttentionFailed: b.rocmFlashAttentionFailed,
      ),
      model: KoboldModelFacts(architecture: info.architecture),
    );
    final fit = KoboldFit(
      info: info,
      fileSizeBytes: bytes,
      contextSize: config.contextSize,
      batchSize: config.batchSize,
      backend: gpu.memory,
      kvQuant: config.kvQuant,
      flashAttention: config.flashAttention,
    );
    final machine = gpu.machineFor(hardware, free);
    // The batch the launch runs: the user's, when one was chosen.
    final batch = gpu.fixedBatch(
      automatic: b.batchAutomatic,
      chosen: b.blasBatchSize,
    );
    final tuning = koboldAutoTuning(fit, machine, batchSize: batch);
    final choices = koboldContextChoices(
      current: b.contextSize,
      modelMax: info.contextLength,
    );
    final verdicts = koboldContextVerdicts(
      fit: fit,
      machine: machine,
      choices: choices,
      batchSize: batch,
    );
    final slots = koboldSmartCacheSlots(
      asked: tuning.smartCache.asked,
      recurrent: fit.recurrent,
      fastForward: true,
      contextShift: tuning.smartCache.contextShift,
    );
    return KoboldStatusFacts(
      lines: [
        'Set up for this computer automatically. '
            '${_pace(tuning.load, machine, gpu.onCard)}',
        'Replies on long chats start fast.',
        // The keeper's chats for an ordinary model, KoboldCpp's own slots
        // for a hybrid one.
        (tuning.chats > 0 ? tuning.chats >= 2 : slots > 0)
            ? 'Going back to another chat is quick.'
            : 'Going back to another chat takes a moment to catch up.',
      ],
      choices: choices,
      verdicts: {for (final v in verdicts.verdicts) v.contextSize: v},
      largestGood: verdicts.largestGood,
      warning: koboldShortModelWarning(info.contextLength),
    );
  }

  /// For the web card: the lines, the choices and, for each, its verdict in
  /// words, against the context in use ([current]).
  Map<String, dynamic> toJson(int current) => {
    'lines': lines,
    'context': current,
    'choices': choices,
    'largestGood': largestGood,
    // Additive: null unless the model was made for too little chat.
    'warning': warning,
    'verdicts': {
      for (final c in choices)
        if (verdicts[c] case final v?)
          '$c': () {
            final words = koboldContextWords(
              v,
              largestGood: largestGood,
              isCurrent: c == current,
            );
            return {
              'outcome': v.outcome.name,
              'title': words.title,
              'text': words.text,
            };
          }(),
    },
  };

  static String _pace(KoboldLoad l, KoboldMachine m, bool onCard) {
    if (!onCard) {
      return 'There is no graphics card it can use, so replies come slowly.';
    }
    if (m.unified) {
      return l.cardMb <= m.graphicsMb
          ? "The model fits in this Mac's memory, so replies come quickly."
          : "The model barely fits in this Mac's memory, so replies may be "
                'slow.';
    }
    if (l.allOnCard) {
      return 'The whole model fits on your graphics card, so replies come '
          'quickly.';
    }
    return l.gpuLayers == l.layerCount
        ? 'The model is bigger than your graphics card, so replies come at '
              'about reading pace.'
        : 'The model is much bigger than your graphics card, so replies '
              'come slowly.';
  }
}
