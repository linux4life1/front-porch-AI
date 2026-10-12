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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_character_page/create_character_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/providers/app_state.dart';

/// Manual character creator — 7-step wizard.
///
/// Step 0: Identity (name, tags)
/// Step 1: Personality (description, personality, scenario, advanced prompts)
/// Step 2: Dialogue (first message, alt greetings, example dialogues)
/// Step 3: Lorebook (CRUD)
/// Step 4: Porch Life + Realism Engine (wardrobe, time, chaos, engine seeds)
/// Step 5: Review & Create (the card is SAVED advancing out of here)
/// Step 6: Portrait & Avatars — the shared AvatarGenerationPanel (phase #12);
///         post-save by design, so a failed generation can't lose the writing.
class CreateCharacterPage extends StatefulWidget {
  const CreateCharacterPage({super.key});

  @override
  State<CreateCharacterPage> createState() => _CreateCharacterPageState();
}

class _CreateCharacterPageState extends State<CreateCharacterPage> {
  int _currentStep = 0;

  /// Every field the steps write; disposed with this State.
  final _draft = CreateCharacterDraft();

  // ── Portrait & Avatars (Step 6) ──
  /// The persisted card, set when Review's "Create Character" advances into
  /// the final step. The panel needs a saved card before any image lands.
  CharacterCard? _savedCard;

  /// The panel is mid-generation — Done is locked so leaving can't silently
  /// drop work the engine is still finishing.
  bool _panelBusy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _onDraftChanged() => setState(() {});

  void _goToStep(int step) => setState(() => _currentStep = step);

  /// Review's "Create Character": persist the card (always-embedded V2 PNG —
  /// placeholder image for now, the portrait lands in the next step), then
  /// advance into Portrait & Avatars holding the saved card.
  Future<void> _createAndAdvance() async {
    final name = _draft.nameController.text.trim();
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

    final saver = CreateCharacterSaver(
      repo: Provider.of<CharacterRepository>(context, listen: false),
      storage: Provider.of<StorageService>(context, listen: false),
    );

    try {
      final card = await saver.save(_draft, name);
      if (mounted) {
        setState(() {
          // p12 flow: advance to the Portrait & Avatars step (6) instead of
          // resetting to step 0 — the wizard continues to the avatar panel
          // and then closes, so there is nothing to reset in this path.
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(characterCreatedSnackBar(context, name));
    // CreateCharacterPage lives as a tab in MainLayout (not pushed as a
    // route), so Navigator.pop() would pop the entire scaffold → black
    // screen. Instead navigate back to the home tab and reset the form.
    Provider.of<AppState>(context, listen: false).setIndex(0);
    setState(() {
      _currentStep = 0;
      _savedCard = null;
      _panelBusy = false;
      _draft.reset();
    });
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return CreatorIdentityStep(
          key: const ValueKey('identity'),
          draft: _draft,
          onChanged: _onDraftChanged,
          onGoToStep: _goToStep,
        );
      case 1:
        return CreatorPersonalityStep(
          key: const ValueKey('personality'),
          draft: _draft,
          onGoToStep: _goToStep,
        );
      case 2:
        return CreatorDialogueStep(
          key: const ValueKey('dialogue'),
          draft: _draft,
          onChanged: _onDraftChanged,
          onGoToStep: _goToStep,
        );
      case 3:
        return CreatorLorebookStep(
          key: const ValueKey('lorebook'),
          draft: _draft,
          onChanged: _onDraftChanged,
          onGoToStep: _goToStep,
        );
      case 4:
        return CreatorRealismStep(
          key: const ValueKey('realism'),
          draft: _draft,
          onChanged: _onDraftChanged,
          onGoToStep: _goToStep,
        );
      case 5:
        return CreatorReviewStep(
          key: const ValueKey('review'),
          draft: _draft,
          onChanged: _onDraftChanged,
          onCreate: _createAndAdvance,
          onBackToEdit: () => _goToStep(0),
        );
    }
    final card = _savedCard;
    if (card == null) return const SizedBox.shrink(); // unreachable guard
    return CreatorPortraitStep(
      key: const ValueKey('portrait-avatars'),
      card: card,
      description: _draft.descriptionController.text,
      panelBusy: _panelBusy,
      onBusyChanged: (busy) {
        if (mounted) setState(() => _panelBusy = busy);
      },
      onDone: _finishAndClose,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              Provider.of<AppState>(context, listen: false).setIndex(0),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.person_add,
              color: AppColors.formMasterAccent,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('Create Character'),
            const Spacer(),
            CreatorStepIndicator(currentStep: _currentStep),
          ],
        ),
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStep(),
          ),
          // Floating token counter
          Positioned(
            right: 24,
            bottom: 24,
            child: ValueListenableBuilder<int>(
              valueListenable: _draft.tokenNotifier,
              builder: (context, tokens, child) =>
                  CreatorTokenBadge(estimatedTokens: tokens),
            ),
          ),
        ],
      ),
    );
  }
}
