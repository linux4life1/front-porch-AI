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
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
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
  String? get workerKoboldModelPath => backendSettings.workerKoboldModelPath;
  Future<void> setWorkerKoboldModelPath(String? v) =>
      backendSettings.setWorkerKoboldModelPath(v);
  String? get workerKoboldKcppsPath => backendSettings.workerKoboldKcppsPath;
  Future<void> setWorkerKoboldKcppsPath(String? v) =>
      backendSettings.setWorkerKoboldKcppsPath(v);

  /// Realism-evals GGUF, or the Models-tab file when the worker slot is empty.
  String resolvedWorkerKoboldModelPath() => resolvedKoboldWorkerModelPath(
    workerPath: workerKoboldModelPath,
    mouthPath: backendSettings.lastUsedModelPath,
  );

  /// Realism-evals .kcpps. Empty inherits mouth only when the GGUFs match.
  String resolvedWorkerKoboldKcppsPath() => resolvedKoboldWorkerKcppsPath(
    workerKcpps: workerKoboldKcppsPath,
    mouthKcpps: backendSettings.activeKcppsPath,
    workerModel: resolvedWorkerKoboldModelPath(),
    mouthModel: backendSettings.lastUsedModelPath,
  );
  Future<void> setRemoteApiKeyFor(String url, String v) =>
      backendSettings.setRemoteApiKeyFor(url, v);
  String remoteApiKeyFor(String url) => backendSettings.remoteApiKeyFor(url);
}

/// Dual-local is refused when this pair has no unload/swap lever.
const kWorkerDualLocalMessage =
    'Chat speech and Realism evals can\'t both use a local engine at the same '
    'time — they would fight over the GPU. Use a cloud/API host for one of '
    'them, or turn the worker off.';

/// Empty [workerBackendType] means today's single-backend behavior.
bool workerBackendIsOff(String workerBackendType) =>
    workerBackendType.trim().isEmpty;

/// Slash-normalize a local GGUF / .kcpps path so mouth/worker compare is honest.
String normalizeLocalModelPath(String path) {
  var p = path.trim().replaceAll('\\', '/');
  while (p.contains('//')) {
    p = p.replaceAll('//', '/');
  }
  if (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Worker GGUF, or the mouth/Models-tab file when the worker slot is empty.
String resolvedKoboldWorkerModelPath({
  required String? workerPath,
  required String? mouthPath,
}) {
  final worker = workerPath?.trim() ?? '';
  if (worker.isNotEmpty) return worker;
  return mouthPath?.trim() ?? '';
}

/// Worker .kcpps, or the mouth preset only when both slots name the same GGUF.
/// A different worker GGUF never inherits mouth `--config`.
String resolvedKoboldWorkerKcppsPath({
  required String? workerKcpps,
  required String? mouthKcpps,
  required String? workerModel,
  required String? mouthModel,
}) {
  final worker = workerKcpps?.trim() ?? '';
  if (worker.isNotEmpty) return worker;
  if (normalizeLocalModelPath(workerModel ?? '') ==
      normalizeLocalModelPath(mouthModel ?? '')) {
    return mouthKcpps?.trim() ?? '';
  }
  return '';
}

/// Same provider/URL family as chat speech. Empty worker inherits the mouth.
bool workerHostMatchesChat({
  required String mouthType,
  required String mouthUrl,
  required String workerType,
  required String workerUrl,
}) {
  if (workerBackendIsOff(workerType)) return true;
  final mouthKind = resolveRemoteProviderKind(
    backendType: mouthType,
    url: mouthUrl,
  );
  final workerKind = resolveRemoteProviderKind(
    backendType: workerType,
    url: workerUrl,
  );
  if (mouthKind != workerKind) return false;
  if (mouthKind == RemoteProviderKind.kobold) return true;
  return resolvedLaneApiUrl(workerType, workerUrl) ==
      resolvedLaneApiUrl(mouthType, mouthUrl);
}

/// Second API key only when the worker host differs and that host has no vault
/// key yet. Same-host reuses the chat key.
bool workerShowsApiKeyField({
  required bool sameHost,
  required RemoteProviderKind workerKind,
  required bool vaultHasKey,
}) {
  if (sameHost) return false;
  if (!remoteProviderNeedsApiKey(workerKind)) return false;
  return !vaultHasKey;
}

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
/// Local+local is allowed only when [gpuSwapAvailable] is true (V2
/// unload/swap). Existing callers that omit the flag stay fail-closed.
bool workerPairAllowed({
  required String mouthType,
  required String mouthUrl,
  required String workerType,
  required String workerUrl,
  bool gpuSwapAvailable = false,
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
  if (!(mouthLocal && workerLocal)) return true;
  return gpuSwapAvailable;
}

/// Plain-English reason a picked worker host is not ready yet.
String? workerLaneUnreadyMessage(String workerType) {
  return switch (workerType.trim()) {
    'kobold' =>
      'Realism evals are waiting for KoboldCPP to start. Open Models '
          'and make sure a file is loaded.',
    'omlx' =>
      'Realism evals need oMLX running (omlx serve). Chat speech stays '
          'on your main model.',
    'openRouter' =>
      'Realism evals need a working URL and key for the worker host.',
    _ => null,
  };
}

/// Start Kobold when the mouth is Kobold, or when an allowed worker is.
/// A local mouth + Kobold worker must not launch at chat entry — that
/// would load both engines before the swap window. The occupancy starts
/// the worker after the mouth unloads.
bool shouldEnsureKoboldProcess({
  required String mouthType,
  required String workerType,
  required bool pairAllowed,
  bool mouthIsLocal = false,
}) {
  if (mouthType == 'kobold') return true;
  if (!pairAllowed || workerType != 'kobold') return false;
  return !mouthIsLocal;
}

/// Poll oMLX when the mouth is oMLX, or when an allowed worker is.
bool shouldRunOmlxPoller({
  required String mouthType,
  required String workerType,
  required bool pairAllowed,
}) {
  if (mouthType == 'omlx') return true;
  return pairAllowed && workerType == 'omlx';
}

/// Probe / tool-pill key for the worker lane. Prefixed so an oMLX (or
/// Nano) verdict can never land in the mouth model's slot.
String workerEvalIdentityFor({
  required String backendName,
  required String remoteApiUrl,
  required String remoteModelName,
  required String? modelPath,
}) =>
    'worker|${evalBackendIdentityFor(backendName: backendName, remoteApiUrl: remoteApiUrl, remoteModelName: remoteModelName, modelPath: modelPath)}';
