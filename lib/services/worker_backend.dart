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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Worker fields without growing [StorageService] past the 1000-line ratchet.
extension WorkerBackendStorage on StorageService {
  String get workerBackendType => backendSettings.workerBackendType;
  Future<void> setWorkerBackendType(String v) =>
      backendSettings.setWorkerBackendType(v);
  String get workerRemoteApiUrl => backendSettings.workerRemoteApiUrl;
  Future<void> setWorkerRemoteApiUrl(String v) =>
      backendSettings.setWorkerRemoteApiUrl(v);
  String get workerRemoteModelName => backendSettings.workerRemoteModelName;
  Future<void> setWorkerRemoteModelName(String v) =>
      backendSettings.setWorkerRemoteModelName(v);
  Future<void> setRemoteApiKeyFor(String url, String v) =>
      backendSettings.setRemoteApiKeyFor(url, v);
}

/// Plain-English reason the app will not run two local engines at once.
const kWorkerDualLocalMessage =
    'Chat speech and side jobs can\'t both use a local engine at the same '
    'time — they would fight over the GPU. Use a cloud/API host for one of '
    'them, or turn the worker off.';

/// Empty [workerBackendType] means today's single-backend behavior.
bool workerBackendIsOff(String workerBackendType) =>
    workerBackendType.trim().isEmpty;

/// URL used for locality and identity. oMLX is a fixed localhost host;
/// Kobold is not a URL backend.
String resolvedLaneApiUrl(String backendType, String storedUrl) {
  if (backendType == 'omlx') return kOmlxApiV1;
  if (backendType == 'kobold') return '';
  return storedUrl.trim();
}

/// Kobold and oMLX are always local. An OpenAI-compatible URL is local
/// when it points at this machine or the LAN (LM Studio, llama.cpp, …).
bool backendLaneIsLocal(String backendType, String apiUrl) {
  switch (backendType.trim()) {
    case 'kobold':
    case 'omlx':
      return true;
    case 'openRouter':
      return isLocalRemoteUrl(resolvedLaneApiUrl('openRouter', apiUrl));
    default:
      return false;
  }
}

/// Allowed pairs: API+API, API+local, local+API. Off is always allowed.
/// Local+local is refused until an unload/swap lever exists.
bool workerPairAllowed({
  required String mouthType,
  required String mouthUrl,
  required String workerType,
  required String workerUrl,
}) {
  if (workerBackendIsOff(workerType)) return true;
  final mouthLocal = backendLaneIsLocal(
    mouthType,
    resolvedLaneApiUrl(mouthType, mouthUrl),
  );
  final workerLocal = backendLaneIsLocal(
    workerType,
    resolvedLaneApiUrl(workerType, workerUrl),
  );
  return !(mouthLocal && workerLocal);
}

/// Probe / tool-pill key for the worker lane. Prefixed so an oMLX (or
/// Nano) verdict can never land in the mouth model's slot.
String workerEvalIdentityFor({
  required String backendName,
  required String remoteApiUrl,
  required String remoteModelName,
  required String? modelPath,
}) =>
    'worker|${evalBackendIdentityFor(
      backendName: backendName,
      remoteApiUrl: remoteApiUrl,
      remoteModelName: remoteModelName,
      modelPath: modelPath,
    )}';
