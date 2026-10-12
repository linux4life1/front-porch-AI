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

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

/// The chat model a swap unloads and puts back: a local GGUF path, or the
/// remote model name.
String mouthSwapModelId(StorageService storage) {
  final b = storage.backendSettings;
  if (b.backendType == 'kobold') {
    return b.lastUsedModelPath?.trim() ?? '';
  }
  return b.remoteModelName;
}

/// The helper model a swap loads: a local GGUF path, or the remote name.
String workerSwapModelId(StorageService storage) {
  if (storage.workerBackendType == 'kobold') {
    return storage.resolvedWorkerKoboldModelPath();
  }
  return storage.workerRemoteModelName;
}

/// The `.kcpps` preset the chat ([worker] false) or helper lane runs.
String koboldKcppsId(StorageService storage, {required bool worker}) {
  if (worker) return storage.resolvedWorkerKoboldKcppsPath();
  return storage.backendSettings.activeKcppsPath?.trim() ?? '';
}

/// The API key stored for the chat lane's resolved address.
String mouthLaneApiKey(StorageService storage) => storage.remoteApiKeyFor(
  resolvedLaneApiUrl(
    storage.backendSettings.backendType,
    storage.backendSettings.remoteApiUrl,
  ),
);

/// The API key stored for the helper lane's resolved address.
String workerLaneApiKey(StorageService storage) => storage.remoteApiKeyFor(
  resolvedLaneApiUrl(storage.workerBackendType, storage.workerRemoteApiUrl),
);

/// Whether the saved chat + helper pair can swap on one GPU. The caller
/// checks first that a helper is configured at all.
bool savedPairSupportsGpuSwap(StorageService storage) => workerGpuSwapSupported(
  mouthType: storage.backendSettings.backendType,
  mouthUrl: storage.backendSettings.remoteApiUrl,
  mouthModel: mouthSwapModelId(storage),
  workerType: storage.workerBackendType,
  workerUrl: storage.workerRemoteApiUrl,
  workerModel: workerSwapModelId(storage),
  mouthKcpps: koboldKcppsId(storage, worker: false),
  workerKcpps: koboldKcppsId(storage, worker: true),
);

/// Whether the saved chat and helper lanes are one resident model.
bool savedLanesShareResident(StorageService storage) =>
    workerLanesShareResident(
      mouthType: storage.backendSettings.backendType,
      mouthUrl: storage.backendSettings.remoteApiUrl,
      mouthModel: mouthSwapModelId(storage),
      workerType: storage.workerBackendType,
      workerUrl: storage.workerRemoteApiUrl,
      workerModel: workerSwapModelId(storage),
      mouthKcpps: koboldKcppsId(storage, worker: false),
      workerKcpps: koboldKcppsId(storage, worker: true),
    );
