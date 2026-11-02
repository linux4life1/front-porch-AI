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

import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/llm_provider/backend_type.dart';
import 'package:front_porch_ai/services/llm_provider/sampler_support.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The open chat's own generation values, as the desktop's Chat Settings
/// Generation section edits them ([ChatService.sessionGenSettings]). One
/// path for a 1:1 and a group chat: both keep their values in the session's
/// settings. Only the preset-held samplers travel; the chat's prompt
/// choices, context, banned phrases and sanitizer are left alone.
class GenPresetChat {
  GenPresetChat(this._storage, this._chat);

  final StorageService _storage;
  final ChatService? _chat;

  /// Wire keys a PUT may set or clear: [SamplerValues.toJson]'s.
  static const keys = {
    'temperature',
    'minP',
    'topP',
    'topK',
    'repeatPenalty',
    'repeatPenaltyTokens',
    'xtcThreshold',
    'xtcProbability',
    'dryMultiplier',
    'dynamicTempEnabled',
    'dynamicTempRange',
    'maxLength',
    'reasoningEnabled',
    'reasoningEffort',
    'stopSequences',
  };

  bool get isOpen {
    final chat = _chat;
    return chat != null &&
        chat.currentSessionId != null &&
        (chat.activeCharacter != null || chat.activeGroup != null);
  }

  static SamplerValues ownOf(ChatGenerationSettings c) => SamplerValues(
    temperature: c.temperature,
    minP: c.minP,
    topP: c.topP,
    topK: c.topK,
    repeatPenalty: c.repeatPenalty,
    repeatPenaltyTokens: c.repeatPenaltyTokens,
    xtcThreshold: c.xtcThreshold,
    xtcProbability: c.xtcProbability,
    dryMultiplier: c.dryMultiplier,
    dynamicTempEnabled: c.dynamicTempEnabled,
    dynamicTempRange: c.dynamicTempRange,
    maxLength: c.maxLength,
    reasoningEnabled: c.reasoningEnabled,
    reasoningEffort: c.reasoningEffort,
    stopSequences: c.stopSequences,
  );

  /// The chat's own values (null = follows the global one), the global
  /// values under them, and which sliders this backend carries.
  Map<String, Object?> read() {
    if (!isOpen) return {'open': false};
    final chat = _chat!;
    final own = ownOf(chat.sessionGenSettings).toJson();
    final b = _storage.backendSettings;
    return {
      'open': true,
      'isGroup': chat.activeGroup != null,
      'values': own,
      'overrides': own.length,
      'genPresetName': chat.sessionGenSettings.genPresetName,
      'global': GenPresetActions(_storage).live.toJson(),
      'backend': b.backendType,
      'samplerKnobs': [
        for (final k in samplerKnobsFor(
          backendTypeFromStored(b.backendType),
          remoteApiUrl: b.remoteApiUrl,
        ))
          k.name,
      ],
    };
  }

  /// Why [patch] cannot be applied, or null. A value the field cannot hold
  /// is refused rather than read as a clear.
  static String? refusal(Map<String, dynamic> patch) {
    for (final e in patch.entries) {
      if (!keys.contains(e.key)) return 'Unknown setting: ${e.key}';
      if (e.value == null) continue;
      if (!SamplerValues.fromJson({
        e.key: e.value,
      }).toJson().containsKey(e.key)) {
        return 'Not a value for ${e.key}';
      }
    }
    return null;
  }

  /// Sets the keys in [patch] on this chat; a null clears one back to the
  /// global value. False when no chat is open.
  Future<bool> patch(Map<String, dynamic> patch) async {
    if (!isOpen) return false;
    final gen = _chat!.sessionGenSettings;
    final merged = <String, Object?>{...ownOf(gen).toJson()};
    patch.forEach((k, v) => v == null ? merged.remove(k) : merged[k] = v);
    final next = GenPresetActions.loadIntoChat(
      gen,
      SamplerValues.fromJson(merged),
      gen.genPresetName,
    );
    _write(gen, next);
    return true;
  }

  /// Copies [preset] (named [name]) into this chat, or with null clears
  /// the chat's values so it follows the model again.
  Future<bool> loadPreset(String? name, SamplerValues? preset) async {
    if (!isOpen) return false;
    final gen = _chat!.sessionGenSettings;
    _write(gen, GenPresetActions.loadIntoChat(gen, preset, name));
    return true;
  }

  /// Copies into the live object rather than replacing it: a new chat's
  /// prompt picker is tied to that object's identity.
  void _write(ChatGenerationSettings gen, ChatGenerationSettings next) {
    gen
      ..temperature = next.temperature
      ..minP = next.minP
      ..topP = next.topP
      ..topK = next.topK
      ..repeatPenalty = next.repeatPenalty
      ..repeatPenaltyTokens = next.repeatPenaltyTokens
      ..xtcThreshold = next.xtcThreshold
      ..xtcProbability = next.xtcProbability
      ..dryMultiplier = next.dryMultiplier
      ..dynamicTempEnabled = next.dynamicTempEnabled
      ..dynamicTempRange = next.dynamicTempRange
      ..maxLength = next.maxLength
      ..reasoningEnabled = next.reasoningEnabled
      ..reasoningEffort = next.reasoningEffort
      ..stopSequences = next.stopSequences
      ..genPresetName = next.genPresetName;
    // The setter saves the chat and repaints, as the desktop dialog's does.
    _chat!.sessionGenSettings = gen;
  }
}
