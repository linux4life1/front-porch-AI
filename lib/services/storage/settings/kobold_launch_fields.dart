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

import 'package:front_porch_ai/services/kobold/kobold_launch_config.dart';

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
