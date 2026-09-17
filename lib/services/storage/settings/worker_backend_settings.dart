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

import 'settings_base.dart';

/// Worker-lane host + model. Lives next to mouth settings so a restart
/// keeps the split. The worker model is its own field — same-host
/// different-model (Nano Kimi mouth + Nano GLM worker) must not share
/// the live mouth model slot.
mixin WorkerBackendFields on SettingsBase {
  String _workerBackendType = '';
  String _workerRemoteApiUrl = '';
  String _workerRemoteModelName = '';
  String? _workerKoboldModelPath;
  String? _workerKoboldKcppsPath;

  /// Empty = worker off (all traffic on the active chat backend).
  String get workerBackendType => _workerBackendType;
  String get workerRemoteApiUrl => _workerRemoteApiUrl;
  String get workerRemoteModelName => _workerRemoteModelName;

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
    _workerKoboldModelPath = prefs?.getString(k('worker_kobold_model_path'));
    _workerKoboldKcppsPath = prefs?.getString(k('worker_kobold_kcpps_path'));
  }

  Future<void> setWorkerBackendType(String value) async {
    _workerBackendType = value;
    await prefs?.setString(k('worker_backend_type'), value);
    notify();
  }

  Future<void> setWorkerRemoteApiUrl(String value) async {
    _workerRemoteApiUrl = value;
    await prefs?.setString(k('worker_remote_api_url'), value);
    notify();
  }

  Future<void> setWorkerRemoteModelName(String value) async {
    _workerRemoteModelName = value;
    await prefs?.setString(k('worker_remote_model_name'), value);
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
