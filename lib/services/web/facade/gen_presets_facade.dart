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

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The web side of generation presets (issue 686): the Generation bar, the
/// model cards' preset pickers and the model-switch notice. Every write goes
/// through [GenPresetActions] or the follower, the same calls the desktop
/// makes, so both surfaces behave alike.
class GenPresetsFacade {
  GenPresetsFacade(this._storage);

  final StorageService _storage;

  GenPresetActions get _actions => GenPresetActions(_storage);
  GenPresetFollower get _follower => _storage.genPresetFollower;

  /// Whether a preset named [name] is saved.
  bool has(String name) => _storage.genPresets.presets.containsKey(name);

  /// The saved values of [name], or null.
  SamplerValues? valuesOf(String name) => _storage.genPresets.presets[name];

  /// The chat model's key, empty when none is chosen.
  String get currentModelKey => _follower.model.key;

  /// Everything the bar, the model pickers and the toast draw.
  Map<String, Object?> read() {
    final presets = _storage.genPresets;
    final model = _follower.model;
    return {
      'presets': [
        for (final e in presets.presets.entries)
          {'name': e.key, 'values': e.value.toJson()},
      ],
      'slot': presets.slot,
      'state': _actions.state.name,
      'model': model.isEmpty
          ? null
          : {'key': model.key, 'label': model.label, 'local': model.isLocal},
      'linked': model.isEmpty ? null : presets.linkedPreset(model.key),
      'links': presets.links,
      'recommended': _follower.recommended.value.toJson(),
      'appDefaults': SamplerValues.appDefaults.toJson(),
      'live': _actions.live.toJson(),
      'notice': _follower.notice.value?.toJson(),
    };
  }

  /// Saves as [name]. With [values] (what the page shows, which may not be
  /// saved yet) they become the global values first, so the preset holds
  /// what the user saw.
  Future<void> save(String name, Object? values) async {
    if (values is Map) {
      await SamplerValues.fromJson(
        values,
      ).applyTo(_storage.generationSettings, _storage.backendSettings);
    }
    await _actions.saveAs(name);
  }

  Future<void> load(String name) => _actions.load(name);

  Future<void> delete(String name) => _actions.delete(name);

  Future<void> link(String? name, {String? modelKey}) =>
      _actions.link(name, modelKey: modelKey);

  Future<void> resetAll() => _actions.resetAll();

  /// False when [id] is no longer the latest notice.
  Future<bool> undo(int id) => _follower.undo(id);

  void dismiss(int id) => _follower.dismissNotice(id);
}
