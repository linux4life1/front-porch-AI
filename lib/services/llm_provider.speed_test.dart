// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Local model card's speed test, wired to the app's own pieces: chat's
// staged config for each try, the trial reload the preset editor's timing
// uses, chat's reload to put the model back, and the preset it saves.

part of 'llm_provider.dart';

final Expando<KoboldSpeedTest> _speedTests = Expando('fpai.koboldSpeedTest');

extension LLMProviderSpeedTest on LLMProvider {
  /// The speed test, one for the app: the desktop's card and the phone's
  /// both run and follow this one. Made with the provider; null on a test
  /// double that stands in for it, which has none.
  KoboldSpeedTest? get koboldSpeedTest => _speedTests[this];

  void _makeSpeedTest() => _speedTests[this] = KoboldSpeedTest(
    kobold: _koboldService,
    why: _speedTestWhyNot,
    setup: _speedTestSetup,
    mapFor: _speedTestMap,
    loadTrial: loadKoboldTrial,
    reloadChat: reloadChatKobold,
    save: _saveMeasuredPreset,
    replaces: (s) async {
      final name = koboldMeasuredPresetName(s.model, s.card);
      return await KcppsLibrary(_storageService.binDir.path).exists(name)
          ? name
          : null;
    },
  );

  /// Why the test cannot run now, in plain words. It tunes auto mode, on
  /// the KoboldCpp the app runs, with its model loaded or unloaded for
  /// being idle, and one speed test at a time.
  Future<String?> _speedTestWhyNot() async {
    if (!hasManagedProcess) {
      return 'The speed test is for the KoboldCpp this app runs.';
    }
    if ((_storageService.backendSettings.activeKcppsPath ?? '').isNotEmpty) {
      return "A preset is in use. The speed test tunes the app's own "
          'settings.';
    }
    // Before the phase: the preset editor's timing loads tries too, and
    // while one loads the model is still there to test.
    if (_koboldService.speedTestHolds) {
      return 'A speed test is already running.';
    }
    final phase = _koboldService.phase;
    if (!_koboldService.isProcessRunning ||
        (phase != KoboldPhase.ready && phase != KoboldPhase.unloaded)) {
      return 'Start the model first, then run the test.';
    }
    if (_koboldService.hardwareInfo?.call() == null) {
      return 'This computer is still being looked at. Try again in a moment.';
    }
    return null;
  }

  /// Chat's own config with [knobs] for one try, or as auto mode runs it
  /// now. Staged under the test's own name, so chat's file and the context
  /// it records are left alone.
  Future<Map<String, dynamic>> _speedTestMap(KoboldKnobs? knobs) async {
    final staged = await _stageKoboldRole(
      role: kKoboldChatRole,
      model: '',
      kcpps: '',
      trial: knobs,
      asName: kSpeedTrialConfig,
    );
    return (jsonDecode(staged.key) as Map).cast<String, dynamic>();
  }

  Future<KoboldSpeedSetup?> _speedTestSetup() async {
    final b = _storageService.backendSettings;
    final model = resolveKoboldLaunch(_storageService).modelPath;
    final hardware = _koboldService.hardwareInfo?.call();
    final info = await koboldModelHeader(model);
    if (hardware == null || info == null) return null;
    final int bytes;
    try {
      bytes = await File(model).length();
    } on FileSystemException {
      return null;
    }
    // The backend by the rule a launch uses, and what runs now as auto mode
    // stages it.
    final gpu = koboldBackendFor(
      hardware: hardware,
      cublas: b.useCublas,
      vulkan: b.useVulkan,
      rocm: b.useRocm,
      metal: b.useMetal,
      gpuId: b.gpuId,
    );
    final now = readKcpps(jsonEncode(await _speedTestMap(null)));
    if (now is! KcppsOk) return null;
    final c = now.config;
    final fit = KoboldFit(
      info: info,
      fileSizeBytes: bytes,
      contextSize: c.contextSize,
      batchSize: c.batchSize,
      backend: gpu.memory,
      kvQuant: c.kvQuant,
      flashAttention: c.flashAttention,
    );
    final exe = _backendManager.backendPath;
    return KoboldSpeedSetup(
      model: model,
      card: hardware.gpuName,
      backend: gpu.label,
      engine: exe == null ? null : await KoboldBinaryVersion.versionFor(exe),
      start: koboldKnobsOf(c),
      facts: koboldSpeedFactsFor(
        gpu: gpu,
        batches: koboldBatchCandidates(
          fit,
          gpu.machineFor(hardware, _koboldService.freeBeforeLaunch),
        ),
        layersManual: b.gpuLayersManual,
        isMoe: info.isMoe,
        kvQuant: c.kvQuant,
        flashAttentionRuns: koboldFlashAttentionRuns(
          backend: gpu.backend,
          rocm: gpu.rocm,
          architecture: info.architecture,
          rocmFailedBefore: b.rocmFlashAttentionFailed,
        ),
      ),
      load: _koboldService.loadTookFor(model) ?? koboldGuessLoad(bytes),
      timing: koboldGuessTiming(_koboldService.lastSpeed),
    );
  }

  /// The winner as a real preset, "`<model>` (measured on `<card>`)", written
  /// by the preset library into the engine folder over one of that name,
  /// stamped as measured here, and made the model's own preset. Auto mode
  /// runs its settings from now on ([koboldMeasuredKnobs]), a chosen batch
  /// in Settings gives way to it, and MMQ is remembered for the card as the
  /// editor's timing does.
  Future<void> _saveMeasuredPreset(KoboldSpeedSetup s, KoboldKnobs best) async {
    final map = await _speedTestMap(best)
      ..remove('host')
      ..remove('adminunloadtimeout');
    map['measured'] = KoboldMeasured(
      card: s.card,
      backend: s.backend,
      engine: s.engine,
      on: DateTime.now().toIso8601String().substring(0, 10),
      auto: true,
    ).toJson();
    final path = await KcppsLibrary(
      _storageService.binDir.path,
    ).write(koboldMeasuredPresetName(s.model, s.card), map);
    await _storageService.presetSettings.setModelPreset(s.model, path);
    final b = _storageService.backendSettings;
    if (s.facts.mmq) await b.setMmqFor(s.card, s.engine, best.mmq);
    await b.setBatchAutomatic(true);
  }
}
