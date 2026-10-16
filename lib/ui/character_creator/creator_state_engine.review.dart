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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_profile.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

/// The Review step's two rewrites (#530): the example dialogue and the
/// lorebook, each steered by its own line of direction. Each runs on its
/// own service and lands only if it is still the live run; Stop keeps the
/// text the card had. An entry edited by hand survives a lorebook rewrite
/// (the engine's `isHandEdited`), and keeps its Review checkbox.
class CreatorReviewRewriter {
  final CreatorState state;

  CreatorReviewRewriter(this.state);

  /// New example dialogue into the Example Dialogue box when it is done.
  Future<void> regenerateExampleDialogue({
    required LLMProvider llmProvider,
  }) async {
    const kind = ReviewRewrite.dialogue;
    final r = state.review;
    final gen = _start(llmProvider, kind);
    if (gen == null) return;
    String? text;
    try {
      text = await gen.regenerateExampleDialogue(
        card: _cardNow(),
        recipe: state.greetings.recipe,
        direction: r.dialogueSteer.text.trim(),
        onProgress: (s) {
          if (!identical(r.runOf(kind), gen)) return;
          r.dialogueText = s;
          state.notify();
        },
      );
    } catch (e) {
      debugPrint('CharacterCreator: example dialogue failed: $e');
    }
    if (!r.finish(kind, gen)) return; // stopped, or the wizard reset
    if (text == null) {
      r.setError(kind, _nothingBack);
    } else {
      state.exampleDialogueController.text = text;
    }
    state.notify();
  }

  /// A new lorebook in place of the generated entries; entries edited by
  /// hand stay where they are, checked or not as they were.
  Future<void> rewriteLorebook({required LLMProvider llmProvider}) async {
    const kind = ReviewRewrite.lorebook;
    final r = state.review;
    final card = state.generatedCard;
    if (card == null) return;
    final gen = _start(llmProvider, kind);
    if (gen == null) return;
    final before = card.lorebook;
    final inputs = state.profile.paused?.inputs;
    Lorebook? book;
    try {
      book = await gen.rewriteLorebook(
        card: _cardNow(),
        concept: inputs?.concept ?? card.description,
        recipe: state.greetings.recipe,
        loreCategories: inputs?.loreCategories ?? const [],
        loreDepth: inputs?.loreDepth ?? 'Standard',
        direction: r.loreSteer.text.trim(),
      );
    } catch (e) {
      debugPrint('CharacterCreator: lorebook rewrite failed: $e');
    }
    if (!r.finish(kind, gen)) return;
    if (book == null) {
      r.setError(kind, _nothingBack);
    } else {
      final flags = state.lorebookEntryEnabled;
      final old = before?.entries ?? const <LorebookEntry>[];
      state.lorebookEntryEnabled = {
        for (var i = 0; i < book.entries.length; i++)
          i: _flagOf(book.entries[i], old, flags),
      };
      card.lorebook = book;
    }
    state.notify();
  }

  /// Stop [kind]'s rewrite; its card keeps what it had.
  void stop(ReviewRewrite kind) {
    state.review.stop(kind);
    state.notify();
  }

  /// A kept entry keeps its checkbox; a new one starts checked.
  bool _flagOf(
    LorebookEntry entry,
    List<LorebookEntry> old,
    Map<int, bool> flags,
  ) {
    final i = old.indexWhere((e) => identical(e, entry));
    return i < 0 ? true : (flags[i] ?? true);
  }

  CharacterGenService? _start(LLMProvider llmProvider, ReviewRewrite kind) {
    final r = state.review;
    if (r.writing(kind) || state.generatedCard == null) return null;
    final llm = llmProvider.serviceForModel(state.selectedModelId);
    if (llm == null) {
      r.setError(
        kind,
        llmProvider.hasManagedProcess
            ? 'The backend is not running. Start it, then try again.'
            : 'No model is ready. Pick or connect one in Setup, then try '
                  'again.',
      );
      state.notify();
      return null;
    }
    final gen = state.newGenService(llm);
    r.start(kind, gen);
    state.notify();
    return gen;
  }

  /// The card as the wizard holds it now; the lorebook is the card's own
  /// (its entries carry the fingerprints that say which were hand-edited).
  CharacterCard _cardNow() {
    final base = state.generatedCard!;
    return CharacterCard(
      name: base.name,
      description: state.descController.text,
      personality: state.personalityController.text,
      scenario: state.scenarioController.text,
      firstMessage: state.firstMessageController.text,
      mesExample: state.exampleDialogueController.text,
      alternateGreetings: [
        for (final c in state.altGreetingControllers) c.text,
      ],
      lorebook: base.lorebook,
      rawExtensions: base.rawExtensions,
    );
  }

  static const _nothingBack =
      'Nothing came back from the model, so this was left as it was. '
      'Check that your model is running, then try again.';
}
