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

import 'remote_model_memory.dart';
import 'settings_base.dart';

/// Worker-lane host + model. Lives next to mouth settings so a restart
/// keeps the split. The worker model is its own field — same-host
/// different-model (Nano Kimi mouth + Nano GLM worker) must not share
/// the live mouth model slot.
mixin WorkerBackendFields on SettingsBase {
  String _workerBackendType = '';
  String _workerRemoteApiUrl = '';
  String _workerRemoteModelName = '';
  RemoteModelMemory _workerRemoteModels = RemoteModelMemory.decode(null);
  String? _workerKoboldModelPath;
  String? _workerKoboldKcppsPath;

  /// Empty = worker off (all traffic on the active chat backend).
  String get workerBackendType => _workerBackendType;
  String get workerRemoteApiUrl => _workerRemoteApiUrl;
  String get workerRemoteModelName => _workerRemoteModelName;

  /// Slot → last worker model, for the web picker to restore on a switch.
  Map<String, String> get rememberedWorkerRemoteModels =>
      _workerRemoteModels.bySlot;

  /// Dedicated Realism-evals GGUF for the managed Kobold process.
  /// Empty inherits the Models-tab / [lastUsedModelPath] file.
  String? get workerKoboldModelPath => _workerKoboldModelPath;

  /// Dedicated Realism-evals .kcpps for the managed Kobold process.
  String? get workerKoboldKcppsPath => _workerKoboldKcppsPath;

  void loadWorkerBackend() {
    _workerBackendType = prefs?.getString(k('worker_backend_type')) ?? '';
    _workerRemoteApiUrl = prefs?.getString(k('worker_remote_api_url')) ?? '';
    _workerRemoteModelName =
        prefs?.getString(k('worker_remote_model_name')) ?? '';
    _workerRemoteModels = RemoteModelMemory.decode(
      prefs?.getString(k('worker_remote_api_models')),
    );
    final slot = _workerSlot();
    if (_workerRemoteModels.modelFor(slot).isEmpty &&
        _workerRemoteModelName.isNotEmpty &&
        slot.isNotEmpty) {
      _workerRemoteModels.pick(slot, _workerRemoteModelName);
      prefs?.setString(
        k('worker_remote_api_models'),
        _workerRemoteModels.encode(),
      );
    }
    _workerKoboldModelPath = prefs?.getString(k('worker_kobold_model_path'));
    _workerKoboldKcppsPath = prefs?.getString(k('worker_kobold_kcpps_path'));
  }

  String _workerSlot() =>
      remoteModelSlot(backend: _workerBackendType, url: _workerRemoteApiUrl);

  /// Park the live worker model under its host, switch via [change], then
  /// bring back the model last used on the new host (empty if none).
  Future<void> _switchWorkerHost(void Function() change) async {
    final before = _workerSlot();
    _workerRemoteModels.park(before, _workerRemoteModelName);
    change();
    if (_workerSlot() != before) {
      _workerRemoteModelName = _workerRemoteModels.modelFor(_workerSlot());
      await prefs?.setString(
        k('worker_remote_model_name'),
        _workerRemoteModelName,
      );
    }
    await _persistWorkerRemoteModels();
  }

  Future<void> _persistWorkerRemoteModels() async {
    await prefs?.setString(
      k('worker_remote_api_models'),
      _workerRemoteModels.encode(),
    );
  }

  Future<void> setWorkerBackendType(String value) async {
    if (value.isEmpty) {
      // Same-as-chat is not a host: keep the parked worker model.
      _workerBackendType = value;
    } else if (value != _workerBackendType) {
      await _switchWorkerHost(() => _workerBackendType = value);
    }
    await prefs?.setString(k('worker_backend_type'), value);
    notify();
  }

  Future<void> setWorkerRemoteApiUrl(String value) async {
    if (_workerBackendType.isEmpty) {
      _workerRemoteApiUrl = value;
    } else {
      await _switchWorkerHost(() => _workerRemoteApiUrl = value);
    }
    await prefs?.setString(k('worker_remote_api_url'), value);
    notify();
  }

  Future<void> setWorkerRemoteModelName(String value) async {
    _workerRemoteModelName = value;
    _workerRemoteModels.pick(_workerSlot(), value);
    await prefs?.setString(k('worker_remote_model_name'), value);
    await _persistWorkerRemoteModels();
    notify();
  }

  Future<void> setWorkerKoboldModelPath(String? value) async {
    final trimmed = value?.trim();
    _workerKoboldModelPath = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    if (_workerKoboldModelPath == null) {
      await prefs?.remove(k('worker_kobold_model_path'));
    } else {
      await prefs?.setString(
        k('worker_kobold_model_path'),
        _workerKoboldModelPath!,
      );
    }
    notify();
  }

  Future<void> setWorkerKoboldKcppsPath(String? value) async {
    final trimmed = value?.trim();
    _workerKoboldKcppsPath = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    if (_workerKoboldKcppsPath == null) {
      await prefs?.remove(k('worker_kobold_kcpps_path'));
    } else {
      await prefs?.setString(
        k('worker_kobold_kcpps_path'),
        _workerKoboldKcppsPath!,
      );
    }
    notify();
  }
}
