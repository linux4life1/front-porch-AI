// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The edit recipe is now a set of DEFAULT constants (edit_profile.dart), not a
// runtime override: the Image Studio Edit tab seeds its OWN edit-scoped copy of
// the Generation Settings from them, then the service honors whatever the user
// set verbatim. These tests lock the field-tested values (so a stray edit can't
// silently change what a first edit does) and prove a fresh ImageGenSettings
// seeds its edit knobs from the recipe — the footgun-avoiding "first edit just
// works" guarantee — while leaving the Create/txt2img knobs on their own.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/edit_profile.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

void main() {
  group('Edit recipe constants (Qwen-Image-Edit, field-tested)', () {
    test('the values the model needs to produce an image at all', () {
      expect(kEditRecommendedSamplerInt, 17); // UniPC Trailing (DT sampler int)
      expect(kEditRecommendedCfg, 3.5); // moderate — high CFG yields no image
      expect(kEditRecommendedShift, 3.0);
      expect(kEditRecommendedSeedMode, 2); // SCALE_ALIKE
      expect(kEditRecommendedSteps, 20);
      // "Do what I asked": multi-change edits are under-driven below full.
      expect(kEditRecommendedStrength, 1.0);
    });
  });

  group('Edit-scoped storage', () {
    test('a fresh ImageGenSettings seeds its edit knobs from the recipe', () {
      final s = ImageGenSettings(); // no prefs loaded → field defaults
      expect(s.editSteps, kEditRecommendedSteps);
      expect(s.editCfgScale, kEditRecommendedCfg);
      expect(s.editSampler, kEditRecommendedSamplerInt);
      expect(s.editShift, kEditRecommendedShift);
      expect(s.editSeedMode, kEditRecommendedSeedMode);
    });

    test('edit knobs are SEPARATE from the txt2img knobs (no clobber)', () {
      final s = ImageGenSettings();
      // The Create/txt2img defaults are the lightning-friendly low values and
      // must not be affected by the edit recipe living alongside them.
      expect(s.imageGenSteps, isNot(kEditRecommendedSteps));
      expect(s.editSampler, isNot(s.drawThingsSampler));
    });

    test('setting an edit knob never writes the txt2img twin, and vice versa',
        () async {
      final s = ImageGenSettings(); // prefs null → writes only the in-memory field
      final createSampler = s.drawThingsSampler;
      final createCfg = s.imageGenCfgScale;
      final createSteps = s.imageGenSteps;
      final createShift = s.drawThingsShift;
      final createSeedMode = s.drawThingsSeedMode;

      await s.setEditSampler(5);
      await s.setEditCfgScale(9.0);
      await s.setEditSteps(28);
      await s.setEditShift(1.5);
      await s.setEditSeedMode(0);

      // Edit side took the new values...
      expect(s.editSampler, 5);
      expect(s.editCfgScale, 9.0);
      expect(s.editSteps, 28);
      expect(s.editShift, 1.5);
      expect(s.editSeedMode, 0);
      // ...and the Create/txt2img side is untouched.
      expect(s.drawThingsSampler, createSampler);
      expect(s.imageGenCfgScale, createCfg);
      expect(s.imageGenSteps, createSteps);
      expect(s.drawThingsShift, createShift);
      expect(s.drawThingsSeedMode, createSeedMode);

      // The reverse: tuning Create leaves the edit knobs alone.
      await s.setImageGenCfgScale(7.0);
      expect(s.editCfgScale, 9.0);

      // "Use recommended" restores the edit recipe (and still not Create).
      await s.resetEditKnobsToRecommended();
      expect(s.editSampler, kEditRecommendedSamplerInt);
      expect(s.editCfgScale, kEditRecommendedCfg);
      expect(s.imageGenCfgScale, 7.0);
    });
  });
}
