// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_create.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_jobs.dart';

/// A create stopped after the profile, waiting for the phone's Next.
class PendingProfile {
  PendingProfile(this.run, this.extras, this.mode);

  final GenPausedRun run;

  /// What the save needs that the generator does not (persona birthday and
  /// picture).
  final Map<String, dynamic> extras;

  /// The wizard mode it was asked in (`quick`, `guided`, `automated`).
  final String mode;

  PendingProfile withRun(GenPausedRun next) =>
      PendingProfile(next, extras, mode);

  Map<String, dynamic> toJson() => {
    'run': run.toJson(),
    'extras': extras,
    'mode': mode,
  };

  static PendingProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final run = j['run'];
    final parsed = run is Map
        ? GenPausedRun.fromJson(Map<String, dynamic>.from(run))
        : null;
    if (parsed == null) return null;
    final extras = j['extras'];
    return PendingProfile(
      parsed,
      extras is Map ? Map<String, dynamic>.from(extras) : {},
      j['mode']?.toString() ?? 'quick',
    );
  }
}

/// The pending run on the record a reload will look at: a file under the
/// library root, read once at the first ask; [value] is the cache.
class PendingProfileStore {
  PendingProfileStore(this._storage);

  final StorageService? _storage;
  PendingProfile? value;
  bool _loaded = false;

  File? get _file {
    final root = _storage?.rootPath;
    if (root == null || root.isEmpty) return null;
    return File(p.join(root, 'chargen', 'pending_profile.json'));
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final f = _file;
    if (f == null || !await f.exists()) return;
    try {
      value ??= PendingProfile.fromJson(jsonDecode(await f.readAsString()));
    } catch (e) {
      debugPrint('[chargen] the pending profile could not be read: $e');
    }
  }

  /// Drop the waiting run, file and all: a new create replaces it. The
  /// cache is cleared at once and the file is never read back after this.
  Future<void> discard() {
    _loaded = true;
    value = null;
    return save();
  }

  /// Write [value], or remove the file when there is none.
  Future<void> save() async {
    final f = _file;
    if (f == null) return;
    try {
      final v = value;
      if (v == null) {
        if (await f.exists()) await f.delete();
        return;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(v.toJson()));
    } catch (e) {
      debugPrint('[chargen] the pending profile could not be written: $e');
    }
  }
}

/// Next on a saved character's Profile step: [run]'s texts and the
/// author's [facts] onto the live card, saved the way the other relay paths
/// save it (change the live card, then the shared update).
Future<Map<String, dynamic>> saveProfileToCard(
  CharacterFacade characters,
  String id,
  GenPausedRun run,
  IdentityFacts? facts,
) async {
  final card = characters.cardByDbId(id);
  if (card == null) return chargenRefuse(404, 'character not found');
  card
    ..description = run.card.description
    ..personality = run.card.personality
    ..scenario = run.card.scenario;
  if (facts != null) {
    writeEditedFacts(card, facts, nsfw: run.inputs.nsfwEnabled);
  }
  final ok = await characters.update(id, const {});
  if (!ok) return chargenRefuse(500, 'The profile could not be saved.');
  return {'ok': true, 'phase': 'saved'};
}

/// What the Profile step shows for [run] (`chargen_profile`, the GET):
/// the texts, the facts, the interview and its question count, and the
/// switches the step reads (mode, the user's own scenario, 18+, age).
Map<String, dynamic> profileViewOf(
  GenPausedRun run, {
  required String mode,
  String? characterId,
}) => {
  'characterId': ?characterId,
  'name': run.card.name.isEmpty ? run.inputs.name : run.card.name,
  'description': run.card.description,
  'personality': run.card.personality,
  'scenario': run.card.scenario,
  'facts': (run.facts ?? identityFactsOfCard(run.card)).toJson(),
  'transcriptQuestions': RegExp(
    r'^Q: ',
    multiLine: true,
  ).allMatches(run.interviewTranscript).length,
  'transcript': run.interviewTranscript,
  'userScenario': run.inputs.userScenario,
  'mode': mode,
  'nsfw': run.inputs.nsfwEnabled,
  'age': run.inputs.age,
};

/// Saved character [id] as a paused run, so the Profile step can rewrite
/// it after the phone went Back from Greetings: a copy of its card, its
/// interview from the greeting recipe, the inputs it was created with when
/// it was created here (else what the card itself says), its facts.
GenPausedRun? savedProfileRun(
  CharacterFacade characters,
  ChargenCreate create,
  String id,
) {
  final card = characters.cardByDbId(id);
  if (card == null) return null;
  final stamped = readGreetingRecipe(card);
  final recipe = stamped ?? const GreetingRecipe();
  final voice = readNarrativeVoice(card);
  final ask = create.loreAskFor(id, card);
  final inputs =
      create.inputsFor(id) ??
      GenRunInputs(
        name: card.name,
        concept: ask.concept,
        loreCategories: ask.loreCategories,
        loreDepth: ask.loreDepth,
        sex: voice.sex,
        narrativePerspective: voice.perspective,
        narrativeTense: voice.tense,
        greetingLength: recipe.greetingLength,
        greetingTones: recipe.tones,
        characterContext: recipe.characterContext,
        worldLore: recipe.worldLore,
        // Unknown (no stamp) counts as on, so a re-read never clears
        // intimate preferences the card already has.
        nsfwEnabled: stamped?.nsfwEnabled ?? true,
        reasoningEnabled: recipe.reasoningEnabled,
        includeDynamicMacros: recipe.includeDynamicMacros,
      );
  final CharacterCard copy = GenPausedRun.copyCard(card.toJson()) ?? card;
  return GenPausedRun(
    inputs: inputs,
    card: copy,
    interviewTranscript: recipe.interviewTranscript,
    facts: identityFactsOfCard(card),
  );
}
