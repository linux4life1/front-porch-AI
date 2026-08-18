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

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/ui/character_creator/chargen_json.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

part 'creator_state_engine.tools.dart';
part 'creator_state_engine.modes.dart';
part 'creator_state_engine.core.dart';

/// The real generation + save engine for the AI character creator, restored
/// faithfully from the pre-refactor implementation. Lives as an extension so
/// `creator_state.dart` stays focused on state and under the file-size cap.
///
/// All `BuildContext`/`Provider`/`setState` usage from the original is replaced
/// by explicit service parameters and `notify()` — the engine holds no context.
/// SnackBars, the accept/reject dialog, and `Navigator.pop` are the caller's
/// responsibility (the steps own the context); the engine returns the data they
/// need (e.g. `saveCharacter` returns success, `expandNarrative` returns text).
///
/// The three mode entry points funnel through a single `_runGeneration` core so
/// the LLM-service resolution, persona context, world-lore extraction, and
/// post-generation wiring exist once instead of being triplicated.
///
/// This file holds the save/portrait spine only; the field-tool generators
/// (`expandNarrative`/`randomizeName`/`randomizeConcept`) live in the public
/// `CreatorEngineTools` extension (creator_state_engine.tools.dart), the mode
/// assemblers in `_CreatorModes` (creator_state_engine.modes.dart), and the
/// shared generation core in `_CreatorCore` (creator_state_engine.core.dart) —
/// all parts of this library so they can share private state access.
extension CreatorEngine on CreatorState {
  // ── Public entry points ──────────────────────────────────────────────

  /// Dispatch generation for the currently selected mode.
  Future<void> generateFromMode({
    required LLMProvider llmProvider,
    required StorageService storage,
    required UserPersonaService personaService,
  }) {
    switch (creatorMode) {
      case CreatorMode.quick:
        return _generateQuick(llmProvider, storage, personaService);
      case CreatorMode.guided:
        return _generateGuided(llmProvider, storage, personaService);
      case CreatorMode.automated:
        return _generateAutomated(llmProvider, storage, personaService);
    }
  }

  /// Persist the generated (and possibly edited) card. Returns true on success;
  /// the caller shows the SnackBar and pops on true, or surfaces [engineError]
  /// on false.
  Future<bool> saveCharacter({
    required CharacterRepository repo,
    required StorageService storage,
  }) async {
    final card = generatedCard;
    if (card == null) return false;
    try {
      card.description = descController.text;
      card.personality = personalityController.text;
      card.scenario = scenarioController.text;
      card.firstMessage = firstMessageController.text;
      card.mesExample = exampleDialogueController.text;
      card.systemPrompt = systemPromptController.text;

      // Always build the V2.5 extensions — even when realism is disabled — so
      // configured realism/needs values AND the stable tracking id survive the
      // PNG round-trip. realismEnabled only controls whether the engine *uses*
      // them at runtime, matching create_character_page's behaviour.
      final fpExt = FrontPorchExtensions(
        realismEnabled: realismStepEnabled,
        shortTermBond: realismShortTermBond,
        longTermBond: realismLongTermBond,
        trustLevel: realismTrustLevel,
        dayCount: realismDayCount,
        timeOfDay: realismTimeOfDay,
        storyStartDate: realismStoryStartDate,
        storyStartTime: realismStoryStartTime,
        characterEmotion: realismEmotion,
        emotionIntensity: realismEmotionIntensity,
        nsfwCooldownEnabled: realismNsfwCooldown,
        chaosModeEnabled: realismChaosMode,
        needsSimEnabled: realismNeedsSim,
        enjoysLowHygiene: realismEnjoysLowHygiene,
        ambitions: realismAmbitions,
        planLines: realismPlanLines,
        occupation: realismOccupation,
        hours: realismHours,
        likes: realismLikes,
        dislikes: realismDislikes,
        intimateInto: realismIntimateInto,
        intimateNotInto: realismIntimateNotInto,
        // Same shared normalizer as the other two authoring surfaces.
        inventory: Pockets.cardJsonFrom(
          worn: realismWorn,
          carrying: realismCarrying,
        ),
        realismVerificationEnabled: realismVerificationEnabled,
        realismVerificationMaxReprocesses: realismVerificationMaxReprocesses,
        realismVerificationStrictness: realismVerificationStrictness,
        realismNeedsDirectorAuthority: realismNeedsDirectorAuthority,
        needsBaselineHunger: needsBaselineHunger,
        needsBaselineBladder: needsBaselineBladder,
        needsBaselineEnergy: needsBaselineEnergy,
        needsBaselineSocial: needsBaselineSocial,
        needsBaselineFun: needsBaselineFun,
        needsBaselineHygiene: needsBaselineHygiene,
        needsBaselineComfort: needsBaselineComfort,
        needsDecayHunger: needsDecayHunger,
        needsDecayBladder: needsDecayBladder,
        needsDecayEnergy: needsDecayEnergy,
        needsDecaySocial: needsDecaySocial,
        needsDecayFun: needsDecayFun,
        needsDecayHygiene: needsDecayHygiene,
        needsDecayComfort: needsDecayComfort,
      );
      // Save is MULTI-SHOT now (the Portrait & Avatars panel persists before
      // it generates; Save & Finish updates the same card), so identity
      // fields the wizard doesn't own MUST carry over — rebuilding without
      // them would mint a fresh stableId on every save and silently break
      // export/re-import identity (Grok review finding, 2026-07-17).
      final prior = card.frontPorchExtensions;
      fpExt.stableId = prior?.stableId;
      fpExt.favoriteAvatarId = prior?.favoriteAvatarId;
      // Stable tracking UUID: ensures later realism/needs edits update this
      // character in place instead of decoupling it from its DB row.
      fpExt.ensureStableId();
      card.frontPorchExtensions = fpExt;

      // Drop lorebook entries the user unchecked in the Review step.
      final lore = card.lorebook;
      if (lore != null && lorebookEntryEnabled.isNotEmpty) {
        final filtered = <LorebookEntry>[];
        for (int i = 0; i < lore.entries.length; i++) {
          if (lorebookEntryEnabled[i] ?? true) filtered.add(lore.entries[i]);
        }
        card.lorebook = Lorebook(entries: filtered);
      }

      if (card.dbId == null) {
        // First save. Always give the card its V2 PNG (placeholder pixels —
        // the Portrait & Avatars panel overwrites them IN PLACE post-save),
        // so the extensions survive restarts and later updates have a file
        // to re-embed into. Mirrors create_character_page's save.
        final charDir = storage.charactersDir;
        if (!charDir.existsSync()) charDir.createSync(recursive: true);
        final epoch = DateTime.now().millisecondsSinceEpoch;
        final safeName = card.name
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .replaceAll(' ', '_');
        final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
        card.imagePath = imagePath;
        await V2CardService().saveCardAsPng(card, imagePath, null);
        await repo.addCharacter(card);
      } else {
        // Already persisted (the Portrait & Avatars panel saves before it
        // generates) — Save & Finish just updates the same card in place.
        await repo.updateCharacter(card);
      }
      await clearSavedFormPrefsAfterSave();
      return true;
    } catch (e, st) {
      debugPrint('CharacterCreator: save failed: $e\n$st');
      engineError = 'Failed to save character: $e';
      notify();
      return false;
    }
  }

  /// The Portrait & Avatars panel's prompt SEED: the LLM-authored image
  /// prompt (name stripped — it means nothing to a diffusion model) when the
  /// generation produced one, else visual tags assembled from the filled
  /// fields. The panel's prompt field stays fully editable — this only
  /// pre-fills it.
  String buildPortraitPromptSeed() {
    final llmPrompt = imagePrompt;
    if (llmPrompt != null && llmPrompt.isNotEmpty) {
      // Strip the character name out of the LLM-authored prompt.
      String clean = llmPrompt;
      final charName = nameController.text.trim();
      if (charName.isNotEmpty) {
        clean = clean
            .replaceAll(
              RegExp(RegExp.escape(charName), caseSensitive: false),
              '',
            )
            .trim();
        for (final part in charName.split(RegExp(r'\s+'))) {
          if (part.length > 2) {
            clean = clean
                .replaceAll(
                  RegExp(
                    '\\b${RegExp.escape(part)}\\b',
                    caseSensitive: false,
                  ),
                  '',
                )
                .trim();
          }
        }
        clean = clean
            .replaceAll(RegExp(r',\s*,'), ',')
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();
        if (clean.startsWith(',')) clean = clean.substring(1).trim();
      }
      return '$clean, $artStyle style';
    }
    // Fallback: assemble visual tags from whatever the user provided.
    final tags = <String>['character portrait', '$artStyle style'];
    final sex = sexController.text.trim();
    final age = ageController.text.trim();
    if (sex.isNotEmpty) tags.add(sex.toLowerCase());
    if (age.isNotEmpty) tags.add('$age years old');
    if (guidedAppearanceController.text.trim().isNotEmpty) {
      tags.add(guidedAppearanceController.text.trim());
    }
    if (guidedHairController.text.trim().isNotEmpty) {
      tags.add(guidedHairController.text.trim());
    }
    if (guidedFeaturesController.text.trim().isNotEmpty) {
      tags.add(guidedFeaturesController.text.trim());
    }
    if (guidedRaceController.text.trim().isNotEmpty) {
      tags.add(guidedRaceController.text.trim());
    }
    if (tags.length <= 4 && descController.text.trim().isNotEmpty) {
      final snippet = descController.text.trim();
      tags.add(snippet.length > 150 ? snippet.substring(0, 150) : snippet);
    }
    return tags.join(', ');
  }
}
