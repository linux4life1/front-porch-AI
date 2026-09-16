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

part of 'llm_provider.dart';

extension LLMProviderWorker on LLMProvider {
  OpenRouterService get workerRemoteService => _workerRemote;

  @visibleForTesting
  bool get debugOmlxPollerStarted => _omlxPoller.isStarted;

  String get workerEvalIdentity {
    final type = _storageService.workerBackendType;
    final url = resolvedLaneApiUrl(type, _storageService.workerRemoteApiUrl);
    final svc = workerService ?? _workerRemote;
    return workerEvalIdentityFor(
      backendName: svc.backendName,
      remoteApiUrl: url,
      remoteModelName: _storageService.workerRemoteModelName,
      modelPath: type == 'kobold' ? _storageService.lastUsedModelPath : null,
    );
  }

  /// Point [_workerRemote] at the saved worker host/model. Returns true
  /// when the pair identity changed. Does not touch [activeService].
  bool _syncWorkerFromStorage() {
    final type = _storageService.workerBackendType;
    final url = resolvedLaneApiUrl(type, _storageService.workerRemoteApiUrl);
    final model = _storageService.workerRemoteModelName;
    final key = (type == 'openRouter' || type == 'omlx')
        ? _storageService.remoteApiKeyFor(url)
        : '';
    // Mouth host rides this key so a mouth URL flip (OpenRouter → LM Studio)
    // re-evaluates dual-local without waiting for a worker-field edit.
    // The vault key is included so a key typed last still reconfigures.
    final identity =
        '${_storageService.backendType}|${_storageService.remoteApiUrl}|'
        '$type|$url|$model|$key';
    if (identity == _lastWorkerIdentity) return false;
    _lastWorkerIdentity = identity;
    if (type == 'openRouter' || type == 'omlx') {
      _workerRemote.configure(apiUrl: url, apiKey: key, modelName: model);
    }
    _syncLiveStatusSources();
    return true;
  }
}
