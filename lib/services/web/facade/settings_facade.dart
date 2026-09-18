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

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/legacy_model_cleanup.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/settings_worker.dart';

part 'settings_facade.read.dart';
part 'settings_facade.update.dart';

/// Read/write adapter over the core generation + backend settings for the web
/// Settings page. Reuses the existing StorageService setters (read live at
/// generation time) and LLMProvider for live backend switching — no new state.
/// Deliberately a focused slice of the huge desktop settings page: backend,
/// model/API, and the most-used sampler values.
class SettingsFacade {
  SettingsFacade(this._storage, this._llm, {ChatService? chat}) : _chat = chat;

  final StorageService _storage;
  final LLMProvider _llm;

  /// Optional: present whenever a chat is open, so the three engine-coupled
  /// Porch Life toggles reach the LIVE conversation the same way the desktop
  /// tab's onChanged does. Null-safe — with no chat bound, the write still
  /// lands in storage and applies to the next one.
  final ChatService? _chat;
  ChatService? get boundChat => _chat;

  static const List<String> backends = ['kobold', 'openRouter', 'omlx'];

  /// Live remote API base — used by the settings route to decide whether a
  /// POST would actually change the generation host (step-up gate).
  String get currentRemoteApiUrl => _storage.backendSettings.remoteApiUrl;

  static String? _seededReasoningCatalogUrl;

  /// The identity the shared reasoning-effort helpers key on: the remote model
  /// name, or — for managed KoboldCpp — the loaded .gguf path the resolver
  /// registers under. Empty (generic chips, nothing claimed) until the file
  /// has actually been read, or in preset mode where there is no path.
  String get _reasoningModelKey {
    if (!_llm.isLocal) return _storage.backendSettings.remoteModelName;
    final path = _storage.backendSettings.lastUsedModelPath ?? '';
    return ReasoningSupportResolver.instance.peek(path) == null ? '' : path;
  }

  bool get _usesTemplateResolve =>
      _llm.activeBackend == BackendType.omlx ||
      isLocalRemoteUrl(_storage.backendSettings.remoteApiUrl);

  /// Template thinking verdict, kicking resolve once so a later state poll
  /// carries the answer. Mirrors the desktop block's kick-then-peek: this
  /// getter itself never touches disk or the network.
  ThinkingSupport? get _localThinkingSupport {
    if (_llm.isLocal) {
      final path = _storage.backendSettings.lastUsedModelPath ?? '';
      if (path.isEmpty) return null;
      if (!ReasoningSupportResolver.instance.isResolved(path)) {
        unawaited(ReasoningSupportResolver.instance.resolveLocalGguf(path));
        return null;
      }
      return ReasoningSupportResolver.instance.peek(path);
    }
    if (!_usesTemplateResolve) return null;
    final name = _storage.backendSettings.remoteModelName;
    if (name.isEmpty) return null;
    if (!ReasoningSupportResolver.instance.isResolved(name)) {
      unawaited(_resolveTemplate(name));
      return null;
    }
    return ReasoningSupportResolver.instance.peek(name);
  }

  Future<void> _resolveTemplate(String name) {
    final key = _storage.backendSettings.remoteApiKey;
    if (_llm.activeBackend == BackendType.omlx) {
      return ReasoningSupportResolver.instance.resolveOmlx(
        apiUrl: 'http://localhost:8000/v1',
        modelName: name,
        apiKey: key,
      );
    }
    return ReasoningSupportResolver.instance.resolveLmStudio(
      apiUrl: _storage.backendSettings.remoteApiUrl,
      modelName: name,
      apiKey: key,
    );
  }

  /// Await the local-template verdict so a web GET/POST does not return
  /// generic chips for one round and the truth on the next.
  Future<void> ensureReasoningResolved() async {
    if (_llm.isLocal) {
      final path = _storage.backendSettings.lastUsedModelPath ?? '';
      if (path.isEmpty) return;
      await ReasoningSupportResolver.instance.resolveLocalGguf(path);
      return;
    }
    final name = _storage.backendSettings.remoteModelName;
    if (name.isEmpty) return;
    if (_usesTemplateResolve) {
      await _resolveTemplate(name);
      return;
    }
    final b = _storage.backendSettings;
    await probeReasoningEfforts(
      model: name,
      apiUrl: b.remoteApiUrl,
      apiKey: b.remoteApiKey,
    );
  }

  void _seedReasoningCatalog() {
    if (_llm.isLocal) return;
    final b = _storage.backendSettings;
    if (b.remoteApiKey.isEmpty && !isLocalRemoteUrl(b.remoteApiUrl)) return;
    final url = b.remoteApiUrl;
    if (_seededReasoningCatalogUrl == url) return;
    _seededReasoningCatalogUrl = url;
    unawaited(_llm.openRouterService.fetchAvailableModels());
  }

  void _kickRemoteEffortProbe() {
    if (_llm.isLocal || _usesTemplateResolve) return;
    final b = _storage.backendSettings;
    if (b.remoteModelName.isEmpty || b.remoteApiUrl.isEmpty) return;
    kickReasoningEffortProbe(
      model: b.remoteModelName,
      apiUrl: b.remoteApiUrl,
      apiKey: b.remoteApiKey,
    );
  }

  /// Remote poke that learned `{none}` is the same UI as a template toggle.
  String? get _thinkingSupportName {
    final local = _localThinkingSupport;
    if (local != null) return local.name;
    if (reasoningEffortIsToggleOnly(_reasoningModelKey)) {
      return ThinkingSupport.toggle.name;
    }
    return null;
  }

  String _loadedModel() {
    final b = _storage.backendSettings;
    if (_llm.isLocal) {
      final path = b.lastUsedModelPath;
      return (path != null && path.isNotEmpty)
          ? p.basename(path)
          : 'No model loaded';
    }
    return b.remoteModelName.isNotEmpty ? b.remoteModelName : 'Not set';
  }

  static String _name(BackendType t) => switch (t) {
    BackendType.kobold => 'kobold',
    BackendType.openRouter => 'openRouter',
    BackendType.omlx => 'omlx',
  };

  static BackendType? _parse(String s) => switch (s) {
    'kobold' => BackendType.kobold,
    // Legacy 'pseudoRemote' now maps to the local Kobold backend.
    'pseudoRemote' => BackendType.kobold,
    'openRouter' => BackendType.openRouter,
    'omlx' => BackendType.omlx,
    _ => null,
  };

  /// Legacy-engine model files still on the host's disk (sidecar
  /// retirement cleanup — desktop parity: the Reclaim Disk Space card).
  Future<Map<String, dynamic>> legacyModels() async {
    final root = _storage.rootPath;
    if (root == null) return {'groups': const [], 'totalBytes': 0};
    final groups = await LegacyModelCleanup.scan(root);
    return {
      'groups': [
        for (final g in groups) {'label': g.label, 'bytes': g.bytes},
      ],
      'totalBytes': groups.fold(0, (sum, g) => sum + g.bytes),
    };
  }

  /// Deletes the scanned legacy files (the scan reruns server-side — the
  /// client never supplies paths). Returns bytes freed.
  Future<int> reclaimLegacyModels() async {
    final root = _storage.rootPath;
    if (root == null) return 0;
    return LegacyModelCleanup.reclaim(root);
  }
}
