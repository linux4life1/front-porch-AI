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

import 'package:front_porch_ai/models/models.dart';

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

  /// What [stampGreetingRecipe] writes on the card. Not the user's persona:
  /// a card travels, and the persona is the user's. Long texts are cut to
  /// what the prompts read (the interview) or to a size an export can carry
  /// (the lore).
  Map<String, dynamic> toStamp() => {
    'length': greetingLength,
    'tones': tones,
    if (characterContext.isNotEmpty)
      'context': _cut(characterContext, _stampContextChars),
    if (interviewTranscript.isNotEmpty)
      'interview': _cut(interviewTranscript, _stampInterviewChars),
    if ((worldLore ?? '').trim().isNotEmpty)
      'lore': _cut(worldLore!, _stampLoreChars),
    'macros': includeDynamicMacros,
    'reasoning': reasoningEnabled,
    'nsfw': nsfwEnabled,
  };

  /// A stamp read back; null when [raw] is not one. Odd values fall back to
  /// the defaults rather than failing (the card may come from anywhere).
  static GreetingRecipe? fromStamp(Object? raw) {
    if (raw is! Map) return null;
    String text(String key) => raw[key] is String ? raw[key] as String : '';
    final tones = [
      if (raw['tones'] is List)
        for (final t in raw['tones'] as List)
          if (t is String && t.trim().isNotEmpty) t,
    ];
    final length = text('length');
    final lore = text('lore');
    return GreetingRecipe(
      greetingLength: length.isEmpty ? 'Medium (2-4 paragraphs)' : length,
      tones: tones.isEmpty ? const ['Neutral'] : tones,
      characterContext: text('context'),
      interviewTranscript: text('interview'),
      worldLore: lore.trim().isEmpty ? null : lore,
      includeDynamicMacros: raw['macros'] == true,
      reasoningEnabled: raw['reasoning'] == true,
      nsfwEnabled: raw['nsfw'] == true,
    );
  }
}

/// Where the recipe sits in the card's extension data, beside the narrative
/// voice's stamp, so a greeting rewritten after a reload or a restart still
/// matches the others.
const kGreetingRecipeExtensionKey = 'greeting_recipe';

/// The prompts read the interview's first 1,400 characters at most; lore
/// past 8,000 would weigh down every export of the card.
const _stampInterviewChars = 1400;
const _stampLoreChars = 8000;
const _stampContextChars = 4000;

String _cut(String s, int max) => s.length > max ? s.substring(0, max) : s;

/// Write [recipe] onto [card], as [stampNarrativeVoice] writes the voice.
void stampGreetingRecipe(CharacterCard card, GreetingRecipe recipe) {
  final raw = Map<String, dynamic>.from(card.rawExtensions ?? {});
  raw[kGreetingRecipeExtensionKey] = recipe.toStamp();
  card.rawExtensions = raw;
}

/// The recipe [card] was created with, or null when it carries none.
GreetingRecipe? readGreetingRecipe(CharacterCard? card) =>
    GreetingRecipe.fromStamp(card?.rawExtensions?[kGreetingRecipeExtensionKey]);
