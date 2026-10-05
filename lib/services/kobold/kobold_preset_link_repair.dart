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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

// A leaf, not storage_service.dart: storage runs this while it starts.
import 'package:front_porch_ai/services/storage/settings/preset_settings.dart';

import 'kcpps_codec.dart';

/// Set once the repair has run, so it never runs again.
const String _kRepaired = 'kobold_preset_links_repaired';

/// Removes, once, the links from a model to a preset that loads a different
/// model. Before Phase 9 the app kept a preset under whichever model a
/// screen showed, so a preset naming model B could sit under model A, and
/// choosing A started B. Only such links go: the preset names another model
/// and that model's file is on this computer. A link whose preset names no
/// model, names this one, names one that is not here, or whose file is
/// gone, is kept, and nothing else is touched. Each removal is logged in
/// plain words.
///
/// [engineDir] is the folder KoboldCpp runs in, which a relative model path
/// in a preset is relative to.
Future<void> repairKoboldPresetLinks(
  PresetSettings presets, {
  required String engineDir,
}) async {
  final prefs = presets.prefs;
  if (prefs == null) return;
  final ran = presets.k(_kRepaired);
  if (prefs.getBool(ran) ?? false) return;
  for (final link in presets.modelPresetMap.entries.toList()) {
    final model = link.key;
    final preset = link.value;
    final loads = await _modelNamedBy(preset, engineDir);
    if (loads == null || p.equals(loads, model)) continue;
    if (!await File(loads).exists()) continue;
    await presets.setModelPreset(model, null);
    debugPrint(
      '[Presets] The preset "${p.basename(preset)}" was kept for the model '
      '"${p.basename(model)}", but it loads "${p.basename(loads)}", so '
      'choosing ${p.basename(model)} started the other model. The link was '
      'removed; the preset itself is unchanged.',
    );
  }
  await prefs.setBool(ran, true);
}

/// The model the preset at [preset] loads, or null when it names none or
/// cannot be read.
Future<String?> _modelNamedBy(String preset, String engineDir) async {
  if (preset.trim().isEmpty) return null;
  final String text;
  try {
    text = await File(preset).readAsString();
  } on Object catch (e) {
    // Gone or unreadable: the link is kept, and a launch drops it anyway.
    debugPrint('[Presets] "$preset" could not be read ($e); its link is kept.');
    return null;
  }
  final read = readKcpps(text);
  if (read is! KcppsOk) return null;
  final named = kcppsModelOf(read.raw, engineDir: engineDir);
  return named.isEmpty ? null : named;
}
