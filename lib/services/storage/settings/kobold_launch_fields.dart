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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/kobold/kobold_idle_unload.dart';
import 'package:front_porch_ai/services/kobold/kobold_launch_config.dart';
import 'package:front_porch_ai/services/kobold/kobold_mmq_timing.dart';

import 'settings_base.dart';

/// Launch settings added by the "let KoboldCpp fit the model" rewrite. A
/// mixin beside [BackendSettings] because that file is at the size limit.
mixin KoboldLaunchFields on SettingsBase {
  bool _gpuLayersManual = false;
  bool _gpuLayersNoteSeen = false;
  KvQuant? _kvQuantNamed;
  ContextManagementMode _koboldContextMode =
      ContextManagementMode.fastForwardSmartCache;
  bool _rocmFlashAttentionFailed = false;
  bool _batchAutomatic = true;
  int _idleUnloadMinutes = 0;
  int? _engineContextSize;

  /// The local backend type; prompts for other backends are not held to
  /// the app's own KoboldCpp.
  String get backendType;

  /// The context chat's KoboldCpp runs with: what chat's config names when
  /// it is staged, and what the engine says once a launch or a reload is
  /// confirmed (the only way to know when the config names none, as its
  /// default differs by version). Staging a config that names none leaves
  /// what was learned.
  int? get engineContextSize => _engineContextSize;

  void setEngineContextSize(int? value) {
    if (value == _engineContextSize) return;
    _engineContextSize = value;
    notify();
  }

  /// [wanted] tokens of prompt, never more than the app's KoboldCpp holds:
  /// a chat set to a longer context than the engine runs would otherwise
  /// be cut from the start, card and all, by KoboldCpp.
  int promptContext(int wanted) {
    final engine = _engineContextSize;
    if (backendType != 'kobold' || engine == null || engine >= wanted) {
      return wanted;
    }
    return engine;
  }

  bool _presetGateSkipped = false;
  Map<String, bool> _mmqTimed = const {};
  Map<String, Map<String, List<KoboldSpeed>>> _mmqSamples = {};

  /// The card and MMQ setting the engine runs with while auto mode learns
  /// which is faster there; null when nothing is being learned.
  ({String key, bool on})? _mmqTrial;

  /// Auto mode picks the batch for this machine (the default). False once
  /// a batch is chosen by hand in Settings.
  bool get batchAutomatic => _batchAutomatic;

  Future<void> setBatchAutomatic(bool value) async {
    _batchAutomatic = value;
    await prefs?.setBool(k('kobold_batch_automatic'), value);
    notify();
  }

  /// Minutes the app's own KoboldCpp may sit idle before its model is
  /// unloaded to free the graphics memory; 0 (the default) never does.
  int get idleUnloadMinutes => _idleUnloadMinutes;

  /// Takes one of [kKoboldIdleUnloadChoices]; anything else is refused.
  Future<void> setIdleUnloadMinutes(int value) async {
    if (!kKoboldIdleUnloadChoices.contains(value)) {
      debugPrint('Idle unload of $value minutes is not a choice; ignored.');
      return;
    }
    _idleUnloadMinutes = value;
    await prefs?.setInt(k('kobold_idle_unload_minutes'), value);
    notify();
  }

  /// "I know KoboldCpp: don't ask again" on the pop-up before the preset
  /// editor.
  bool get presetGateSkipped => _presetGateSkipped;

  Future<void> setPresetGateSkipped(bool value) async {
    _presetGateSkipped = value;
    await prefs?.setBool(k('kobold_preset_gate_skipped'), value);
    notify();
  }

  /// MMQ on (true) or off as timed faster on [card] with KoboldCpp
  /// [engineVersion]; null when not timed there.
  bool? mmqFor(String card, String? engineVersion) =>
      _mmqTimed[_mmqKey(card, engineVersion)];

  Future<void> setMmqFor(String card, String? engineVersion, bool on) async {
    _mmqTimed = {..._mmqTimed, _mmqKey(card, engineVersion): on};
    await prefs?.setString(k('kobold_mmq_timed'), jsonEncode(_mmqTimed));
    notify();
  }

  static String _mmqKey(String card, String? version) =>
      '${card.trim()}|${version ?? ''}';

  /// MMQ for an auto-mode launch on [card]: as learned, or the setting
  /// still to be timed there (on, KoboldCpp's default, then off). Replies
  /// read their speeds into it until each has three that can be timed (see
  /// [noteKoboldOutput] and [koboldTurnSeconds]).
  bool mmqForLaunch(String card, String? engineVersion) {
    final key = _mmqKey(card, engineVersion);
    final learned = _mmqTimed[key];
    if (learned != null) {
      _mmqTrial = null;
      return learned;
    }
    // "On" is done when enough of its replies could be timed: counting the
    // replies seen would end it after three short ones, and "off" would then
    // be tried for good with nothing known about "on".
    final on = koboldTurnSeconds(_mmqSamples[key]?['on'] ?? const []) == null;
    _mmqTrial = (key: key, on: on);
    return on;
  }

  /// Stops learning MMQ until the next launch (the editor times it itself).
  void pauseMmqLearning() => _mmqTrial = null;

  /// KoboldCpp's output while MMQ is being learned: each reply's speeds go
  /// to the setting it ran with; once both have enough, the faster is kept.
  void noteKoboldOutput(String text) {
    final trial = _mmqTrial;
    if (trial == null) return;
    final speeds = [
      for (final line in text.split('\n')) ?parseKoboldSpeed(line),
    ];
    if (speeds.isEmpty) return;
    final both = _mmqSamples[trial.key] ??= {};
    final phase = trial.on ? 'on' : 'off';
    both[phase] = koboldKeepTimed([...?both[phase], ...speeds]);
    final faster = koboldMmqFaster(
      on: both['on'] ?? const [],
      off: both['off'] ?? const [],
    );
    if (faster != null) {
      _mmqSamples.remove(trial.key);
      _mmqTrial = null;
      _mmqTimed = {..._mmqTimed, trial.key: faster};
      unawaited(prefs?.setString(k('kobold_mmq_timed'), jsonEncode(_mmqTimed)));
    }
    unawaited(
      prefs?.setString(
        k('kobold_mmq_samples'),
        jsonEncode({
          for (final e in _mmqSamples.entries)
            e.key: {
              for (final s in e.value.entries)
                s.key: [
                  for (final r in s.value)
                    [r.read, r.readSeconds, r.written, r.writeSeconds],
                ],
            },
        }),
      ),
    );
  }

  static Map<String, Map<String, List<KoboldSpeed>>> _readMmqSamples(
    String? text,
  ) {
    if (text == null) return {};
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: {
            for (final s in (e.value as Map<String, dynamic>).entries)
              s.key: [
                for (final r in s.value as List)
                  (
                    read: (r as List)[0] as int,
                    readSeconds: (r[1] as num).toDouble(),
                    written: r[2] as int,
                    writeSeconds: (r[3] as num).toDouble(),
                  ),
              ],
          },
      };
    } on Object catch (e) {
      debugPrint('Unreadable MMQ samples dropped: $e');
      return {};
    }
  }

  /// KoboldCpp on ROCm died on this machine with flash attention on, so
  /// the app's own launches leave it off here.
  bool get rocmFlashAttentionFailed => _rocmFlashAttentionFailed;

  Future<void> setRocmFlashAttentionFailed(bool value) async {
    _rocmFlashAttentionFailed = value;
    await prefs?.setBool(k('rocm_flash_attention_failed'), value);
    notify();
  }

  /// Clears the mark, so the next ROCm launch has flash attention again.
  Future<void> retryRocmFlashAttention() async {
    if (_rocmFlashAttentionFailed) await setRocmFlashAttentionFailed(false);
  }

  /// False (the default, for everyone): KoboldCpp fits the model to the
  /// card itself. True: the stored `gpu_layers` number is sent as typed.
  bool get gpuLayersManual => _gpuLayersManual;

  /// True once a GPU layer count has ever been stored. A VALUE of 0 is not
  /// that signal: 0 is a deliberate "keep the model off the card".
  bool get gpuLayersConfigured => prefs?.containsKey(k('gpu_layers')) ?? false;

  /// The layer count stored before everyone moved to Automatic, until the
  /// user has acknowledged the move; null on a fresh install, once
  /// acknowledged, and while layers are set by hand. Drives the one-time
  /// note beside the control.
  int? get retiredGpuLayers => _gpuLayersManual || _gpuLayersNoteSeen
      ? null
      : prefs?.getInt(k('gpu_layers'));

  /// Attention cache type. Five levels. Until one is picked by name, the
  /// older 0 / 1 / 2 level (f16, q8_0, q4_0) is what counts.
  KvQuant get kvQuant =>
      _kvQuantNamed ??
      KvQuant.parse(prefs?.getInt(k('kv_quantization_level')) ?? 0);

  /// How a chat longer than the context is handled when no preset is in
  /// use. Sliding window is only applied to models that have it.
  ContextManagementMode get koboldContextMode => _koboldContextMode;

  void loadKoboldLaunch() {
    _gpuLayersManual = prefs?.getBool(k('gpu_layers_manual')) ?? false;
    final seen = prefs?.getBool(k('gpu_layers_note_seen'));
    if (seen == null) {
      // First start of a build with Automatic layers. Only someone who
      // already had a layer count has anything to be told; decided once,
      // here, because a later launch stores a count for everybody.
      _gpuLayersNoteSeen = !gpuLayersConfigured;
      unawaited(prefs?.setBool(k('gpu_layers_note_seen'), _gpuLayersNoteSeen));
    } else {
      _gpuLayersNoteSeen = seen;
    }
    final named = prefs?.getString(k('kv_quant'));
    _kvQuantNamed = named == null ? null : KvQuant.parse(named);
    _rocmFlashAttentionFailed =
        prefs?.getBool(k('rocm_flash_attention_failed')) ?? false;
    _koboldContextMode = prefs?.getString(k('kobold_context_mode')) == 'swa'
        ? ContextManagementMode.slidingWindowAttention
        : ContextManagementMode.fastForwardSmartCache;
    // Auto for everyone who never chose a batch; a batch chosen before Auto
    // existed is kept.
    _batchAutomatic =
        prefs?.getBool(k('kobold_batch_automatic')) ??
        !(prefs?.containsKey(k('blas_batch_size')) ?? false);
    _presetGateSkipped =
        prefs?.getBool(k('kobold_preset_gate_skipped')) ?? false;
    final idle = prefs?.getInt(k('kobold_idle_unload_minutes')) ?? 0;
    _idleUnloadMinutes = kKoboldIdleUnloadChoices.contains(idle) ? idle : 0;
    _mmqTimed = _readMmqTimed(prefs?.getString(k('kobold_mmq_timed')));
    _mmqSamples = _readMmqSamples(prefs?.getString(k('kobold_mmq_samples')));
  }

  static Map<String, bool> _readMmqTimed(String? text) {
    if (text == null) return const {};
    try {
      final map = jsonDecode(text);
      if (map is! Map) return const {};
      return {
        for (final e in map.entries)
          if (e.value is bool) '${e.key}': e.value as bool,
      };
    } on FormatException catch (e) {
      debugPrint('Unreadable MMQ timings dropped: $e');
      return const {};
    }
  }

  Future<void> setGpuLayersManual(bool value) async {
    _gpuLayersManual = value;
    await prefs?.setBool(k('gpu_layers_manual'), value);
    // Taking the number back into use is an acknowledgement too.
    if (value && !_gpuLayersNoteSeen) return dismissGpuLayersNote();
    notify();
  }

  Future<void> dismissGpuLayersNote() async {
    _gpuLayersNoteSeen = true;
    await prefs?.setBool(k('gpu_layers_note_seen'), true);
    notify();
  }

  Future<void> setKvQuant(KvQuant value) async {
    _kvQuantNamed = value;
    await prefs?.setString(k('kv_quant'), value.wire);
    notify();
  }

  Future<void> setKoboldContextMode(ContextManagementMode value) async {
    _koboldContextMode = value;
    await prefs?.setString(
      k('kobold_context_mode'),
      value == ContextManagementMode.slidingWindowAttention ? 'swa' : 'ff',
    );
    notify();
  }
}
