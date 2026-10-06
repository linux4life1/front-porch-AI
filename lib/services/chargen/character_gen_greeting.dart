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

part of '../character_gen_service.dart';

/// The most alternate greetings the creator writes or lets you add, on the
/// desktop and through the web relay alike.
const kMaxAlternateGreetings = 5;

/// How a creation run wrote its greetings, kept so the creator's Greetings
/// step (desktop and web) can write one more greeting the same way.
/// The default is a card nobody recorded: medium length, a neutral tone and
/// no extra context.
class GreetingRecipe {
  const GreetingRecipe({
    this.greetingLength = 'Medium (2-4 paragraphs)',
    this.tones = const ['Neutral'],
    this.characterContext = '',
    this.userPersonaContext = '',
    this.interviewTranscript = '',
    this.worldLore,
    this.includeDynamicMacros = false,
    this.reasoningEnabled = false,
    this.nsfwEnabled = false,
  });

  final String greetingLength;
  final List<String> tones;
  final String characterContext;
  final String userPersonaContext;
  final String interviewTranscript;
  final String? worldLore;
  final bool includeDynamicMacros;
  final bool reasoningEnabled;
  final bool nsfwEnabled;

  /// The tone creation gave greeting [index] (0 = the first message): the
  /// first tone, then round the list for the alternates.
  String toneFor(int index) =>
      tones.isEmpty ? 'Neutral' : tones[index % tones.length];
}

/// One greeting at a time, for the creator's Greetings step.
extension GenGreeting on CharacterGenService {
  /// Write greeting [index] of [card] again. 0 is the first message, 1 and up
  /// are the alternates in order, and `alternateGreetings.length + 1` writes
  /// a new alternate. [direction] is the author's one-line steer; empty
  /// writes it as creation did. Same prompt, voice and clean-up as creation,
  /// from the card's current text. [card] is only read.
  ///
  /// Returns the new text with the name turned into `{{char}}`, or null
  /// when stopped ([abort]) or when the model gave nothing.
  Future<String?> regenerateGreeting({
    required CharacterCard card,
    required int index,
    String direction = '',
    GreetingRecipe recipe = const GreetingRecipe(),
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
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

    final prompt = _buildGreetingPrompt(
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
    final out = await _callLLM(
      prompt,
      maxLen: 4096,
      minLen: 512,
      onProgress: onProgress,
    );
    if (_aborted || _generationEpoch != epoch) return null;
    if (out == null) return null;
    final text = applyCharMacro(_cleanGreeting(stripThinkBlocks(out)), name);
    return text.trim().isEmpty ? null : text;
  }

  /// Read again what [card]'s first message shows the character wearing and
  /// carrying: the Porch Life pass creation runs once the first message
  /// exists. Null when stopped, or when the model named nothing to wear or
  /// carry (the caller then keeps the outfit it has).
  Future<PorchLifeIdentity?> rereadOpeningWardrobe({
    required CharacterCard card,
    GreetingRecipe recipe = const GreetingRecipe(),
    bool abortInFlight = true,
  }) async {
    final epoch = _beginSingleRun(card, recipe, abortInFlight);
    final name = card.name;
    String expand(String s) => s.replaceAll('{{char}}', name);
    final identity = await _readPorchLifeIdentity(
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
    if (_aborted || _generationEpoch != epoch) return null;
    if (identity == null) return null;
    if (identity.worn.isEmpty && identity.carrying.isEmpty) return null;
    return identity;
  }

  /// Start a one-call run the way [GenGenerate.generateCharacter] starts a
  /// whole one: the card's stamped voice, a fresh epoch for [abort].
  int _beginSingleRun(
    CharacterCard card,
    GreetingRecipe recipe,
    bool abortInFlight,
  ) {
    final voice = readNarrativeVoice(card);
    _narrativeVoice = voice.voice;
    _narrativeSex = voice.sex;
    _generationEpoch++;
    _aborted = false;
    _abortInFlight = abortInFlight;
    if (abortInFlight) _llmService.abortGeneration();
    _reasoningEnabled = recipe.reasoningEnabled;
    _includeDynamicMacros = recipe.includeDynamicMacros;
    return _generationEpoch;
  }
}
