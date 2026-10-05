// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'kcpps_editor_controller.dart';

/// The least context the editor's slider offers.
const int kKcppsContextMin = 2048;

/// What the form adds up to on this machine: the load panel, the smart
/// cache suggestion and the plain words.
extension KcppsEditorFit on KcppsEditorController {
  bool get recurrent => (info?.recurrentStateBytes ?? 0) > 0;

  bool get unified => unifiedMemory;

  /// The backend the form's preset names on this machine. Settings only
  /// says whether the engine is the ROCm build.
  KoboldBackendChoice get backendChoice => koboldBackendFor(
    hardware: hardware.hardwareInfo,
    rocm: storage.backendSettings.useRocm,
    unified: unified,
    preset: draft.backend,
    presetGpuId: draft.gpuId,
  );

  bool get rocm => backendChoice.rocm;

  /// A card the model can go on (Apple Silicon counts).
  bool get hasCard => backendChoice.onCard;

  /// MMQ only does anything on CUDA and the ROCm build.
  bool get mmqApplies => draft.backend == KoboldGpuBackend.cuda;

  bool get flashAttentionRuns => koboldFlashAttentionRuns(
    backend: draft.backend,
    rocm: rocm,
    architecture: info?.architecture,
    rocmFailedBefore: storage.backendSettings.rocmFlashAttentionFailed,
  );

  String? get flashAttentionNote => koboldFlashAttentionNote(
    backend: draft.backend,
    rocm: rocm,
    architecture: info?.architecture,
    rocmFailedBefore: storage.backendSettings.rocmFlashAttentionFailed,
  );

  /// The preset says nothing about sliding window and the model has it:
  /// KoboldCpp's own default stands until the switch is answered.
  bool get swaLeftToKobold => draft.slidingWindowLeft && hasSlidingWindow;

  /// ... and the file leaves fast forward on, so that default is sliding
  /// window together with fast forward, which [kSwaLeftToKoboldNote] says.
  bool get swaLeftWarns =>
      swaLeftToKobold && kcppsSwaLeftToKobold(draft.swaLeftAsWritten!);

  /// The config the form writes, for the panel and the plain words.
  KoboldLaunchConfig get config => draft.toConfig(
    recurrent: recurrent,
    rocm: rocm,
    rocmFlashAttentionFailed: storage.backendSettings.rocmFlashAttentionFailed,
    architecture: info?.architecture,
    hasSlidingWindow: hasSlidingWindow,
  );

  int get paddingMb => koboldAutofitPaddingMb(greedy: draft.greedy);

  /// Blocks plus the output layer: the most layers that go on a card.
  int get layerCount => (info?.nLayers ?? 0) + 1;

  /// The slider's top: what the model was made for ([koboldContextMost]),
  /// or the size in use when that is more, and never below the slider's
  /// bottom.
  int get maxContext => [
    koboldContextMost(info?.contextLength),
    draft.contextSize,
    kKcppsContextMin,
  ].reduce((a, b) => a > b ? a : b);

  /// Graphics cards the preset spreads the model over.
  int get cards =>
      koboldCardsUsed(config, machineCards: hardware.hardwareInfo?.cardCount);

  KoboldMachine? get machine {
    final hw = hardware.hardwareInfo;
    return hw == null ? null : backendChoice.machineFor(hw, free, cards: cards);
  }

  KoboldFit? get fit {
    final model = info;
    final bytes = fileBytes;
    if (model == null || bytes == null) return null;
    final c = config;
    final base = KoboldFit(
      info: model,
      fileSizeBytes: bytes,
      contextSize: c.contextSize,
      batchSize: c.batchSize,
      backend: backendChoice.memory,
      kvQuant: c.kvQuant,
      slidingWindowOn:
          c.contextMode == ContextManagementMode.slidingWindowAttention,
      flashAttention: c.flashAttention,
    );
    // Each further card holds working memory of its own.
    final spread = (cards - 1) * base.load().computeMb;
    final helper = draftModelInfo;
    final helperBytes = draftModelBytes;
    if (helper == null || helperBytes == null) {
      return spread > 0 ? base.copyWith(extraCardMb: spread) : base;
    }
    // KoboldCpp puts the whole draft model on the card, with its own
    // cache at the same length.
    final extra = KoboldFit(
      info: helper,
      fileSizeBytes: helperBytes,
      contextSize: c.contextSize,
      batchSize: c.batchSize,
      backend: backendChoice.memory,
      kvQuant: c.kvQuant,
      flashAttention: c.flashAttention,
    ).load();
    return base.copyWith(extraCardMb: spread + extra.cardMb - extra.overheadMb);
  }

  KoboldPlacement get placement => draft.manual
      ? KoboldPlacement.manual(draft.gpuLayers, draft.moeCpuLayers)
      : const KoboldPlacement.automatic();

  KoboldFitView? get view {
    final f = fit;
    final m = machine;
    if (f == null || m == null || !hasCard) return null;
    return koboldFitView(f, m, placement, paddingMb: paddingMb);
  }

  /// The slots that fit beside the model, with the batch as set.
  ({int slots, SmartCacheLimit limit})? get suggestedSlots {
    final f = fit;
    final m = machine;
    if (f == null || m == null) return null;
    return koboldAutoTuning(
      f,
      m,
      paddingMb: paddingMb,
      batchSize: draft.batchSize,
    ).slots;
  }

  /// The most one slot holds, in MB.
  int? get slotMb => fit?.slotMb;

  /// The slots KoboldCpp makes for what the form asks.
  int get slotsMade {
    final w = koboldSmartCacheSetting(slots: draft.slots, recurrent: recurrent);
    return koboldSmartCacheSlots(
      asked: w.asked,
      recurrent: recurrent,
      fastForward: !slidingWindowOn,
      contextShift: w.contextShift,
    );
  }

  String get plainWords => kcppsPlainWords(
    config,
    recurrent: recurrent,
    shortOfMemory: suggestedSlots?.limit == SmartCacheLimit.noRoom,
    machineCards: hardware.hardwareInfo?.cardCount,
  );

  List<String> get modelFacts =>
      info == null ? const [] : koboldModelFacts(info!);

  /// "your GeForce GTX 1060", or "this computer" without a card.
  String get cardName {
    final name = hardware.hardwareInfo?.gpuName ?? '';
    if (!hasCard || name.isEmpty || name == 'Unknown GPU') {
      return 'this computer';
    }
    final short = name
        .replaceAll(RegExp(r'\((R|TM)\)', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^NVIDIA\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+\d+\s*GB$', caseSensitive: false), '')
        .trim();
    return 'your $short';
  }

  /// "5.1 GB free of 6 GB (the rest is your desktop)".
  String get freeLine {
    final hw = hardware.hardwareInfo;
    if (hw == null || !hasCard) return '';
    String gb(int mb) => (mb / 1024).toStringAsFixed(mb % 1024 == 0 ? 0 : 1);
    final freeMb = free?.graphics;
    if (unified) {
      return '${gb(freeMb ?? hw.vramMb)} GB the graphics may use, of '
          '${gb(hw.ramMb)} GB';
    }
    if (cards > 1) {
      return '${gb(hw.vramMb + (cards - 1) * hw.smallestCardMb)} GB on $cards '
          'cards';
    }
    return freeMb == null
        ? '${gb(hw.vramMb)} GB on the card'
        : '${gb(freeMb)} GB free of ${gb(hw.vramMb)} GB (the rest is your '
              'desktop)';
  }

  /// Takes the largest placement by hand that fits.
  void useLargestThatFits() {
    final fix = view?.fix;
    if (fix == null) return;
    edit(
      (d) => d.copyWith(
        manual: true,
        gpuLayers: fix.gpuLayers,
        moeCpuLayers: fix.moeCpuLayers,
      ),
    );
  }
}

/// A preset's own MoE setting (`moecpu`, experts kept in system memory)
/// that the form does not hold, such as one beside automatic layers: the
/// form writes placement as one group, so a placement edit replaces it.
extension KcppsEditorOwnMoe on KcppsEditorController {
  /// Saving now drops or replaces the file's own `moecpu`, which the form
  /// did not hold when the preset was opened. False for a new preset, an
  /// edit that leaves placement alone, and a `moecpu` the form shows.
  bool get saveReplacesOwnMoe {
    final raw = _raw;
    final opened = _opened;
    if (raw == null || opened == null) return false;
    int layers(Object? v) =>
        (v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim())) ?? 0;
    final own = layers(raw['moecpu']);
    if (own <= 0 || layers(opened['moecpu']) == own) return false;
    return layers(kcppsMergeEdits(raw, opened, _map())['moecpu']) != own;
  }
}

/// Timing MMQ on and off on this card, from the editor.
extension KcppsEditorMmq on KcppsEditorController {
  /// The chat memory at [q], in MB, wherever it sits.
  int? cacheMbFor(KvQuant q) {
    final f = fit;
    if (f == null) return null;
    final l = f.copyWith(kvQuant: q).load();
    return l.cacheMb + l.ramCacheMb;
  }

  /// Loads the preset with MMQ on, reads a fresh prompt twice, then with it
  /// off; keeps the faster, remembers it for this card, and puts chat back.
  Future<void> timeMmq() async {
    final load = loadTrial;
    if (load == null || mmqTiming || !canWrite) return;
    if (!kobold.isRunning) {
      mmqStatus = 'Start the model first, then time it here.';
      _notify();
      return;
    }
    mmqTiming = true;
    // Auto mode's own learning would take these runs for its own.
    storage.backendSettings.pauseMmqLearning();
    final best = <bool, Duration>{};
    try {
      var round = 0;
      for (final on in [true, false]) {
        mmqStatus = 'Loading with MMQ ${on ? 'on' : 'off'}…';
        _notify();
        // Built as the form is saved, so what the machine has already shown
        // it cannot run (flash attention on a ROCm build that died with it)
        // is not loaded to be timed. Sliding window is answered as the
        // switch reads, off while it is left to KoboldCpp: timed as before.
        final map = kcppsPresetLaunchMap(
          _map(draft.copyWith(mmq: on, slidingWindow: draft.slidingWindow)),
          modelPath: draft.modelPath,
          mmprojPath: '',
        );
        if (!await load('${kStagedConfigPrefix}mmq.kcpps', map)) {
          throw StateError('KoboldCpp did not load the preset');
        }
        mmqStatus = 'Timing with MMQ ${on ? 'on' : 'off'}…';
        _notify();
        // The better of two: the first read after a load can be slowed by
        // the disk.
        for (var i = 0; i < 2; i++) {
          final t = await timeKoboldPrompt(kobold.baseUrl, ++round);
          if (best[on] == null || t < best[on]!) best[on] = t;
        }
      }
      final onFaster = best[true]! <= best[false]!;
      draft = draft.copyWith(mmq: onFaster);
      final card = hardware.hardwareInfo?.gpuName;
      if (card != null) {
        await storage.backendSettings.setMmqFor(card, engineVersion, onFaster);
      }
      String s(Duration d) =>
          '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
      mmqStatus =
          'On: ${s(best[true]!)}, off: ${s(best[false]!)}. '
          '${onFaster ? 'On' : 'Off'} is faster here, so it is set.';
    } on KoboldPresetProblem catch (e) {
      // A preset that asks KoboldCpp to run a program or open itself to the
      // internet is not loaded to be timed.
      mmqStatus = e.message;
    } on Object catch (e) {
      mmqStatus = 'Timing stopped: $e';
    } finally {
      mmqTiming = false;
      _notify();
      await _reloadChat();
    }
  }
}
