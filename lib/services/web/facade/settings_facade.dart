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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Read/write adapter over the core generation + backend settings for the web
/// Settings page. Reuses the existing StorageService setters (read live at
/// generation time) and LLMProvider for live backend switching — no new state.
/// Deliberately a focused slice of the huge desktop settings page: backend,
/// model/API, and the most-used sampler values.
class SettingsFacade {
  SettingsFacade(this._storage, this._llm);

  final StorageService _storage;
  final LLMProvider _llm;

  static const List<String> backends = [
    'kobold',
    'pseudoRemote',
    'openRouter',
    'omlx',
  ];

  Map<String, dynamic> read() {
    final g = _storage.generationSettings;
    final b = _storage.backendSettings;
    return {
      'backend': _name(_llm.activeBackend),
      'backends': backends,
      'isLocal': _llm.isLocal,
      'loadedModel': _loadedModel(),
      'remoteApiUrl': b.remoteApiUrl,
      'remoteModelName': b.remoteModelName,
      'hasApiKey': b.remoteApiKey.isNotEmpty,
      'contextSize': b.contextSize,
      // Reasoning / "thinking" — for reasoning models (GLM-*:thinking, etc.) this
      // must be on or the provider's reasoning tokens are discarded and no
      // <think> block is ever produced for the chat to show.
      'reasoningEnabled': b.reasoningEnabled,
      'reasoningEffort': b.reasoningEffort,
      'generation': {
        'temperature': g.temperature,
        'minP': g.minP,
        'repeatPenalty': g.repeatPenalty,
        'repeatPenaltyTokens': g.repeatPenaltyTokens,
        'xtcThreshold': g.xtcThreshold,
        'xtcProbability': g.xtcProbability,
        'maxLength': g.maxLength,
        'minLength': g.minLength,
        'dynamicTempEnabled': g.dynamicTempEnabled,
      },
    };
  }

  Future<void> update(Map<String, dynamic> body) async {
    final g = _storage.generationSettings;
    final b = _storage.backendSettings;

    final backend = body['backend']?.toString();
    if (backend != null) {
      final type = _parse(backend);
      if (type != null) await _llm.setActiveBackend(type);
    }

    var remoteChanged = false;
    if (body.containsKey('remoteApiUrl')) {
      await b.setRemoteApiUrl(body['remoteApiUrl'].toString());
      remoteChanged = true;
    }
    if (body.containsKey('remoteModelName')) {
      await b.setRemoteModelName(body['remoteModelName'].toString());
      remoteChanged = true;
    }
    // Only overwrite the API key when a non-empty value is provided (the read
    // path never returns it, so an empty field means "leave unchanged").
    final apiKey = body['apiKey']?.toString();
    if (apiKey != null && apiKey.isNotEmpty) {
      await b.setRemoteApiKey(apiKey);
      remoteChanged = true;
    }

    final ctx = body['contextSize'];
    if (ctx is num) await b.setContextSize(ctx.toInt());

    final reasoning = body['reasoningEnabled'];
    if (reasoning is bool) await b.setReasoningEnabled(reasoning);
    final effort = body['reasoningEffort']?.toString();
    if (effort != null && effort.isNotEmpty) await b.setReasoningEffort(effort);
    if (remoteChanged) {
      _llm.openRouterService.configure(
        apiUrl: b.remoteApiUrl,
        apiKey: b.remoteApiKey,
        modelName: b.remoteModelName,
      );
    }

    final gen = body['generation'];
    if (gen is Map) {
      final t = gen['temperature'];
      if (t is num) await g.setTemperature(t.toDouble());
      final mp = gen['minP'];
      if (mp is num) await g.setMinP(mp.toDouble());
      final rp = gen['repeatPenalty'];
      if (rp is num) await g.setRepeatPenalty(rp.toDouble());
      final rpt = gen['repeatPenaltyTokens'];
      if (rpt is num) await g.setRepeatPenaltyTokens(rpt.toInt());
      final xt = gen['xtcThreshold'];
      if (xt is num) await g.setXtcThreshold(xt.toDouble());
      final xp = gen['xtcProbability'];
      if (xp is num) await g.setXtcProbability(xp.toDouble());
      final ml = gen['maxLength'];
      if (ml is num) await g.setMaxLength(ml.toInt());
      final mn = gen['minLength'];
      if (mn is num) await g.setMinLength(mn.toInt());
      final dt = gen['dynamicTempEnabled'];
      if (dt is bool) await g.setDynamicTempEnabled(dt);
    }
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
        BackendType.pseudoRemote => 'pseudoRemote',
        BackendType.openRouter => 'openRouter',
        BackendType.omlx => 'omlx',
      };

  static BackendType? _parse(String s) => switch (s) {
        'kobold' => BackendType.kobold,
        'pseudoRemote' => BackendType.pseudoRemote,
        'openRouter' => BackendType.openRouter,
        'omlx' => BackendType.omlx,
        _ => null,
      };
}
