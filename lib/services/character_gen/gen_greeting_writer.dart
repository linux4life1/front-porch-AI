// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_parsing.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/character_gen/gen_stages.dart';
import 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

/// One greeting at a time, for the creator's Greetings step.
class GenGreetingWriter {
  GenGreetingWriter(this._s);

  final GenStages _s;
  GenRunState get _state => _s.state;

  /// Write greeting [index] of [card] again. 0 is the first message, 1 and up
  /// are the alternates in order, and `alternateGreetings.length + 1` writes
  /// a new alternate. [direction] is the author's one-line steer; empty
  /// writes it as creation did. Same prompt, voice and clean-up as creation,
  /// from the card's current text. [card] is only read.
  ///
  /// Returns the new text with the name turned into `{{char}}`, or null
  /// when stopped (an abort) or when the model gave nothing.
  Future<String?> regenerateGreeting({
    required CharacterCard card,
    required int index,
    required String direction,
    required GreetingRecipe recipe,
    required bool abortInFlight,
    required void Function(String accumulated)? onProgress,
  }) async {
    final alts = card.alternateGreetings;
    RangeError.checkValueInInterval(index, 0, alts.length + 1, 'index');
    final epoch = _beginSingleRun(card, recipe, abortInFlight);
    final name = card.name;
    String expand(String s) => s.replaceAll('{{char}}', name);

    // The first message is written from the card's scenario with nothing to
    // avoid, as at creation. An alternate must differ from every other one.
    final others = index == 0
        ? <String>[]
        : [
            card.firstMessage,
            for (var i = 0; i < alts.length; i++)
              if (i != index - 1) alts[i],
          ].where((g) => g.trim().isNotEmpty).toList();

    final prompt = _s.greetingPrompt(
      name: name,
      description: expand(card.description),
      personality: expand(card.personality),
      scenario: expand(card.scenario),
      length: recipe.greetingLength,
      tone: recipe.toneFor(index),
      previousGreetings: others,
      characterContext: recipe.characterContext,
      userPersonaContext: recipe.userPersonaContext,
      interviewTranscript: recipe.interviewTranscript,
      worldLore: recipe.worldLore,
      direction: direction,
    );
    final out = await _s.llm.call(
      prompt,
      maxLen: 4096,
      minLen: 512,
      onProgress: onProgress,
    );
    if (_state.isStale(epoch)) return null;
    if (out == null) return null;
    final text = applyCharMacro(
      cleanGeneratedGreeting(stripThinkBlocks(out)),
      name,
    );
    return text.trim().isEmpty ? null : text;
  }

  /// Read again what [card]'s first message shows the character wearing and
  /// carrying: the Porch Life pass creation runs once the first message
  /// exists. Null when stopped, or when the model named nothing to wear or
  /// carry (the caller then keeps the outfit it has).
  Future<PorchLifeIdentity?> rereadOpeningWardrobe({
    required CharacterCard card,
    required GreetingRecipe recipe,
    required bool abortInFlight,
  }) async {
    final epoch = _beginSingleRun(card, recipe, abortInFlight);
    final name = card.name;
    String expand(String s) => s.replaceAll('{{char}}', name);
    final identity = await _s.porchLife.readIdentity(
      card: CharacterCard(
        name: name,
        description: expand(card.description),
        personality: expand(card.personality),
        firstMessage: expand(card.firstMessage),
      ),
      name: name,
      interviewTranscript: recipe.interviewTranscript,
      nsfwEnabled: recipe.nsfwEnabled,
    );
    if (_state.isStale(epoch)) return null;
    if (identity == null) return null;
    if (identity.worn.isEmpty && identity.carrying.isEmpty) return null;
    return identity;
  }

  int _beginSingleRun(
    CharacterCard card,
    GreetingRecipe recipe,
    bool abortInFlight,
  ) => _s.beginCardRun(card, recipe, abortInFlight: abortInFlight);
}
