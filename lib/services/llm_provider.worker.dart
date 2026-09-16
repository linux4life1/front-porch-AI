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
  /// Worker picker type, or null when the worker is off.
  BackendType? get workerBackend {
    switch (_storageService.workerBackendType) {
      case 'openRouter':
        return BackendType.openRouter;
      case 'omlx':
        return BackendType.omlx;
      case 'kobold':
        return BackendType.kobold;
      default:
        return null;
    }
  }

  bool get workerConfigured =>
      !workerBackendIsOff(_storageService.workerBackendType);

  bool get workerRefusedDualLocal =>
      workerConfigured &&
      !workerPairAllowed(
        mouthType: _storageService.backendType,
        mouthUrl: _storageService.remoteApiUrl,
        workerType: _storageService.workerBackendType,
        workerUrl: _storageService.workerRemoteApiUrl,
      );

  /// Side-lane service when the worker is on and the pair is allowed.
  LLMService? get workerService {
    if (!workerConfigured || workerRefusedDualLocal) return null;
    return switch (workerBackend) {
      BackendType.kobold => _koboldService,
      BackendType.openRouter || BackendType.omlx => _workerRemote,
      null => null,
    };
  }

  /// Evals / clerk / journal / growth. Mouth stays [activeService].
  LLMService get sideLaneService => workerService ?? activeService;

  bool get sideLaneIsKobold => sideLaneService is KoboldService;

  OpenRouterService get workerRemoteService => _workerRemote;

  @visibleForTesting
  bool get debugOmlxPollerStarted => _omlxPoller.isStarted;

  /// Plain-English reason the worker host is picked but not ready.
  String? get workerUnreadyMessage {
    if (!workerConfigured || workerRefusedDualLocal) return null;
    final svc = workerService;
    if (svc == null || svc.isReady) return null;
    return switch (workerBackend) {
      BackendType.kobold =>
        'Side jobs are waiting for KoboldCPP to start. Open Models '
            'and make sure a file is loaded.',
      BackendType.omlx =>
        'Side jobs need oMLX running (omlx serve). Chat speech stays '
            'on your main model.',
      BackendType.openRouter =>
        'Side jobs need a working URL and key for the worker host.',
      null => null,
    };
  }

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
