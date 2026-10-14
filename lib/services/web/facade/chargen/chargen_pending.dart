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
  final recipe = readGreetingRecipe(card) ?? const GreetingRecipe();
  final voice = readNarrativeVoice(card);
  final inputs =
      create.inputsFor(id) ??
      GenRunInputs(
        name: card.name,
        concept: card.description,
        sex: voice.sex,
        narrativePerspective: voice.perspective,
        narrativeTense: voice.tense,
        greetingLength: recipe.greetingLength,
        greetingTones: recipe.tones,
        characterContext: recipe.characterContext,
        worldLore: recipe.worldLore,
        nsfwEnabled: recipe.nsfwEnabled,
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
