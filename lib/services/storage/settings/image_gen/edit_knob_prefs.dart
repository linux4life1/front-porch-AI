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

import '../../../image/edit_profile.dart';
import '../settings_base.dart';

/// Edit-scoped generation knobs (Image Studio → Edit tab, instruction-edit
/// models like Qwen-Image-Edit). Kept SEPARATE from the txt2img knobs so
/// tuning an edit never clobbers Create's sampler/CFG/steps — the two model
/// families want very different values. Seeded from the field-tested recipe
/// (edit_profile.dart) and then honored verbatim; nothing overrides them.
mixin ImageGenEditKnobPrefs on SettingsBase {
  int _editSteps = kEditRecommendedSteps;
  double _editCfgScale = kEditRecommendedCfg;
  int _editSampler = kEditRecommendedSamplerInt;
  double _editShift = kEditRecommendedShift;
  int _editSeedMode = kEditRecommendedSeedMode;

  int get editSteps => _editSteps;
  double get editCfgScale => _editCfgScale;
  int get editSampler => _editSampler;
  double get editShift => _editShift;
  int get editSeedMode => _editSeedMode;

  void loadEditKnobPrefs() {
    _editSteps =
        prefs?.getInt(k('image_gen_edit_steps')) ?? kEditRecommendedSteps;
    _editCfgScale =
        prefs?.getDouble(k('image_gen_edit_cfg_scale')) ?? kEditRecommendedCfg;
    _editSampler =
        prefs?.getInt(k('draw_things_edit_sampler')) ??
        kEditRecommendedSamplerInt;
    _editShift =
        prefs?.getDouble(k('draw_things_edit_shift')) ?? kEditRecommendedShift;
    _editSeedMode =
        prefs?.getInt(k('draw_things_edit_seed_mode')) ??
        kEditRecommendedSeedMode;
  }

  // Same clamps as their txt2img twins; they persist to their own keys so
  // Create's knobs are never touched.
  Future<void> setEditSteps(int value) async {
    _editSteps = value.clamp(1, 50);
    await prefs?.setInt(k('image_gen_edit_steps'), _editSteps);
    notify();
  }

  Future<void> setEditCfgScale(double value) async {
    _editCfgScale = value.clamp(1.0, 20.0);
    await prefs?.setDouble(k('image_gen_edit_cfg_scale'), _editCfgScale);
    notify();
  }

  Future<void> setEditSampler(int value) async {
    _editSampler = value;
    await prefs?.setInt(k('draw_things_edit_sampler'), value);
    notify();
  }

  Future<void> setEditShift(double value) async {
    _editShift = value;
    await prefs?.setDouble(k('draw_things_edit_shift'), value);
    notify();
  }

  Future<void> setEditSeedMode(int value) async {
    _editSeedMode = value;
    await prefs?.setInt(k('draw_things_edit_seed_mode'), value);
    notify();
  }

  /// One-tap "Use recommended edit settings" — writes the field-tested edit
  /// recipe back into the edit-scoped knobs (never touches the Create knobs).
  Future<void> resetEditKnobsToRecommended() async {
    await setEditSteps(kEditRecommendedSteps);
    await setEditCfgScale(kEditRecommendedCfg);
    await setEditSampler(kEditRecommendedSamplerInt);
    await setEditShift(kEditRecommendedShift);
    await setEditSeedMode(kEditRecommendedSeedMode);
  }
}
