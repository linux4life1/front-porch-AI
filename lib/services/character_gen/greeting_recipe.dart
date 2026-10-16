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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

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
    this.profileFingerprint = '',
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

  /// [profileFingerprintOf] the description and personality these greetings
  /// were written from; '' when unknown (a card stamped before it existed).
  /// A different fingerprint now means the profile changed under them.
  final String profileFingerprint;

  /// This recipe, written from the profile whose fingerprint is [fp]
  /// ("Keep them" re-stamps with the current one).
  GreetingRecipe withProfileFingerprint(String fp) => GreetingRecipe(
    greetingLength: greetingLength,
    tones: tones,
    characterContext: characterContext,
    userPersonaContext: userPersonaContext,
    interviewTranscript: interviewTranscript,
    worldLore: worldLore,
    includeDynamicMacros: includeDynamicMacros,
    reasoningEnabled: reasoningEnabled,
    nsfwEnabled: nsfwEnabled,
    profileFingerprint: fp,
  );

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
      'interview': _cut(interviewTranscript, kInterviewTranscriptCap),
    if ((worldLore ?? '').trim().isNotEmpty)
      'lore': _cut(worldLore!, _stampLoreChars),
    'macros': includeDynamicMacros,
    'reasoning': reasoningEnabled,
    'nsfw': nsfwEnabled,
    if (profileFingerprint.isNotEmpty) 'profile': profileFingerprint,
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
      profileFingerprint: text('profile'),
    );
  }
}

/// Where the recipe sits in the card's extension data, beside the narrative
/// voice's stamp, so a greeting rewritten after a reload or a restart still
/// matches the others.
const kGreetingRecipeExtensionKey = 'greeting_recipe';

/// The interview is kept up to the cap every prompt reads it under
/// ([kInterviewTranscriptCap]); lore past 8,000 would weigh down every
/// export of the card.
const _stampLoreChars = 8000;
const _stampContextChars = 4000;

String _cut(String s, int max) => s.length > max ? s.substring(0, max) : s;

/// A fingerprint of a profile's [description] and [personality], the same
/// whether the character's [name] is written out or as `{{char}}`.
String profileFingerprintOf(
  String description,
  String personality, {
  String name = '',
}) {
  String norm(String s) => applyCharMacro(s, name).trim();
  return sha1
      .convert(utf8.encode(jsonEncode([norm(description), norm(personality)])))
      .toString();
}

/// Write [recipe] onto [card], as [stampNarrativeVoice] writes the voice.
void stampGreetingRecipe(CharacterCard card, GreetingRecipe recipe) {
  final raw = Map<String, dynamic>.from(card.rawExtensions ?? {});
  raw[kGreetingRecipeExtensionKey] = recipe.toStamp();
  card.rawExtensions = raw;
}

/// The recipe [card] was created with, or null when it carries none.
GreetingRecipe? readGreetingRecipe(CharacterCard? card) =>
    GreetingRecipe.fromStamp(card?.rawExtensions?[kGreetingRecipeExtensionKey]);
