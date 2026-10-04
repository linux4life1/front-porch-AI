// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// What the local model card says in auto mode, worked out once for each
/// change of model, settings or machine: never on a rebuild.
class KoboldStatusFacts {
  const KoboldStatusFacts({
    required this.lines,
    required this.choices,
    required this.verdicts,
    required this.largestGood,
  });

  /// The plain sentences: how it is set up, long chats, other chats.
  final List<String> lines;
  final List<int> choices;
  final Map<int, KoboldContextVerdict> verdicts;
  final int? largestGood;

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
    final mac = unified ?? Platform.isMacOS;
    final gpu = koboldGpuFor(hardware, gpuId: b.gpuId);
    final rocm = b.useRocm ?? false;
    final config = koboldAppConfig(
      modelPath: '',
      settings: KoboldAppSettings(
        contextSize: b.contextSize,
        batchSize: b.blasBatchSize,
        layersManual: false,
        manualLayers: 0,
        backend: gpu.backend,
        gpuId: gpu.gpuId,
        rocm: rocm,
        flashAttention: b.flashAttentionEnabled,
        kvQuant: b.kvQuant,
        mlock: false,
        contextMode: b.koboldContextMode,
        rocmFlashAttentionFailed: b.rocmFlashAttentionFailed,
      ),
      model: KoboldModelFacts(
        hasSlidingWindow: info.hasSlidingWindow,
        architecture: info.architecture,
      ),
    );
    final backend = mac
        ? KoboldMemoryBackend.metal
        : gpu.backend == KoboldGpuBackend.vulkan
        ? KoboldMemoryBackend.vulkan
        : rocm
        ? KoboldMemoryBackend.rocm
        : KoboldMemoryBackend.cuda;
    final onCard = mac || gpu.backend != KoboldGpuBackend.none;
    final swa =
        config.contextMode == ContextManagementMode.slidingWindowAttention;
    final fit = KoboldFit(
      info: info,
      fileSizeBytes: bytes,
      contextSize: config.contextSize,
      batchSize: config.batchSize,
      backend: backend,
      kvQuant: config.kvQuant,
      slidingWindowOn: swa,
      flashAttention: config.flashAttention,
    );
    final machine = KoboldMachine(
      backend: backend,
      totalGraphicsMb: onCard ? hardware.vramMb : 0,
      totalSystemMb: hardware.ramMb,
      freeGraphicsMb: onCard ? free?.graphics : 0,
      freeSystemMb: free?.system,
    );
    final tuning = koboldAutoTuning(
      fit,
      machine,
      batchSize: b.batchAutomatic ? null : b.blasBatchSize,
    );
    final choices = koboldContextChoices(
      current: b.contextSize,
      modelMax: info.contextLength,
    );
    final verdicts = koboldContextVerdicts(
      fit: fit,
      machine: machine,
      choices: choices,
    );
    final slots = koboldSmartCacheSlots(
      asked: tuning.smartCache.asked,
      recurrent: fit.recurrent,
      fastForward: !swa,
      contextShift: tuning.smartCache.contextShift,
    );
    return KoboldStatusFacts(
      lines: [
        'Set up for this computer automatically. '
            '${_pace(tuning.load, machine, onCard)}',
        swa
            ? 'Every reply reads the whole chat again, so long chats start '
                  'slowly.'
            : 'Replies on long chats start fast.',
        slots > 0
            ? 'Going back to another chat is quick.'
            : 'Going back to another chat takes a moment to catch up.',
      ],
      choices: choices,
      verdicts: {for (final v in verdicts.verdicts) v.contextSize: v},
      largestGood: verdicts.largestGood,
    );
  }

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
