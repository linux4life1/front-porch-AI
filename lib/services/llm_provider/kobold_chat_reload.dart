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

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider/lane_host_factory.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Live reloads of the running KoboldCpp: chat's new preset or model, and a
/// timing trial's config.
class KoboldChatReload {
  KoboldChatReload({
    required KoboldService kobold,
    required StorageService storage,
    required LaneHostFactory hosts,
    required EnsureKobold ensureKobold,
  }) : _kobold = kobold,
       _storage = storage,
       _hosts = hosts,
       _ensureKobold = ensureKobold;

  final KoboldService _kobold;
  final StorageService _storage;
  final LaneHostFactory _hosts;
  final EnsureKobold _ensureKobold;

  /// Puts what Settings now says chat runs (a new chat preset or model)
  /// into the running KoboldCpp: a reload of the staged chat config by
  /// name, and a restart when the engine never acts on it. What loaded is
  /// recorded as the model in use. Nothing happens when KoboldCpp is not
  /// running or chat's pair is loaded already.
  ///
  /// When it could not be loaded KoboldCpp has gone back to the model it
  /// had, which still works. The reason is noted first, on the status line
  /// and in the log. If a fresh start would be refused (the new model file
  /// cannot be read, the preset is one the app will not start) nothing is
  /// stopped, the stored choice goes back to what runs ([_putChoiceBack]),
  /// and the answer is a refusal saying why. Otherwise the engine is stopped
  /// and started, and the start's answer is the answer. Null: nothing to
  /// report.
  Future<KoboldLaunchResult?> reloadChat() async {
    if (!_kobold.isProcessRunning) return null;
    // Before the engine is touched, and before the first wait: the choice
    // this reload is for, what the service recorded as loaded, and the
    // config staged for it.
    final asked = resolveKoboldLaunch(_storage);
    final model = _kobold.loadedModelPath;
    final kcpps = _kobold.loadedKcppsPath;
    final was = (
      model: model,
      kcpps: kcpps,
      asked: asked,
      staged: await readStagedKoboldConfig(
        koboldAdminDirFor(_storage),
        kStagedChatConfig,
      ),
    );
    try {
      await _hosts
          .koboldSwapHost(role: kKoboldChatRole, model: '', kcpps: '')
          .restore();
      await recordKoboldModelInUse(_storage);
      return null;
    } on KoboldPresetProblem catch (e) {
      // Refused before anything was sent: the engine runs what it ran.
      _kobold.noteReloadFailed(e.message);
      await _putChoiceBack(was);
      return _refusedKeepingEngine(e.message);
    } on KoboldSwapFailed catch (e) {
      _kobold.noteReloadFailed(e.message);
      // The swap's own last resort stops the engine for a restart. When that
      // restart was refused, there is no previous model left to keep.
      if (!_kobold.isProcessRunning) {
        return KoboldLaunchResult.refused(e.message);
      }
      final problem = await koboldLaunchProblem(_storage);
      if (problem != null) {
        await _putChoiceBack(was);
        return _refusedKeepingEngine(problem);
      }
      await _kobold.stopKobold();
      return _ensureKobold();
    }
  }

  KoboldLaunchResult _refusedKeepingEngine(String why) =>
      KoboldLaunchResult.refused(
        'The new model was not loaded. The previous one is still running. '
        '$why',
      );

  /// The old model is kept running: chat's stored choice (the model in use,
  /// the preset, and the link between them) goes back to exactly the pair the
  /// service recorded as loaded before the reload, so every screen names what
  /// runs,
  /// and the staged chat config is the one that was there, which an idle
  /// unload loads back. The record is put back too, so the next refused
  /// reload can do the same.
  ///
  /// Only the record is trusted, and only when KoboldCpp itself says that
  /// model is the one running (a helper model loaded at the time, or an
  /// engine that went back to another, is not what the record says) and the
  /// choice is still the one this reload was for (one made meanwhile is the
  /// user's newer one). Otherwise nothing is guessed and nothing changes.
  /// What runs is known again too: the staged config is noted as the one
  /// resident.
  Future<void> _putChoiceBack(
    ({String? model, String? kcpps, KoboldLaunch asked, String? staged}) was,
  ) async {
    final model = was.model;
    if (model == null || model.isEmpty) return;
    final runs = await koboldEngineModel(_kobold.baseUrl);
    if (!koboldModelNameMatches(
      runs,
      koboldExpectedModelName({'model_param': model}),
    )) {
      return;
    }
    final now = resolveKoboldLaunch(_storage);
    if (now.modelPath != was.asked.modelPath ||
        now.kcppsPath != was.asked.kcppsPath) {
      return;
    }
    final recorded = was.kcpps ?? '';
    final kcpps = recorded.isNotEmpty && await File(recorded).exists()
        ? recorded
        : '';
    // Exactly the recorded pair, written as it is. Not through
    // chooseKoboldPreset, which works out the model in use again and, for a
    // preset whose model has appeared on disk since the launch, would name
    // that one while KoboldCpp runs the model it was given.
    final b = _storage.backendSettings;
    await b.setLastUsedModelPath(model);
    await b.setActiveKcppsPath(kcpps.isEmpty ? null : kcpps);
    await _storage.presetSettings.setModelPreset(model, kcpps);
    _kobold.noteAdminLoadedPair(modelPath: model, kcppsPath: kcpps);
    final staged = was.staged;
    final dir = koboldAdminDirFor(_storage);
    if (staged != null && dir.isNotEmpty) {
      await stageKoboldConfig(dir, kStagedChatConfig, staged);
    }
    // The failed check left what runs unknown, which keeps the tool-calling
    // check from naming the model. KoboldCpp has said it runs this one, under
    // the config that was staged for it. With no config to name, nothing is
    // guessed.
    if (staged != null) _kobold.noteResident(staged);
  }

  /// Loads [config], which belongs to no role (a timing trial), into the
  /// running KoboldCpp the way a swap loads a role: staged in the admin
  /// folder as [name], reloaded by name, waited for. True when it is what
  /// runs afterwards. Throws [KoboldPresetProblem], in plain words, for a
  /// config [kcppsPresetProblem] refuses, as every other way a config
  /// reaches the engine does.
  Future<bool> loadTrial(String name, Map<String, dynamic> config) async {
    final refused = kcppsPresetProblem(config);
    if (refused != null) throw KoboldPresetProblem(refused);
    final dir = koboldAdminDirFor(_storage);
    if (!_kobold.isProcessRunning || dir.isEmpty) return false;
    final json = encodeKcpps(config);
    final file = await stageKoboldConfig(dir, name, json);
    final staged = KoboldStagedRole(
      filename: name,
      path: file.path,
      key: json,
      modelPath: kcppsModelOf(config),
      kcppsPath: '',
      expectedModel: koboldExpectedModelName(config),
      contextSize: koboldExpectedContext(config),
    );
    try {
      await _hosts
          .koboldSwapHost(
            role: kKoboldTrialRole,
            model: staged.modelPath,
            kcpps: '',
            stage: () async => staged,
          )
          .restore();
    } on KoboldSwapFailed catch (e) {
      debugPrint('[Presets] the trial $name did not load: $e');
      return false;
    }
    return _kobold.isResident(json);
  }
}
