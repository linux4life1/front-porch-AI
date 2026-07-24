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

import 'dart:convert';
import 'dart:io';
import 'settings_base.dart';

/// Saved system prompts, kcpps presets, model preset map.
///
/// Lifted Stage 7. Includes _parseKcppsFile (moved here; was private helper
/// in god used by kcpps active path + preset map).
class PresetSettings with SettingsBase {
  static const String defaultSystemPrompt =
      "You are an immersive roleplay partner. Embody {{char}} completely — personality, appearance, thought processes, emotions, behaviors, and speech patterns. You may also roleplay as any side characters introduced.\n\nEngage with {{user}} by depicting {{char}}'s actions, emotions, and dialogue. Develop the plot slowly and organically while driving the scenario forward. Never write {{user}}'s speech, actions, or decisions — allow them full control of their character.\n\nWrite in a vivid, creative, varied, and descriptive style. Use rich sensory detail for the environment, people, and events. Make each reply unique and end with an action or dialogue to keep momentum.\n\nMaintain consistency with established details — clothing, time of day, location, and prior events. Stay in character at all times.";

  List<Map<String, String>> _savedPrompts = [];
  Map<String, String> _modelPresetMap = {};
  Map<String, String> _modelMmprojMap = {};

  List<Map<String, String>> get savedPrompts =>
      List.unmodifiable(_savedPrompts);
  Map<String, String> get modelPresetMap => Map.unmodifiable(_modelPresetMap);

  /// Per-local-model mmproj (vision projector) file overrides. Keyed by the
  /// model's GGUF path → the mmproj file to pass to KoboldCpp so a
  /// multimodal-but-no-embedded-projector model can actually see images.
  Map<String, String> get modelMmprojMap => Map.unmodifiable(_modelMmprojMap);

  void load() {
    // Load saved prompts
    final promptsJson = prefs?.getString(k('saved_prompts'));
    if (promptsJson != null) {
      final decoded = jsonDecode(promptsJson) as List;
      _savedPrompts = decoded
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    }
    // Default "Immersive Roleplay" ensure/persist now handled in thin god _init (after load of persisted list)
    // so that first-run case always persists (was mem-only insert here causing god any() on unmodifiable to skip savePrompt).

    final presetMapJson = prefs?.getString(k('model_preset_map'));
    if (presetMapJson != null) {
      try {
        _modelPresetMap = Map<String, String>.from(
          jsonDecode(presetMapJson) as Map,
        );
      } catch (_) {
        _modelPresetMap = {};
      }
    }

    final mmprojMapJson = prefs?.getString(k('model_mmproj_map'));
    if (mmprojMapJson != null) {
      try {
        _modelMmprojMap = Map<String, String>.from(
          jsonDecode(mmprojMapJson) as Map,
        );
      } catch (_) {
        _modelMmprojMap = {};
      }
    }
  }

  Future<void> savePrompt(String name, String content) async {
    _savedPrompts.removeWhere((p) => p['name'] == name);
    _savedPrompts.add({'name': name, 'content': content});
    await _persistPrompts();
    notify();
  }

  Future<void> deleteSavedPrompt(String name) async {
    _savedPrompts.removeWhere((p) => p['name'] == name);
    await _persistPrompts();
    notify();
  }

  void loadSavedPrompt(String name, void Function(String) setSystemPromptCb) {
    final prompt = _savedPrompts.firstWhere(
      (p) => p['name'] == name,
      orElse: () => {},
    );
    if (prompt.containsKey('content')) {
      setSystemPromptCb(prompt['content']!);
    }
  }

  Future<void> _persistPrompts() async {
    await prefs?.setString(k('saved_prompts'), jsonEncode(_savedPrompts));
  }

  Future<void> setModelPreset(String modelPath, String? kcppsPath) async {
    if (kcppsPath != null) {
      _modelPresetMap[modelPath] = kcppsPath;
    } else {
      _modelPresetMap.remove(modelPath);
    }
    await prefs?.setString(k('model_preset_map'), jsonEncode(_modelPresetMap));
    notify();
  }

  Future<void> setModelMmproj(String modelPath, String? mmprojPath) async {
    if (mmprojPath != null && mmprojPath.isNotEmpty) {
      _modelMmprojMap[modelPath] = mmprojPath;
    } else {
      _modelMmprojMap.remove(modelPath);
    }
    await prefs?.setString(k('model_mmproj_map'), jsonEncode(_modelMmprojMap));
    notify();
  }

  /// Parse a .kcpps JSON file and return the parsed map.
  /// Returns null if the path is invalid or parsing fails.
  /// (Moved here from god; used by active kcpps + preset logic.)
  static Map<String, dynamic>? parseKcppsFile(String? kcppsPath) {
    if (kcppsPath == null || kcppsPath.isEmpty) return null;
    try {
      final file = File(kcppsPath);
      if (!file.existsSync()) return null;
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
