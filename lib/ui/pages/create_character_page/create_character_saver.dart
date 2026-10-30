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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;

import 'create_character_draft.dart';

/// Persists the manual creator's draft as a new card (always-embedded V2
/// PNG; the draft's portrait source, else a placeholder the next step
/// replaces) and adds it to the repository. Throws on failure; the page owns the snackbars.
class CreateCharacterSaver {
  const CreateCharacterSaver({required this.repo, required this.storage});

  final CharacterRepository repo;
  final StorageService storage;

  Future<CharacterCard> save(CreateCharacterDraft draft, String name) async {
    // Always build extensions — even when realism is disabled — so that
    // any configured values survive a round-trip through PNG save/load.
    // The realismEnabled flag controls whether the engine *uses* them at
    // runtime, not whether they are persisted.
    final fpExt = FrontPorchExtensions(
      realismEnabled: draft.realismEnabled,
      shortTermBond: draft.realismShortTermBond,
      longTermBond: draft.realismLongTermBond,
      trustLevel: draft.realismTrustLevel,
      dayCount: draft.realismDayCount,
      timeOfDay: draft.realismTimeOfDay,
      storyStartDate: draft.realismStoryStartDate,
      storyStartTime: draft.realismStoryStartTime,
      characterEmotion: draft.realismEmotion,
      emotionIntensity: draft.realismEmotionIntensity,
      nsfwCooldownEnabled: draft.realismNsfwCooldown,
      passageOfTimeEnabled: true, // default on; user can toggle later
      chaosModeEnabled: draft.realismChaosMode,
      afterglowEnabled: draft.realismAfterglow,
      needsSimEnabled: draft.realismNeedsSim,
      pocketsEnabled: draft.realismPocketsEnabled,
      enjoysLowHygiene: draft.realismEnjoysLowHygiene,
      ambitions: draft.realismAmbitions,
      planLines: draft.realismPlanLines,
      occupation: draft.realismOccupation,
      occupationBrief: draft.realismOccupationBrief,
      hours: draft.realismHours,
      workDays: draft.realismWorkDays,
      birthday: draft.realismBirthday,
      likes: draft.realismLikes,
      dislikes: draft.realismDislikes,
      intimateInto: draft.realismIntimateInto,
      intimateNotInto: draft.realismIntimateNotInto,
      recovery: draft.realismRecovery,
      // Through the shared normalizer, so a wardrobe typed here and the same
      // wardrobe typed in the edit page land on the card identically. The
      // neighbouring lists deliberately stay raw and are tidied at parse
      // time; wardrobe cannot, because splitting `name (state)` apart is not
      // something the card parser can do after the fact.
      inventory: Pockets.cardJsonFrom(
        worn: draft.realismWorn,
        carrying: draft.realismCarrying,
      ),
      realismVerificationEnabled: draft.realismVerificationEnabled,
      realismVerificationMaxReprocesses:
          draft.realismVerificationMaxReprocesses,
      realismVerificationStrictness: draft.realismVerificationStrictness,
      realismNeedsDirectorAuthority: draft.realismNeedsDirectorAuthority,
      needsBaselineHunger: draft.needsBaselineHunger,
      needsBaselineBladder: draft.needsBaselineBladder,
      needsBaselineEnergy: draft.needsBaselineEnergy,
      needsBaselineSocial: draft.needsBaselineSocial,
      needsBaselineFun: draft.needsBaselineFun,
      needsBaselineHygiene: draft.needsBaselineHygiene,
      needsBaselineComfort: draft.needsBaselineComfort,
      needsPace: draft.needsPace,
      needsOff: draft.needsOff,
      greetingSeeds: compactGreetingPairs([
        for (final c in draft.altGreetingControllers) c.text,
      ], draft.altGreetingSeeds).seeds,
    );

    fpExt.ensureStableId();

    final card = CharacterCard(
      name: name,
      description: draft.descriptionController.text,
      personality: draft.personalityController.text,
      scenario: draft.scenarioController.text,
      firstMessage: draft.firstMessageController.text,
      mesExample: draft.exampleDialogueController.text,
      systemPrompt: draft.systemPromptController.text,
      postHistoryInstructions: draft.postHistoryController.text,
      alternateGreetings: compactGreetingPairs([
        for (final c in draft.altGreetingControllers) c.text,
      ], draft.altGreetingSeeds).greetings,
      tags: List.from(draft.tags),
      lorebook: draft.lorebookEntries.isNotEmpty
          ? Lorebook(entries: List.from(draft.lorebookEntries))
          : null,
      frontPorchExtensions: fpExt,
    );

    // Determine PNG path — always write a PNG so card data (including
    // Realism Engine extensions) can be embedded and survive app restarts.
    // Placeholder image for now: the Portrait & Avatars step overwrites the
    // pixels in place (same basename — folders key members on it).
    final charDir = storage.charactersDir;
    // Sync I/O is fine here: a one-shot save action, never a build path.
    final dirExists = charDir.existsSync(); // io-ok: save action
    if (!dirExists) charDir.createSync(recursive: true); // io-ok: save action
    final epoch = DateTime.now().millisecondsSinceEpoch;
    final safeName = name
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(' ', '_');
    final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
    card.imagePath = imagePath;
    final v2Service = V2CardService();
    await v2Service.saveCardAsPng(card, imagePath, draft.portraitSourcePath);
    debugPrint(
      '[CreateCharacter] Saved PNG with extensions: '
      'realism=${fpExt.realismEnabled}, bond=${fpExt.shortTermBond}, '
      'trust=${fpExt.trustLevel}, emotion=${fpExt.characterEmotion}',
    );

    // Add to repository
    await repo.addCharacter(card);
    return card;
  }
}
