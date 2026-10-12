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

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/services.dart';

/// Reasoning ("thinking") support lookups for the web Settings page: which
/// identity the effort helpers key on, the template verdict for local
/// backends, and the background probes that fill those in.
class SettingsReasoning {
  SettingsReasoning(this._storage, this._llm);

  final StorageService _storage;
  final LLMProvider _llm;

  static String? _seededCatalogUrl;

  /// The identity the shared reasoning-effort helpers key on: the remote model
  /// name, or — for managed KoboldCpp — the loaded .gguf path the resolver
  /// registers under. Empty (generic chips, nothing claimed) until the file
  /// has actually been read, or in preset mode where there is no path.
  String get modelKey {
    if (!_llm.isLocal) return _storage.backendSettings.remoteModelName;
    final path = _storage.backendSettings.lastUsedModelPath ?? '';
    return ReasoningSupportResolver.instance.peek(path) == null ? '' : path;
  }

  bool get usesTemplateResolve =>
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
    if (!usesTemplateResolve) return null;
    final name = _storage.backendSettings.remoteModelName;
    if (name.isEmpty) return null;
    if (!ReasoningSupportResolver.instance.isResolved(name)) {
      unawaited(resolveTemplate(name));
      return null;
    }
    return ReasoningSupportResolver.instance.peek(name);
  }

  Future<void> resolveTemplate(String name) {
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
  Future<void> ensureResolved() async {
    if (_llm.isLocal) {
      final path = _storage.backendSettings.lastUsedModelPath ?? '';
      if (path.isEmpty) return;
      await ReasoningSupportResolver.instance.resolveLocalGguf(path);
      return;
    }
    final name = _storage.backendSettings.remoteModelName;
    if (name.isEmpty) return;
    if (usesTemplateResolve) {
      await resolveTemplate(name);
      return;
    }
    final b = _storage.backendSettings;
    await probeReasoningEfforts(
      model: name,
      apiUrl: b.remoteApiUrl,
      apiKey: b.remoteApiKey,
    );
  }

  void seedCatalog() {
    if (_llm.isLocal) return;
    final b = _storage.backendSettings;
    if (b.remoteApiKey.isEmpty && !isLocalRemoteUrl(b.remoteApiUrl)) return;
    final url = b.remoteApiUrl;
    if (_seededCatalogUrl == url) return;
    _seededCatalogUrl = url;
    unawaited(_llm.openRouterService.fetchAvailableModels());
  }

  void kickRemoteEffortProbe() {
    if (_llm.isLocal || usesTemplateResolve) return;
    final b = _storage.backendSettings;
    if (b.remoteModelName.isEmpty || b.remoteApiUrl.isEmpty) return;
    kickReasoningEffortProbe(
      model: b.remoteModelName,
      apiUrl: b.remoteApiUrl,
      apiKey: b.remoteApiKey,
    );
  }

  /// After a remote host/model/key change: template resolve for local
  /// servers, the effort probe for everything else.
  void refreshAfterRemoteChange() {
    final b = _storage.backendSettings;
    if (usesTemplateResolve) {
      unawaited(resolveTemplate(b.remoteModelName));
    } else {
      kickReasoningEffortProbe(
        model: b.remoteModelName,
        apiUrl: b.remoteApiUrl,
        apiKey: b.remoteApiKey,
      );
    }
  }

  /// Remote poke that learned `{none}` is the same UI as a template toggle.
  String? get thinkingSupportName {
    final local = _localThinkingSupport;
    if (local != null) return local.name;
    if (reasoningEffortIsToggleOnly(modelKey)) {
      return ThinkingSupport.toggle.name;
    }
    return null;
  }
}
