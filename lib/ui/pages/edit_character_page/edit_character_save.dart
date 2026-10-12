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
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';

List<String> _trimmed(List<String> items) => [
  for (final a in items)
    if (a.trim().isNotEmpty) a.trim(),
];

/// Writes an [EditCharacterDraft] back onto its [CharacterCard]: the field
/// write-back, the PNG re-embed and the lorebook. Persisting the row (library
/// or group override) stays with the page, which owns context and `mounted`.
class EditCharacterCardWriter {
  final CharacterCard character;
  final EditCharacterDraft draft;

  const EditCharacterCardWriter({required this.character, required this.draft});

  /// Worlds linked in THIS edit (not present when the editor opened).
  List<String> get addedWorlds => draft.selectedWorldNames
      .where((w) => !draft.initialWorldNames.contains(w))
      .toList();

  void writeFields({required bool showRealismTab}) {
    final d = draft;
    character.name = d.nameController.text;
    character.description = d.descriptionController.text;
    character.personality = d.personalityController.text;
    character.scenario = d.scenarioController.text;
    character.firstMessage = d.firstMessageController.text;
    character.mesExample = d.mesExampleController.text;
    character.systemPrompt = d.systemPromptController.text;
    character.postHistoryInstructions = d.postHistoryController.text;
    final greetingPairs = compactGreetingPairs([
      for (final c in d.altGreetingControllers) c.text,
    ], d.altGreetingSeeds);
    character.alternateGreetings = greetingPairs.greetings;
    character.tags = List.from(d.tags);
    // Empty clears the per-character override so the character
    // follows the global Settings voice again (null, not '', so
    // the card round-trip omits the field entirely).
    character.ttsVoice = d.ttsVoice.isEmpty ? null : d.ttsVoice;
    character.worldNames = d.selectedWorldNames;

    // Always persist extensions — even when realism is disabled — so that
    // configured-but-disabled values survive the PNG round-trip. Skipped when
    // the Realism section is hidden (group member): the member's existing
    // realism/needs ext is group state and must be preserved untouched.
    // The identity chips — Ambitions, Likes & Dislikes, the 18+ pair and
    // Pockets & Wardrobe kit — live OUTSIDE the realism section. The
    // per-character Pockets switch on that panel sets
    // `realismSettingsModified` so turning it off still writes. The rest
    // of the chips do not; they persist via hasIdentityContent below.
    //
    // So for a character with the Realism Engine off, no realism control
    // touched, and no extensions yet, this whole block was skipped: everything
    // typed into those chips was discarded before the PNG was written. The
    // symptom is exactly what the report showed —
    //   About to save PNG with extensions: false
    //   ✗ PNG verification FAILED: no extensions in saved file!
    // — with no "Saving realism:" line above it, because the block never ran.
    //
    // Checked as DATA rather than by setting the modified flag in seven
    // callbacks. A flag has to be remembered by every chip added later; "did
    // the user author any of this" cannot be forgotten. Clearing the last item
    // on a card that HAS extensions still writes, via the clause below it.
    final hasIdentityContent =
        d.ambitions.isNotEmpty ||
        d.planLines.isNotEmpty ||
        d.occupation.trim().isNotEmpty ||
        d.occupationBrief.trim().isNotEmpty ||
        d.hours.trim().isNotEmpty ||
        d.birthday.trim().isNotEmpty ||
        d.likes.isNotEmpty ||
        d.dislikes.isNotEmpty ||
        d.intimateInto.isNotEmpty ||
        d.intimateNotInto.isNotEmpty ||
        d.worn.isNotEmpty ||
        d.carrying.isNotEmpty;

    final hasGreetingSeeds = compactGreetingSeeds(
      d.altGreetingSeeds,
    ).isNotEmpty;
    if (showRealismTab &&
        (d.realismEnabled ||
            d.realismSettingsModified ||
            hasIdentityContent ||
            hasGreetingSeeds ||
            character.frontPorchExtensions != null)) {
      debugPrint(
        '[_saveCharacter] Saving realism: enabled=${d.realismEnabled}, modified=${d.realismSettingsModified}',
      );
      _writeExtensions(greetingPairs.seeds);
    }
  }

  void _writeExtensions(List<GreetingRealismSeed?> greetingSeeds) {
    final d = draft;
    // Use copyWith from existing (if any) to preserve non-realism FP state
    // (colors, font, avatarLocked, etc.) that the bare ctor would drop.
    // stableId is carried by copyWith; ensure after (addresses review Issue 1).
    final base = character.frontPorchExtensions ?? FrontPorchExtensions();
    character.frontPorchExtensions = base.copyWith(
      realismEnabled: d.realismEnabled,
      shortTermBond: d.realismShortTermBond,
      longTermBond: d.realismLongTermBond,
      trustLevel: d.realismTrustLevel,
      dayCount: d.realismDayCount,
      timeOfDay: d.realismTimeOfDay,
      characterEmotion: d.realismEmotion,
      emotionIntensity: d.realismEmotionIntensity,
      nsfwCooldownEnabled: d.realismNsfwCooldown,
      passageOfTimeEnabled: d.realismPassageOfTime,
      chaosModeEnabled: d.realismChaosMode,
      // Null keeps a silent card silent (copyWith keeps the base's null)
      // unless the switch moved off the Porch Life value it showed.
      needsSimEnabled: d.realismNeedsSim == d.needsSimShownForSilent
          ? null
          : d.realismNeedsSim,
      pocketsEnabled: d.realismPocketsEnabled,
      enjoysLowHygiene: d.realismEnjoysLowHygiene,
      ambitions: _trimmed(d.ambitions),
      planLines: _trimmed(d.planLines),
      occupation: d.occupation.trim(),
      occupationBrief: d.occupationBrief.trim(),
      hours: d.hours.trim(),
      workDays: d.workDays,
      birthday: d.birthday.trim(),
      likes: _trimmed(d.likes),
      dislikes: _trimmed(d.dislikes),
      intimateInto: _trimmed(d.intimateInto),
      intimateNotInto: _trimmed(d.intimateNotInto),
      // Not the inline trim the lists above use: wardrobe entries carry a
      // condition, so normalizing them means parsing `name (state)` apart,
      // capping both halves and applying the per-list caps. That belongs in
      // one place shared with the two creators, not copied three times with
      // three slightly different rules — which is exactly how the lists
      // above ended up disagreeing.
      inventory: Pockets.cardJsonFrom(worn: d.worn, carrying: d.carrying),
      currentTask: d.realismCurrentTask,
      greetingSeeds: greetingSeeds,
      realismVerificationEnabled: d.realismVerificationEnabled,
      realismVerificationMaxReprocesses: d.realismVerificationMaxReprocesses,
      realismVerificationStrictness: d.realismVerificationStrictness,
      realismNeedsDirectorAuthority: d.realismNeedsDirectorAuthority,
      needsPace: d.needsPace,
      needsOff: d.needsOff,
      needsBaselineHunger: d.needsBaselineHunger,
      needsBaselineBladder: d.needsBaselineBladder,
      needsBaselineEnergy: d.needsBaselineEnergy,
      needsBaselineSocial: d.needsBaselineSocial,
      needsBaselineFun: d.needsBaselineFun,
      needsBaselineHygiene: d.needsBaselineHygiene,
      needsBaselineComfort: d.needsBaselineComfort,
    );
    // Direct assignment (not copyWith): its `?? this.x` pattern cannot
    // CLEAR a nullable field, and "clear the fixed start date back to 'the
    // day the chat starts'" is a real edit.
    character.frontPorchExtensions!
      ..storyStartDate = d.realismStoryStartDate
      ..storyStartTime = d.realismStoryStartTime;
    character.frontPorchExtensions!.ensureStableId();
  }

  /// The portrait is no longer changed from this page (managed in the Avatar
  /// Gallery) — re-embed the V2 card data into the current imagePath PNG to
  /// preserve the edited extensions/fields.
  Future<void> embedPng(StorageService storage) async {
    String? targetPngPath;
    if (character.imagePath != null && character.imagePath!.isNotEmpty) {
      final img = character.imagePath!;
      targetPngPath = p.isAbsolute(img)
          ? img
          : p.join(storage.charactersDir.path, img);
    }

    if (targetPngPath == null) {
      debugPrint(
        '[_saveCharacter] WARNING: targetPngPath is null, skipping PNG save!',
      );
      return;
    }
    try {
      debugPrint(
        '[_saveCharacter] About to save PNG with extensions: ${character.frontPorchExtensions != null}',
      );
      await V2CardService().saveCardAsPng(
        character,
        targetPngPath,
        targetPngPath,
      );
      debugPrint(
        '[_saveCharacter] PNG saved successfully for ${character.name} to $targetPngPath',
      );

      // Verify PNG was written by reading it back immediately
      try {
        final reloaded = await V2CardService().readCard(targetPngPath);
        if (reloaded?.frontPorchExtensions != null) {
          debugPrint(
            '[_saveCharacter] ✓ PNG verification successful: extensions found in saved file',
          );
        } else {
          debugPrint(
            '[_saveCharacter] ✗ PNG verification FAILED: no extensions in saved file!',
          );
        }
      } catch (verifyError) {
        debugPrint(
          '[_saveCharacter] PNG verification read failed: $verifyError',
        );
      }
    } catch (e) {
      debugPrint('Failed to embed V2 card data: $e');
    }
  }

  void writeLorebook() {
    if (character.lorebook == null) {
      character.lorebook = Lorebook(entries: draft.loreEntries);
    } else {
      character.lorebook!.entries = draft.loreEntries;
    }
  }
}
