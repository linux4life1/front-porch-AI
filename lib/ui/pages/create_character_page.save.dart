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
// Manual creator: persisting the card (Review's "Create Character")
// and the final "Done" reset.
// Extracted verbatim from create_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so privates and the mandatory
// step-indicator wizard flow are unchanged.

part of 'create_character_page.dart';

extension _CreateCharacterSave on _CreateCharacterPageState {
  // ═══════════════════════════════════════════════════════════════
  //  SAVE
  // ═══════════════════════════════════════════════════════════════

  /// Review's "Create Character": persist the card (always-embedded V2 PNG —
  /// placeholder image for now, the portrait lands in the next step), then
  /// advance into Portrait & Avatars holding the saved card.
  Future<void> _createAndAdvance() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Character name is required'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    try {
      // Always build extensions — even when realism is disabled — so that
      // any configured values survive a round-trip through PNG save/load.
      // The realismEnabled flag controls whether the engine *uses* them at
      // runtime, not whether they are persisted.
      final fpExt = FrontPorchExtensions(
        realismEnabled: _realismEnabled,
        shortTermBond: _realismShortTermBond,
        longTermBond: _realismLongTermBond,
        trustLevel: _realismTrustLevel,
        dayCount: _realismDayCount,
        timeOfDay: _realismTimeOfDay,
        storyStartDate: _realismStoryStartDate,
        storyStartTime: _realismStoryStartTime,
        characterEmotion: _realismEmotion,
        emotionIntensity: _realismEmotionIntensity,
        nsfwCooldownEnabled: _realismNsfwCooldown,
        passageOfTimeEnabled: true, // default on; user can toggle later
        chaosModeEnabled: _realismChaosMode,
        needsSimEnabled: _realismNeedsSim,
        enjoysLowHygiene: _realismEnjoysLowHygiene,
        ambitions: _realismAmbitions,
        planLines: _realismPlanLines,
        likes: _realismLikes,
        dislikes: _realismDislikes,
        intimateInto: _realismIntimateInto,
        intimateNotInto: _realismIntimateNotInto,
        // Through the shared normalizer, so a wardrobe typed here and the same
        // wardrobe typed in the edit page land on the card identically. The
        // neighbouring lists deliberately stay raw and are tidied at parse
        // time; wardrobe cannot, because splitting `name (state)` apart is not
        // something the card parser can do after the fact.
        inventory: Pockets.cardJsonFrom(
          worn: _realismWorn,
          carrying: _realismCarrying,
        ),
        realismVerificationEnabled: _realismVerificationEnabled,
        realismVerificationMaxReprocesses: _realismVerificationMaxReprocesses,
        realismVerificationStrictness: _realismVerificationStrictness,
        realismNeedsDirectorAuthority: _realismNeedsDirectorAuthority,
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

      fpExt.ensureStableId();

      final card = CharacterCard(
        name: name,
        description: _descriptionController.text,
        personality: _personalityController.text,
        scenario: _scenarioController.text,
        firstMessage: _firstMessageController.text,
        mesExample: _exampleDialogueController.text,
        systemPrompt: _systemPromptController.text,
        postHistoryInstructions: _postHistoryController.text,
        alternateGreetings: _altGreetingControllers
            .map((c) => c.text)
            .where((t) => t.trim().isNotEmpty)
            .toList(),
        tags: List.from(_tags),
        lorebook: _lorebookEntries.isNotEmpty
            ? Lorebook(entries: List.from(_lorebookEntries))
            : null,
        frontPorchExtensions: fpExt,
      );

      // Determine PNG path — always write a PNG so card data (including
      // Realism Engine extensions) can be embedded and survive app restarts.
      // Placeholder image for now: the Portrait & Avatars step overwrites the
      // pixels in place (same basename — folders key members on it).
      final charDir = storage.charactersDir;
      if (!charDir.existsSync()) charDir.createSync(recursive: true);
      final epoch = DateTime.now().millisecondsSinceEpoch;
      final safeName = name
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
      card.imagePath = imagePath;
      final v2Service = V2CardService();
      await v2Service.saveCardAsPng(card, imagePath, null);
      debugPrint(
        '[CreateCharacter] Saved PNG with extensions: '
        'realism=${fpExt.realismEnabled}, bond=${fpExt.shortTermBond}, '
        'trust=${fpExt.trustLevel}, emotion=${fpExt.characterEmotion}',
      );

      // Add to repository
      await repo.addCharacter(card);

      if (mounted) {
        rebuildState(() {
          // p12 flow: advance to the Portrait & Avatars step (6) instead of
          // resetting to step 0. The old reset block (including Rawhide's
          // _realismStoryStartDate/_realismStoryStartTime resets) is obsolete
          // here — the wizard continues to the avatar panel and then closes, so
          // there is nothing to reset for a fresh start in this path.
          _savedCard = card;
          _currentStep = 6;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save character: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Final step's "Done": back to home and reset the wizard for a fresh run.
  void _finishAndClose() {
    final name = _savedCard?.name ?? 'Character';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.logReady, size: 20),
            const SizedBox(width: 8),
            Text('$name created successfully!'),
          ],
        ),
        backgroundColor: AppColors.surfaceContainerOf(context),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // CreateCharacterPage lives as a tab in MainLayout (not pushed as a
    // route), so Navigator.pop() would pop the entire scaffold → black
    // screen. Instead navigate back to the home tab and reset the form.
    Provider.of<AppState>(context, listen: false).setIndex(0);
    rebuildState(() {
      _currentStep = 0;
      _savedCard = null;
      _panelBusy = false;
      _nameController.clear();
      _descriptionController.clear();
      _personalityController.clear();
      _scenarioController.clear();
      _firstMessageController.clear();
      _exampleDialogueController.clear();
      _systemPromptController.clear();
      _postHistoryController.clear();
      for (final c in _altGreetingControllers) {
        c.dispose();
      }
      _altGreetingControllers.clear();
      _lorebookEntries.clear();
      _tags.clear();
      _realismEnabled = false;
      _realismTimeOfDay = 'morning';
      _realismDayCount = 1;
      _realismStoryStartDate = null;
      _realismStoryStartTime = null;
      _realismShortTermBond = 0;
      _realismLongTermBond = 0;
      _realismTrustLevel = 0;
      _realismEmotion = '';
      _realismEmotionIntensity = 'mild';
      _realismNsfwCooldown = false;
      _realismChaosMode = false;
      _realismNeedsSim = true;
      _realismEnjoysLowHygiene = false;
      _realismAmbitions = const [];
      _realismPlanLines = const [];
      _realismLikes = const [];
      _realismDislikes = const [];
      _realismIntimateInto = const [];
      _realismIntimateNotInto = const [];
      _realismWorn = const [];
      _realismCarrying = const [];
      _realismVerificationEnabled = false;
      _realismVerificationMaxReprocesses = 1;
      _realismVerificationStrictness = 3;
      _realismNeedsDirectorAuthority = false;
      _needsBaselineHunger = 80;
      _needsBaselineBladder = 80;
      _needsBaselineEnergy = 80;
      _needsBaselineSocial = 80;
      _needsBaselineFun = 80;
      _needsBaselineHygiene = 80;
      _needsBaselineComfort = 80;
      _needsDecayHunger = 5;
      _needsDecayBladder = 5;
      _needsDecayEnergy = 5;
      _needsDecaySocial = 5;
      _needsDecayFun = 5;
      _needsDecayHygiene = 5;
      _needsDecayComfort = 5;
      _tokenNotifier.value = 0;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════

  Widget _inputLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required)
          const Text(' *', style: TextStyle(color: Colors.redAccent)),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textTertiary(context),
        fontSize: 14,
      ),
      filled: true,
      fillColor: AppColors.surfaceContainerOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.porchAmberOf(context)),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }

  Widget _expandableField(
    String label,
    TextEditingController controller, {
    String hint = '',
    int maxLines = 3,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _inputLabel(label),
            const Spacer(),
            IconButton(
              onPressed: () => showExpandedEditorDialog(
                context: context,
                title: label,
                controller: controller,
              ),
              icon: const Icon(
                Icons.open_in_full,
                size: 16,
                color: Colors.white38,
              ),
              tooltip: 'Expand editor',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
          spellCheckConfiguration: AppTextField.platformSpellCheck(),
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }
}
