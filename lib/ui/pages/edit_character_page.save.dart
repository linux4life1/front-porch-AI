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
//
// Persist the editor: field write-back, PNG re-embed, library/group save.
// Extracted from edit_character_page.dart so the library file stays under
// the 1,000-line god-file ratchet; `part of` the same library.

part of 'edit_character_page.dart';

extension _EditCharacterSave on _EditCharacterPageState {
  Future<void> _saveCharacter() async {
    // Update model
    widget.character.name = _nameController.text;
    widget.character.description = _descriptionController.text;
    widget.character.personality = _personalityController.text;
    widget.character.scenario = _scenarioController.text;
    widget.character.firstMessage = _firstMessageController.text;
    widget.character.mesExample = _mesExampleController.text;
    widget.character.systemPrompt = _systemPromptController.text;
    widget.character.postHistoryInstructions = _postHistoryController.text;
    final greetingPairs = compactGreetingPairs(
      [for (final c in _altGreetingControllers) c.text],
      _altGreetingSeeds,
    );
    widget.character.alternateGreetings = greetingPairs.greetings;
    widget.character.tags = List.from(_tags);
    // Empty clears the per-character override so the character
    // follows the global Settings voice again (null, not '', so
    // the card round-trip omits the field entirely).
    widget.character.ttsVoice = _ttsVoice.isEmpty ? null : _ttsVoice;
    widget.character.worldNames = _selectedWorldNames;

    // Always persist extensions — even when realism is disabled — so that
    // configured-but-disabled values survive the PNG round-trip. Skipped when
    // the Realism section is hidden (group member): the member's existing
    // realism/needs ext is group state and must be preserved untouched.
    // The identity chips — Ambitions, Likes & Dislikes, the 18+ pair and
    // Pockets & Wardrobe — are written into frontPorchExtensions but live
    // OUTSIDE the realism section, and not one of them sets
    // `_realismSettingsModified` (every control that does is in
    // edit_character_page.realism_section.dart).
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
        _ambitions.isNotEmpty ||
        _planLines.isNotEmpty ||
        _occupation.trim().isNotEmpty ||
        _occupationBrief.trim().isNotEmpty ||
        _hours.trim().isNotEmpty ||
        _likes.isNotEmpty ||
        _dislikes.isNotEmpty ||
        _intimateInto.isNotEmpty ||
        _intimateNotInto.isNotEmpty ||
        _worn.isNotEmpty ||
        _carrying.isNotEmpty;

    final hasGreetingSeeds = compactGreetingSeeds(_altGreetingSeeds).isNotEmpty;
    if (widget.showRealismTab &&
        (_realismEnabled ||
            _realismSettingsModified ||
            hasIdentityContent ||
            hasGreetingSeeds ||
            widget.character.frontPorchExtensions != null)) {
      debugPrint(
        '[_saveCharacter] Saving realism: enabled=$_realismEnabled, modified=$_realismSettingsModified',
      );
      // Use copyWith from existing (if any) to preserve non-realism FP state
      // (colors, font, avatarLocked, etc.) that the bare ctor would drop.
      // stableId is carried by copyWith; ensure after (addresses review Issue 1).
      final base =
          widget.character.frontPorchExtensions ?? FrontPorchExtensions();
      widget.character.frontPorchExtensions = base.copyWith(
        realismEnabled: _realismEnabled,
        shortTermBond: _realismShortTermBond,
        longTermBond: _realismLongTermBond,
        trustLevel: _realismTrustLevel,
        dayCount: _realismDayCount,
        timeOfDay: _realismTimeOfDay,
        characterEmotion: _realismEmotion,
        emotionIntensity: _realismEmotionIntensity,
        nsfwCooldownEnabled: _realismNsfwCooldown,
        passageOfTimeEnabled: _realismPassageOfTime,
        chaosModeEnabled: _realismChaosMode,
        needsSimEnabled: _realismNeedsSim,
        enjoysLowHygiene: _realismEnjoysLowHygiene,
        ambitions: [
          for (final a in _ambitions)
            if (a.trim().isNotEmpty) a.trim(),
        ],
        planLines: [
          for (final a in _planLines)
            if (a.trim().isNotEmpty) a.trim(),
        ],
        occupation: _occupation.trim(),
        occupationBrief: _occupationBrief.trim(),
        hours: _hours.trim(),
        workDays: _workDays,
        likes: [
          for (final a in _likes)
            if (a.trim().isNotEmpty) a.trim(),
        ],
        dislikes: [
          for (final a in _dislikes)
            if (a.trim().isNotEmpty) a.trim(),
        ],
        intimateInto: [
          for (final a in _intimateInto)
            if (a.trim().isNotEmpty) a.trim(),
        ],
        intimateNotInto: [
          for (final a in _intimateNotInto)
            if (a.trim().isNotEmpty) a.trim(),
        ],
        // Not the inline trim the lists above use: wardrobe entries carry a
        // condition, so normalizing them means parsing `name (state)` apart,
        // capping both halves and applying the per-list caps. That belongs in
        // one place shared with the two creators, not copied three times with
        // three slightly different rules — which is exactly how the lists
        // above ended up disagreeing.
        inventory: Pockets.cardJsonFrom(worn: _worn, carrying: _carrying),
        currentTask: _realismCurrentTask,
        greetingSeeds: greetingPairs.seeds,
        realismVerificationEnabled: _realismVerificationEnabled,
        realismVerificationMaxReprocesses: _realismVerificationMaxReprocesses,
        realismVerificationStrictness: _realismVerificationStrictness,
        realismNeedsDirectorAuthority: _realismNeedsDirectorAuthority,
        needsSimStrength: _needsSimStrength,
        needsBaselineHunger: _needsBaselineHunger,
        needsBaselineBladder: _needsBaselineBladder,
        needsBaselineEnergy: _needsBaselineEnergy,
        needsBaselineSocial: _needsBaselineSocial,
        needsBaselineFun: _needsBaselineFun,
        needsBaselineHygiene: _needsBaselineHygiene,
        needsBaselineComfort: _needsBaselineComfort,
        needsDecayHunger: _needsDecayHunger,
        needsDecayBladder: _needsDecayBladder,
        needsDecayEnergy: _needsDecayEnergy,
        needsDecaySocial: _needsDecaySocial,
        needsDecayFun: _needsDecayFun,
        needsDecayHygiene: _needsDecayHygiene,
        needsDecayComfort: _needsDecayComfort,
      );
      // Direct assignment (not copyWith): its `?? this.x` pattern cannot
      // CLEAR a nullable field, and "clear the fixed start date back to 'the
      // day the chat starts'" is a real edit.
      widget.character.frontPorchExtensions!
        ..storyStartDate = _realismStoryStartDate
        ..storyStartTime = _realismStoryStartTime;
      widget.character.frontPorchExtensions!.ensureStableId();
    }

    // The portrait is no longer changed from this page (managed in the Avatar
    // Gallery) — re-embed the V2 card data into the current imagePath PNG to
    // preserve the edited extensions/fields.
    final storage = Provider.of<StorageService>(context, listen: false);
    String? targetPngPath;
    if (widget.character.imagePath != null &&
        widget.character.imagePath!.isNotEmpty) {
      final img = widget.character.imagePath!;
      targetPngPath = p.isAbsolute(img)
          ? img
          : p.join(storage.charactersDir.path, img);
    }

    if (targetPngPath != null) {
      try {
        debugPrint(
          '[_saveCharacter] About to save PNG with extensions: ${widget.character.frontPorchExtensions != null}',
        );
        await V2CardService().saveCardAsPng(
          widget.character,
          targetPngPath,
          targetPngPath,
        );
        debugPrint(
          '[_saveCharacter] PNG saved successfully for ${widget.character.name} to $targetPngPath',
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
    } else {
      debugPrint(
        '[_saveCharacter] WARNING: targetPngPath is null, skipping PNG save!',
      );
    }

    // Update Lorebook
    if (widget.character.lorebook == null) {
      widget.character.lorebook = Lorebook(entries: _loreEntries);
    } else {
      widget.character.lorebook!.entries = _loreEntries;
    }

    try {
      if (widget.onSaveOverride != null) {
        // Delegated persistence (e.g. a group member → its group row, never the
        // library). The field updates + PNG save above already ran on the card.
        await widget.onSaveOverride!(widget.character);
      } else {
        await Provider.of<CharacterRepository>(
          context,
          listen: false,
        ).updateCharacter(widget.character);

        // Refresh the "Enjoys low hygiene" flag in any active chat so that
        // toggling it on the character immediately affects existing sessions
        // (without requiring a database change).
        if (mounted) {
          try {
            final chatService = Provider.of<ChatService>(
              context,
              listen: false,
            );
            chatService.refreshEnjoysLowHygieneFromActiveCharacter();
          } catch (_) {
            // ChatService not available in this context — that's fine.
          }
        }

        // Worlds added in THIS edit back-fill the character's existing chats
        // that have none. Creation-time seeding only covers chats made after
        // the character already had a world, so a chat opened first and given
        // a world later would otherwise keep its temperate default forever
        // (climate, Setting prose and the Places panel all read the CHAT's
        // attachments, never the character's list).
        final addedWorlds = _selectedWorldNames
            .where((w) => !_initialWorldNames.contains(w))
            .toList();
        final charId = widget.character.dbId;
        if (addedWorlds.isNotEmpty && charId != null) {
          try {
            final worlds = Provider.of<WorldRepository>(context, listen: false);
            final touched = await worlds.applyAddedCharacterWorldsToChats(
              characterId: charId,
              addedRefs: addedWorlds,
            );
            if (touched.isNotEmpty && mounted) {
              final chatService = Provider.of<ChatService>(
                context,
                listen: false,
              );
              if (touched.contains(chatService.currentSessionId)) {
                await chatService.refreshChatWorlds();
              }
            }
          } catch (_) {
            // Repository/ChatService not in this context — the chat picks the
            // world up on its next open regardless.
          }
        }
      }

      if (widget.onSaved != null) {
        await widget.onSaved!(widget.character);
      }

      if (mounted) {
        // Continue mode (e.g. the Stoop update flow): return the saved card so
        // the caller can proceed, instead of the standard "updated" toast + pop.
        if (widget.popWithCardOnSave) {
          Navigator.pop(context, widget.character);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: AppColors.textPrimary(context),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text('Character updated successfully!'),
                ],
              ),
              backgroundColor: AppColors.cardOf(context),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating character: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
