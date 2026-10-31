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
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/prefs_recovery.dart';

import 'settings_base.dart';

/// Saved system prompts, kcpps presets, model preset map.
///
/// Lifted Stage 7. Includes _parseKcppsFile (moved here; was private helper
/// in god used by kcpps active path + preset map).
class PresetSettings with SettingsBase {
  static const String defaultSystemPrompt =
      "You are an immersive roleplay partner. Embody {{char}} completely — personality, appearance, thought processes, emotions, behaviors, and speech patterns. You may also roleplay as any side characters introduced.\n\nEngage with {{user}} by depicting {{char}}'s actions, emotions, and dialogue. Develop the plot slowly and organically while driving the scenario forward. Never write {{user}}'s speech, actions, or decisions — allow them full control of their character.\n\nWrite in a vivid, creative, varied, and descriptive style. Use rich sensory detail for the environment, people, and events. Make each reply unique and end with an action or dialogue to keep momentum.\n\nMaintain consistency with established details — clothing, time of day, location, and prior events. Stay in character at all times.";

  List<Map<String, String>> _savedPrompts = [];
  String? _oneToOneSlotName;
  String? _groupSlotName;
  Map<String, String> _modelPresetMap = {};
  Map<String, String> _modelMmprojMap = {};

  List<Map<String, String>> get savedPrompts =>
      List.unmodifiable(_savedPrompts);
  Map<String, String> get modelPresetMap => Map.unmodifiable(_modelPresetMap);

  /// The saved prompt the one-to-one Fallback system prompt was last loaded
  /// from or saved as, or null. Each Settings prompt slot keeps its own.
  String? get oneToOneSlotName => _oneToOneSlotName;

  /// The saved prompt the Group system prompt was last loaded from or saved
  /// as, or null.
  String? get groupSlotName => _groupSlotName;

  /// Per-local-model mmproj (vision projector) file overrides. Keyed by the
  /// model's GGUF path → the mmproj file to pass to KoboldCpp so a
  /// multimodal-but-no-embedded-projector model can actually see images.
  Map<String, String> get modelMmprojMap => Map.unmodifiable(_modelMmprojMap);

  void load() {
    // Load saved prompts. A malformed value (hand-edited prefs file, a torn
    // write) must never escape: StorageService._init is fire-and-forget, so a
    // throw here leaves its `initialized` completer unresolved forever and the
    // app comes up half-booted (no web server, no groups/worlds) with no way
    // for the user to recover. Readable entries survive; the rest is kept
    // aside by _decodePrompts.
    final promptsJson = prefs?.getString(k('saved_prompts'));
    if (promptsJson != null) _savedPrompts = _decodePrompts(promptsJson);
    _oneToOneSlotName = _nonEmpty(prefs?.getString(k('system_prompt_name')));
    _groupSlotName = _nonEmpty(prefs?.getString(k('group_system_prompt_name')));

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

  /// Key that holds the raw `saved_prompts` text when it could not be read
  /// in full. Startup seeds Immersive Roleplay right after [load] and that
  /// write replaces `saved_prompts`, so without this copy one bad byte would
  /// erase every custom prompt for good.
  static const String unreadablePromptsKey = 'saved_prompts_unreadable';

  /// Keeps every entry that still decodes. Whatever cannot be read is copied
  /// to [unreadablePromptsKey] before anything can overwrite it.
  List<Map<String, String>> _decodePrompts(String raw) {
    final kept = <Map<String, String>>[];
    var lossy = false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          final name = e is Map ? e['name'] : null;
          final content = e is Map ? e['content'] : null;
          if (name is String && content is String) {
            kept.add({'name': name, 'content': content});
          } else {
            lossy = true;
          }
        }
      } else {
        lossy = true;
      }
    } catch (e) {
      debugPrint('[Settings] saved_prompts is unreadable: $e');
      lossy = true;
    }
    if (lossy) {
      debugPrint(
        '[Settings] saved_prompts could not be read in full; kept '
        '${kept.length} prompt(s) and copied the raw value to '
        '$unreadablePromptsKey.',
      );
      final stash = prefs?.setString(k(unreadablePromptsKey), raw);
      stash?.catchError((Object e) {
        debugPrint('[Settings] could not keep the unreadable prompts: $e');
        return false;
      });
    }
    return kept;
  }

  Future<void> savePrompt(String name, String content) async {
    _savedPrompts.removeWhere((p) => p['name'] == name);
    _savedPrompts.add({'name': name, 'content': content});
    await _persistPrompts();
    notify();
  }

  /// Deleting a prompt also lets go of it in any slot that named it, so a
  /// slot never offers to overwrite a prompt that is gone.
  Future<void> deleteSavedPrompt(String name) async {
    _savedPrompts.removeWhere((p) => p['name'] == name);
    await _persistPrompts();
    if (_oneToOneSlotName == name) await setOneToOneSlotName(null);
    if (_groupSlotName == name) await setGroupSlotName(null);
    notify();
  }

  Future<void> setOneToOneSlotName(String? name) async {
    _oneToOneSlotName = _nonEmpty(name);
    await prefs?.setString(k('system_prompt_name'), _oneToOneSlotName ?? '');
    notify();
  }

  Future<void> setGroupSlotName(String? name) async {
    _groupSlotName = _nonEmpty(name);
    await prefs?.setString(k('group_system_prompt_name'), _groupSlotName ?? '');
    notify();
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

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
    // Saved prompts are the settings users can least afford to lose, so a
    // prompt edit refreshes the known-good copy straight away.
    await PrefsRecovery.snapshotGood();
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
