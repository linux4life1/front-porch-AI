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

import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider/lane_ids.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';
import 'package:front_porch_ai/utils/utils.dart' show LocalModelKeys;

/// The helper (worker) lane's saved host: its dedicated remote client and
/// the identity evals key their verdicts by.
class WorkerLaneConfig {
  WorkerLaneConfig({
    required StorageService storage,
    required KoboldService kobold,
  }) : _storage = storage,
       _kobold = kobold;

  final StorageService _storage;
  final KoboldService _kobold;

  /// Dedicated OpenAI-compatible client for the worker lane. Never the
  /// mouth's client — configuring this must not flip chat speech.
  final OpenRouterService remote = OpenRouterService();

  String? _lastIdentity;

  /// The worker model's key in the eval identity, read from its file once
  /// per model and per engine load.
  LocalModelKeys? _modelKeys;

  /// Point [remote] at the saved worker host/model. Returns true when the
  /// pair identity changed. Does not touch the mouth.
  bool sync() {
    final type = _storage.workerBackendType;
    final url = resolvedLaneApiUrl(type, _storage.workerRemoteApiUrl);
    final model = _storage.workerRemoteModelName;
    final key = (type == 'openRouter' || type == 'omlx')
        ? _storage.remoteApiKeyFor(url)
        : '';
    // Mouth host rides this key so a mouth URL flip (OpenRouter → LM Studio)
    // re-evaluates dual-local without waiting for a worker-field edit.
    // The vault key is included so a key typed last still reconfigures.
    final identity =
        '${_storage.backendSettings.backendType}|${_storage.backendSettings.remoteApiUrl}|'
        '$type|$url|$model|$key|${mouthSwapModelId(_storage)}|'
        '${workerSwapModelId(_storage)}|${koboldKcppsId(_storage, worker: false)}|'
        '${koboldKcppsId(_storage, worker: true)}';
    if (identity == _lastIdentity) return false;
    _lastIdentity = identity;
    if (type == 'openRouter' || type == 'omlx') {
      remote.configure(apiUrl: url, apiKey: key, modelName: model);
    }
    return true;
  }

  /// The worker's eval identity as [service] runs it, with a local helper's
  /// model named by [modelKey] (what the engine runs, for a helper the lane
  /// does not swap in) instead of by the file the helper setting names.
  String evalIdentity({required LLMService service, String? modelKey}) {
    final type = _storage.workerBackendType;
    final url = resolvedLaneApiUrl(type, _storage.workerRemoteApiUrl);
    // Named the way the chat model is: a local one by its file, a remote one
    // by its host and name (see ChatService._evalBackendIdentity).
    final local = type == 'kobold';
    return workerEvalIdentityFor(
      backendName: service.backendName,
      remoteApiUrl: url,
      remoteModelName: local ? '' : _storage.workerRemoteModelName,
      modelPath: local
          ? modelKey ??
                (_modelKeys ??= LocalModelKeys()).of(
                  _storage.resolvedWorkerKoboldModelPath(),
                  stamp: _kobold.residentGeneration,
                )
          : null,
    );
  }
}
