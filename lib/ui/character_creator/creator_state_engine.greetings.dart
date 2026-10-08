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

part of 'creator_state_engine.dart';

/// The Greetings step's actions (#370): rewrite one greeting (optionally
/// steered), add one, delete an alternate, stop the one being written, and
/// re-read the outfit after a new first message. One write at a time; the
/// box keeps its old text until the new one is in, so Stop has nothing to
/// undo. The web relay calls the same [GenGreeting] service functions.
extension CreatorGreetingEngine on CreatorState {
  /// Rewrite greeting [index] (0 = the first message, 1 and up = the
  /// alternates), steered by that greeting's steer box when it has text.
  Future<void> regenerateGreeting({
    required LLMProvider llmProvider,
    required int index,
  }) {
    final box = index == 0 ? firstMessageController : _altBox(index);
    if (box == null) return Future.value();
    return _writeGreeting(
      llmProvider,
      index,
      direction: greetings.steerFor(box).text,
    );
  }

  /// Write a new alternate right away, up to [CreatorGreetings.maxAlternates].
  Future<void> addGreeting({required LLMProvider llmProvider}) {
    if (altGreetingControllers.length >= CreatorGreetings.maxAlternates) {
      return Future.value();
    }
    return _writeGreeting(llmProvider, altGreetingControllers.length + 1);
  }

  /// Delete alternate [index] (1 and up, as above) with its starting state.
  /// The first message cannot be deleted.
  void deleteAlternate(int index) {
    final box = _altBox(index);
    if (box == null || greetings.busy) return;
    greetingSeeds = alignGreetingSeeds(
      greetingSeeds,
      altGreetingControllers.length,
    )..removeAt(index - 1);
    altGreetingControllers = [...altGreetingControllers]..removeAt(index - 1);
    greetings.forgetSteer(box);
    if (greetings.errorIndex != null) greetings.clearError();
    notify();
    // Its box can still be on screen this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => box.dispose());
  }

  /// Stop the greeting being written. Its box never changed, so the old
  /// text is simply still there; a greeting being added just goes away.
  void stopGreeting() {
    final gen = greetings.activeGen;
    if (gen == null) return;
    gen.abort();
    greetings
      ..activeGen = null
      ..writingIndex = null
      ..writingText = '';
    notify();
  }

  /// Fill the Realism step's outfit (Wearing / Carrying) from the current
  /// first message, with the extraction creation used. On no answer the
  /// outfit is left as it was and the hint says so.
  Future<void> rereadOutfit({required LLMProvider llmProvider}) async {
    final g = greetings;
    if (g.busy || generatedCard == null) return;
    final llm = llmProvider.serviceForModel(selectedModelId);
    if (llm == null) {
      g.outfitError = _noModel(llmProvider);
      notify();
      return;
    }
    final gen = CharacterGenService(llm);
    g
      ..rereadingOutfit = true
      ..outfitGen = gen
      ..outfitError = null;
    notify();
    final card = _greetingCard();
    final read = await gen
        .rereadOpeningWardrobe(card: card, recipe: g.recipe)
        .catchError((Object e) {
          debugPrint('CharacterCreator: outfit re-read failed: $e');
          return null;
        });
    if (!identical(g.outfitGen, gen)) return; // the wizard moved on
    g
      ..outfitGen = null
      ..rereadingOutfit = false;
    if (read == null) {
      g.outfitError =
          'The outfit could not be read from the new first message. '
          'Nothing was changed. Try again, or edit it below.';
    } else {
      realismWorn = read.worn;
      realismCarrying = read.carrying;
      g.outfitReadFrom = card.firstMessage;
    }
    notify();
  }

  /// "Keep this outfit": the outfit stays and now stands for the first
  /// message as it reads today, so the hint goes until that changes again.
  void keepOutfit() {
    greetings
      ..outfitReadFrom = firstMessageController.text
      ..outfitError = null;
    notify();
  }

  Future<void> _writeGreeting(
    LLMProvider llmProvider,
    int index, {
    String direction = '',
  }) async {
    final g = greetings;
    if (g.busy || generatedCard == null) return;
    final llm = llmProvider.serviceForModel(selectedModelId);
    if (llm == null) {
      g.setError(index, _noModel(llmProvider));
      notify();
      return;
    }
    final gen = CharacterGenService(llm);
    g
      ..clearError()
      ..writingIndex = index
      ..writingText = ''
      ..activeGen = gen;
    notify();
    String? text;
    try {
      text = await gen.regenerateGreeting(
        card: _greetingCard(),
        index: index,
        direction: direction,
        recipe: g.recipe,
        onProgress: (s) {
          if (!identical(g.activeGen, gen)) return;
          g.writingText = s;
          notify();
        },
      );
    } catch (e) {
      debugPrint('CharacterCreator: greeting $index failed: $e');
    }
    if (!identical(g.activeGen, gen)) return; // stopped, or the wizard reset
    g
      ..activeGen = null
      ..writingIndex = null
      ..writingText = '';
    if (text == null) {
      g.setError(
        index,
        'Nothing came back from the model, so this greeting was left as it '
        'was. Check that your model is running, then try again.',
      );
    } else if (index == 0) {
      // The outfit was read from the old words; Realism sees the difference
      // (CreatorGreetings.firstMessageChangedFrom) and offers a re-read.
      firstMessageController.text = text;
    } else if (index <= altGreetingControllers.length) {
      altGreetingControllers[index - 1].text = text;
    } else {
      altGreetingControllers = [
        ...altGreetingControllers,
        newGreetingBox(text),
      ];
      greetingSeeds = alignGreetingSeeds(
        greetingSeeds,
        altGreetingControllers.length,
      );
    }
    notify();
  }

  /// The card as the wizard holds it right now: the generated card with
  /// every box's current text, so a rewrite follows the user's edits.
  CharacterCard _greetingCard() {
    final base = generatedCard!;
    return CharacterCard(
      name: base.name,
      description: descController.text,
      personality: personalityController.text,
      scenario: scenarioController.text,
      firstMessage: firstMessageController.text,
      alternateGreetings: [for (final c in altGreetingControllers) c.text],
      rawExtensions: base.rawExtensions,
    );
  }

  TextEditingController? _altBox(int index) =>
      index >= 1 && index <= altGreetingControllers.length
      ? altGreetingControllers[index - 1]
      : null;

  String _noModel(LLMProvider llmProvider) => llmProvider.hasManagedProcess
      ? 'The backend is not running. Start it, then try again.'
      : 'No model is ready. Pick or connect one in Setup, then try again.';
}
