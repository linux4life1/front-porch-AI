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

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

/// What the story model picker offers, on desktop and over the relay alike:
/// the chat model, the worker model (when set up), every host a lane may
/// pick, and the local KoboldCpp model files and launch presets.
Map<String, dynamic> storyLaneOptionsFor(
  StorageService storage,
  LLMProvider llm,
) {
  final settings = storage.backendSettings;
  final chatDetail = settings.backendType == 'kobold'
      ? 'KoboldCpp · ${_modelName('', settings.lastUsedModelPath)}'
      : '${remoteProviderLabel(settings.backendType, resolvedLaneApiUrl(settings.backendType, settings.remoteApiUrl))} · ${_modelName(settings.remoteModelName, null)}';
  final workerDetail = !llm.workerConfigured
      ? null
      : storage.workerBackendType == 'kobold'
      ? 'KoboldCpp · ${_modelName('', storage.workerKoboldModelPath ?? settings.lastUsedModelPath)}'
      : '${remoteProviderLabel(storage.workerBackendType, resolvedLaneApiUrl(storage.workerBackendType, storage.workerRemoteApiUrl))} · ${_modelName(storage.workerRemoteModelName, null)}';
  final chatModel = settings.backendType == 'kobold'
      ? _modelName('', settings.lastUsedModelPath)
      : _modelName(settings.remoteModelName, null);
  final workerModel = storage.workerBackendType == 'kobold'
      ? _modelName(
          '',
          storage.workerKoboldModelPath ?? settings.lastUsedModelPath,
        )
      : _modelName(storage.workerRemoteModelName, null);
  return {
    'chat': {'label': 'Same as chat', 'detail': chatDetail, 'model': chatModel},
    'worker': workerDetail == null
        ? null
        : {
            'label': 'Worker model',
            'detail': workerDetail,
            'model': workerModel,
          },
    'hosts': [
      for (final kind in RemoteProviderKind.values)
        if (kind != RemoteProviderKind.omlx || Platform.isMacOS)
          {
            'kind': kind.name,
            'label': remoteProviderKindLabel(kind),
            'type': switch (kind) {
              RemoteProviderKind.kobold => 'kobold',
              RemoteProviderKind.omlx => 'omlx',
              _ => 'openRouter',
            },
            'url': urlForRemoteProvider(kind) ?? '',
            'needsKey': remoteProviderNeedsApiKey(kind),
            'hasKey': switch (urlForRemoteProvider(kind)) {
              final u? => storage.remoteApiKeyFor(u).isNotEmpty,
              null => false,
            },
            'local':
                kind == RemoteProviderKind.kobold ||
                kind == RemoteProviderKind.lmStudio ||
                kind == RemoteProviderKind.omlx,
          },
    ],
    'koboldModels': _files(storage.modelsDir, const ['.gguf']),
    'kcpps': _files(storage.binDir, const ['.kcpps']),
  };
}

/// "Same as chat · Kimi K2.6", "Worker model · Gemma", "OpenRouter · Opus".
String storyLaneLabel(
  StorageService storage,
  LLMProvider llm,
  StoryLaneChoice choice,
) {
  final options = storyLaneOptionsFor(storage, llm);
  switch (choice.lane) {
    case StoryModelLane.main:
      return 'Same as chat · ${storyShortModelName(options['chat']['model'])}';
    case StoryModelLane.worker:
      final worker = options['worker'];
      return worker == null
          ? 'Same as chat · ${storyShortModelName(options['chat']['model'])}'
          : 'Worker model · ${storyShortModelName(worker['model'])}';
    case StoryModelLane.host:
      final host = llm.laneHost(
        type: choice.backendType,
        url: choice.apiUrl,
        model: choice.model,
        kcpps: choice.kcpps,
      );
      return host?.label ?? 'Another host · no model picked';
  }
}

String _modelName(String remote, String? local) {
  if (remote.isNotEmpty) return remote;
  if (local != null && local.isNotEmpty) {
    return path.basenameWithoutExtension(local);
  }
  return 'no model picked';
}

List<Map<String, String>> _files(Directory dir, List<String> extensions) {
  try {
    if (!dir.existsSync()) return const [];
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) => extensions.any((e) => f.path.toLowerCase().endsWith(e)),
            )
            .toList()
          ..sort(
            (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
          );
    return [
      for (final f in files) {'name': path.basename(f.path), 'path': f.path},
    ];
  } catch (_) {
    return const [];
  }
}

/// "moonshotai/kimi-k2.6:thinking" → "kimi-k2.6"; a .gguf path → its
/// basename. What a lane field and the rail have room for.
String storyShortModelName(Object? raw) {
  var s = raw?.toString() ?? '';
  if (s.contains('/')) s = s.split('/').last;
  if (s.endsWith('.gguf')) s = s.substring(0, s.length - 5);
  final colon = s.indexOf(':');
  if (colon > 0) s = s.substring(0, colon);
  return s.isEmpty ? 'no model' : s;
}

/// The URL a lane choice actually talks to (oMLX ignores the stored URL).
String storyLaneResolvedUrl(String type, String url) =>
    type == 'omlx' ? kOmlxApiV1 : resolvedLaneApiUrl(type, url);

/// Default URL for a host kind, for the picker's URL field.
String storyHostDefaultUrl(String kind) {
  for (final k in RemoteProviderKind.values) {
    if (k.name == kind) return urlForRemoteProvider(k) ?? kOpenRouterApiV1;
  }
  return '';
}
