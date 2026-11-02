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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';

import 'settings_base.dart';

/// Saved generation presets, which one the Generation bar last loaded, and
/// which preset each chat model is linked to (issue 686).
///
/// Links are keyed by [ChatModelId.key], so a local model keeps its link
/// when its folder moves and a remote model's link is per host.
class GenPresetSettings with SettingsBase {
  final Map<String, SamplerValues> _presets = {};
  final Map<String, String> _links = {};
  String? _slot;

  /// Saved presets in the order they were first saved.
  Map<String, SamplerValues> get presets => Map.unmodifiable(_presets);

  /// Model key → preset name.
  Map<String, String> get links => Map.unmodifiable(_links);

  /// The preset the Generation bar last loaded or saved, or null.
  String? get slot => _slot;

  /// The preset linked to [modelKey], when it still exists.
  String? linkedPreset(String modelKey) {
    final name = _links[modelKey];
    return name != null && _presets.containsKey(name) ? name : null;
  }

  void load() {
    _presets.clear();
    _links.clear();
    try {
      final raw = prefs?.getString(k('gen_presets'));
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            final name = e is Map ? e['name'] : null;
            if (name is String && name.trim().isNotEmpty) {
              _presets[name] = SamplerValues.fromJson(e['values']);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[GenPresets] unreadable gen_presets, starting empty: $e');
    }
    try {
      final raw = prefs?.getString(k('gen_preset_links'));
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is String) _links[key] = value;
          });
        }
      }
    } catch (e) {
      debugPrint('[GenPresets] unreadable gen_preset_links, none kept: $e');
    }
    final slot = prefs?.getString(k('gen_preset_slot'));
    _slot = slot != null && _presets.containsKey(slot) ? slot : null;
  }

  Future<void> savePreset(String name, SamplerValues values) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    _presets[clean] = values;
    await _persistPresets();
    notify();
  }

  /// Deleting a preset also drops every link to it and the bar's slot.
  Future<void> deletePreset(String name) async {
    if (_presets.remove(name) == null) return;
    _links.removeWhere((_, v) => v == name);
    await _persistPresets();
    await _persistLinks();
    if (_slot == name) await setSlot(null);
    notify();
  }

  /// Link [modelKey] to [name], or unlink it when [name] is null.
  Future<void> link(String modelKey, String? name) async {
    if (modelKey.isEmpty) return;
    if (name == null || !_presets.containsKey(name)) {
      if (_links.remove(modelKey) == null) return;
    } else {
      _links[modelKey] = name;
    }
    await _persistLinks();
    notify();
  }

  Future<void> setSlot(String? name) async {
    _slot = name != null && _presets.containsKey(name) ? name : null;
    await prefs?.setString(k('gen_preset_slot'), _slot ?? '');
    notify();
  }

  Future<void> _persistPresets() async {
    await prefs?.setString(
      k('gen_presets'),
      jsonEncode([
        for (final e in _presets.entries)
          {'name': e.key, 'values': e.value.toJson()},
      ]),
    );
  }

  Future<void> _persistLinks() async {
    await prefs?.setString(k('gen_preset_links'), jsonEncode(_links));
  }
}
