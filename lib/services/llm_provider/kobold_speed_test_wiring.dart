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

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/kobold_speed_test.dart';
import 'package:front_porch_ai/services/llm_provider/lane_host_factory.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The Local model card's speed test, wired to the app's own pieces: chat's
/// staged config for each try, the trial reload the preset editor's timing
/// uses, chat's reload to put the model back, and the preset it saves.
class KoboldSpeedTestWiring {
  KoboldSpeedTestWiring({
    required KoboldService kobold,
    required StorageService storage,
    required BackendManager backendManager,
    required LaneHostFactory hosts,
    required bool Function() hasManagedProcess,
  }) : _kobold = kobold,
       _storage = storage,
       _backendManager = backendManager,
       _hosts = hosts,
       _hasManagedProcess = hasManagedProcess;

  final KoboldService _kobold;
  final StorageService _storage;
  final BackendManager _backendManager;
  final LaneHostFactory _hosts;
  final bool Function() _hasManagedProcess;

  /// The speed test, one for the app: the desktop's card and the phone's
  /// both run and follow this one.
  KoboldSpeedTest build({
    required Future<bool> Function(String name, Map<String, dynamic> config)
    loadTrial,
    required Future<KoboldLaunchResult?> Function() reloadChat,
  }) => KoboldSpeedTest(
    kobold: _kobold,
    why: _whyNot,
    setup: _setup,
    mapFor: _mapFor,
    loadTrial: loadTrial,
    reloadChat: reloadChat,
    save: _saveMeasuredPreset,
    replaces: (s) async {
      final name = koboldMeasuredPresetName(s.model, s.card);
      return await KcppsLibrary(_storage.binDir.path).exists(name)
          ? name
          : null;
    },
  );

  /// Why the test cannot run now, in plain words. It tunes auto mode, on
  /// the KoboldCpp the app runs, with its model loaded or unloaded for
  /// being idle, and one speed test at a time.
  Future<String?> _whyNot() async {
    if (!_hasManagedProcess()) {
      return 'The speed test is for the KoboldCpp this app runs.';
    }
    if ((_storage.backendSettings.activeKcppsPath ?? '').isNotEmpty) {
      return "A preset is in use. The speed test tunes the app's own "
          'settings.';
    }
    // Before the phase: the preset editor's timing loads tries too, and
    // while one loads the model is still there to test.
    if (_kobold.speedTestHolds) {
      return 'A speed test is already running.';
    }
    final phase = _kobold.phase;
    if (!_kobold.isProcessRunning ||
        (phase != KoboldPhase.ready && phase != KoboldPhase.unloaded)) {
      return 'Start the model first, then run the test.';
    }
    if (_kobold.hardwareInfo?.call() == null) {
      return 'This computer is still being looked at. Try again in a moment.';
    }
    return null;
  }

  /// Chat's own config with [knobs] for one try, or as auto mode runs it
  /// now. Staged under the test's own name, so chat's file and the context
  /// it records are left alone.
  Future<Map<String, dynamic>> _mapFor(KoboldKnobs? knobs) async {
    final staged = await _hosts.stageRole(
      role: kKoboldChatRole,
      model: '',
      kcpps: '',
      trial: knobs,
      asName: kSpeedTrialConfig,
    );
    return (jsonDecode(staged.key) as Map).cast<String, dynamic>();
  }

  Future<KoboldSpeedSetup?> _setup() async {
    final b = _storage.backendSettings;
    final model = resolveKoboldLaunch(_storage).modelPath;
    final hardware = _kobold.hardwareInfo?.call();
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
    final now = readKcpps(jsonEncode(await _mapFor(null)));
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
          gpu.machineFor(hardware, _kobold.freeBeforeLaunch),
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
      load: _kobold.loadTookFor(model) ?? koboldGuessLoad(bytes),
      timing: koboldGuessTiming(_kobold.lastSpeed),
    );
  }

  /// The winner as a real preset, "`<model file>` (measured on `<card>`)",
  /// written by the preset library into the engine folder over one of that
  /// name, stamped as measured here, and made the model's own preset. Auto
  /// mode runs its settings from now on ([koboldMeasuredKnobs]), a chosen
  /// batch in Settings gives way to it, and MMQ is remembered for the card as
  /// the editor's timing does.
  Future<void> _saveMeasuredPreset(KoboldSpeedSetup s, KoboldKnobs best) async {
    final map = await _mapFor(best)
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
      _storage.binDir.path,
    ).write(koboldMeasuredPresetName(s.model, s.card), map);
    await _storage.presetSettings.setModelPreset(s.model, path);
    final b = _storage.backendSettings;
    if (s.facts.mmq) await b.setMmqFor(s.card, s.engine, best.mmq);
    await b.setBatchAutomatic(true);
  }
}
