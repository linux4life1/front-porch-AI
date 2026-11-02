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
import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Whether the Generation values match the preset the bar last loaded.
enum GenPresetState { notSaved, saved, edited }

/// What the Generation bar, the model cards, Chat Settings and the web relay
/// do with presets. One place, so desktop and web behave alike.
class GenPresetActions {
  const GenPresetActions(this.storage);
  final StorageService storage;

  SamplerValues get live => SamplerValues.capture(
    storage.generationSettings,
    storage.backendSettings,
  );

  GenPresetState get state {
    final slot = storage.genPresets.slot;
    final values = slot == null ? null : storage.genPresets.presets[slot];
    if (values == null) return GenPresetState.notSaved;
    return values.matchedBy(live)
        ? GenPresetState.saved
        : GenPresetState.edited;
  }

  /// Saves the live values as [name] (replacing one of that name) and makes
  /// it the bar's preset.
  Future<void> saveAs(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    await storage.genPresets.savePreset(clean, live);
    await storage.genPresets.setSlot(clean);
  }

  Future<void> load(String name) async {
    final values = storage.genPresets.presets[name];
    if (values == null) return;
    await values.applyTo(storage.generationSettings, storage.backendSettings);
    await storage.genPresets.setSlot(name);
  }

  Future<void> delete(String name) => storage.genPresets.deletePreset(name);

  /// Links [modelKey] (the current chat model when null) to [name], or
  /// unlinks it. Linking the model in use loads the preset now.
  Future<void> link(String? name, {String? modelKey}) async {
    final current = storage.genPresetFollower.model.key;
    final key = modelKey ?? current;
    if (key.isEmpty) return;
    await storage.genPresets.link(key, name);
    if (name != null && key == current && storage.genPresets.slot != name) {
      await load(name);
    }
  }

  /// Puts every sampler back to the current model's recommended value, or
  /// the app default where it has none. Thinking and stop sequences stay.
  Future<void> resetAll() => storage
      .genPresetFollower
      .recommended
      .value
      .resetValues
      .applyTo(storage.generationSettings, storage.backendSettings);

  /// Copies [name] into one chat's own values, or clears them (back to the
  /// global ones) when [name] is null. Prompt choices are kept.
  static ChatGenerationSettings loadIntoChat(
    ChatGenerationSettings chat,
    SamplerValues? preset,
    String? name,
  ) {
    final v = preset ?? const SamplerValues();
    return ChatGenerationSettings.fromJson(chat.toJson())
      ..temperature = v.temperature
      ..minP = v.minP
      ..topP = v.topP
      ..topK = v.topK
      ..repeatPenalty = v.repeatPenalty
      ..repeatPenaltyTokens = v.repeatPenaltyTokens
      ..xtcThreshold = v.xtcThreshold
      ..xtcProbability = v.xtcProbability
      ..dryMultiplier = v.dryMultiplier
      ..dynamicTempEnabled = v.dynamicTempEnabled
      ..dynamicTempRange = v.dynamicTempRange
      ..maxLength = v.maxLength
      ..reasoningEnabled = v.reasoningEnabled
      ..reasoningEffort = v.reasoningEffort
      ..stopSequences = v.stopSequences == null
          ? null
          : List.of(v.stopSequences!)
      ..genPresetName = preset == null ? null : name;
  }
}
