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

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// The greeting being written, so Stop reaches that run and no other.
class _GreetingJob {
  _GreetingJob(this.characterId, this.index, this.gen);

  final String characterId;
  final int index;
  final CharacterGenService gen;
}

/// The web twin of the desktop creator's Greetings step (#370): rewrite one
/// greeting of a saved character (optionally steered), add one, delete an
/// alternate, or stop the one being written. The model work is the same
/// [CharacterGenService.regenerateGreeting] the desktop calls. Starting returns at
/// once; the text streams over the hub as `chargen_greeting_progress`, then
/// `chargen_greeting_done` (saved), `_error` or `_stopped`. A greeting is
/// saved only when it is done, so Stop leaves the card as it was.
class ChargenGreetings {
  ChargenGreetings(
    this._llm,
    this._characters,
    this._hub, {
    required String? Function() busyReason,
  }) : _busyReason = busyReason;

  final LLMProvider _llm;
  final CharacterFacade _characters;
  final StreamHub? _hub;

  /// Why another model call must wait (a create, a profile rewrite, a
  /// review rewrite), or null.
  final String? Function() _busyReason;

  /// The one greeting being written, and a cache of how characters created
  /// here wrote their greetings (the card's own stamp is the record).
  _GreetingJob? _greetingJob;
  final Map<String, GreetingRecipe> _recipes = {};

  /// "Rewrite the greetings from it": the character whose greetings are
  /// being written one after another, and the last index to write.
  ({String characterId, int last})? _all;

  /// Whether a greeting, or a run of them, is being written.
  bool get busy => _greetingJob != null || _all != null;

  /// Rewrite greeting `index` (0 = the first message) of `characterId`,
  /// steered by `direction`; with [add], write a new alternate instead.
  /// `{ok: true}`, or `{ok: false, status, error}` to refuse at once.
  Map<String, dynamic> startGreeting(
    Map<String, dynamic> body, {
    bool add = false,
  }) {
    final id = body['characterId']?.toString().trim() ?? '';
    if (id.isEmpty) return _refuse(400, 'characterId is required');
    final card = _characters.cardByDbId(id);
    if (card == null) return _refuse(404, 'character not found');
    final busy = _refuseBusy();
    if (busy != null) return busy;
    final alts = card.alternateGreetings.length;
    final int index;
    if (add) {
      if (alts >= kMaxAlternateGreetings) {
        return _refuse(
          400,
          'This character already has $kMaxAlternateGreetings alternate '
          'greetings, the most it can have.',
        );
      }
      index = alts + 1;
    } else {
      final raw = body['index'];
      index = raw is num ? raw.toInt() : int.tryParse('$raw') ?? -1;
      if (index < 0 || index > alts) {
        return _refuse(400, 'index must be 0 (the first message) to $alts');
      }
    }
    final svc = _llm.activeService;
    if (!svc.isReady) return _refuse(400, 'the LLM backend is not ready');
    _startJob(id, card, index, add ? '' : body['direction']?.toString() ?? '');
    return {'ok': true, 'index': index};
  }

  Map<String, dynamic>? _refuseBusy() {
    if (busy) {
      return _refuse(
        409,
        'A greeting is already being written. Stop it or wait for it.',
      );
    }
    final reason = _busyReason();
    return reason == null ? null : _refuse(409, reason);
  }

  void _startJob(String id, CharacterCard card, int index, String direction) {
    final job = _greetingJob = _GreetingJob(
      id,
      index,
      CharacterGenService(_llm.activeService),
    );
    unawaited(_writeGreeting(job, card, direction));
  }

  /// "Rewrite the greetings from it": write the first message and every
  /// alternate again, one after another, from the profile as it is now.
  /// Stop ends the run (what was written so far stays). When the last one
  /// is done the greetings count as written from this profile.
  Map<String, dynamic> startRewriteAll(Map<String, dynamic> body) {
    final id = body['characterId']?.toString().trim() ?? '';
    if (id.isEmpty) return _refuse(400, 'characterId is required');
    final card = _characters.cardByDbId(id);
    if (card == null) return _refuse(404, 'character not found');
    final busy = _refuseBusy();
    if (busy != null) return busy;
    if (!_llm.activeService.isReady) {
      return _refuse(400, 'the LLM backend is not ready');
    }
    final count = card.alternateGreetings.length + 1;
    _all = (characterId: id, last: count - 1);
    _startJob(id, card, 0, '');
    return {'ok': true, 'count': count};
  }

  /// After greeting [job] was saved: the next one of a rewrite-all, or its
  /// end.
  Future<void> _advanceAll(_GreetingJob job) async {
    final all = _all;
    if (all == null || all.characterId != job.characterId) return;
    final card = _characters.cardByDbId(job.characterId);
    if (card != null && job.index < all.last) {
      return _startJob(job.characterId, card, job.index + 1, '');
    }
    _all = null;
    if (card == null) return;
    await keepProfile(job.characterId);
    _hub?.broadcast({
      'event': 'chargen_greetings_rewritten',
      'characterId': job.characterId,
    });
  }

  /// Whether [characterId]'s profile changed since its greetings were
  /// written: the fingerprint stamped then against the profile now. A card
  /// with no stamp says nothing (false).
  bool profileChanged(String characterId) {
    final card = _characters.cardByDbId(characterId);
    if (card == null) return false;
    final stamp = recipeFor(characterId, card).profileFingerprint;
    if (stamp.isEmpty) return false;
    return stamp !=
        profileFingerprintOf(
          card.description,
          card.personality,
          name: card.name,
        );
  }

  /// "Keep them": the greetings count as written from the profile as it is
  /// now. False when the character is gone or could not be saved.
  Future<bool> keepProfile(String characterId) async {
    final card = _characters.cardByDbId(characterId);
    if (card == null) return false;
    final fp = profileFingerprintOf(
      card.description,
      card.personality,
      name: card.name,
    );
    final stamped = (readGreetingRecipe(card) ?? const GreetingRecipe())
        .withProfileFingerprint(fp);
    stampGreetingRecipe(card, stamped);
    final cached = _recipes[characterId];
    if (cached != null) {
      _recipes[characterId] = cached.withProfileFingerprint(fp);
    }
    return _characters.update(characterId, const {});
  }

  /// Which greeting of [characterId] is being written, or null. A phone that
  /// slept through the end of a write asks this when its socket comes back.
  int? writingGreeting(String characterId) {
    final job = _greetingJob;
    return job != null && job.characterId == characterId ? job.index : null;
  }

  /// Stop the greeting being written for [characterId]. Nothing it wrote is
  /// saved. False when no greeting of that character is being written.
  bool stopGreeting(String characterId) {
    final job = _greetingJob;
    if (job == null || job.characterId != characterId) return false;
    _greetingJob = null;
    if (_all?.characterId == characterId) _all = null;
    job.gen.abort();
    _hub?.broadcast({
      'event': 'chargen_greeting_stopped',
      'characterId': job.characterId,
      'index': job.index,
    });
    return true;
  }

  /// Delete alternate [index] (1 and up) and its starting state together.
  Future<Map<String, dynamic>> deleteGreeting(
    String characterId,
    int index,
  ) async {
    if (busy) {
      return _refuse(409, 'Wait for the greeting being written first.');
    }
    final card = _characters.cardByDbId(characterId);
    if (card == null) return _refuse(404, 'character not found');
    final alts = card.alternateGreetings;
    if (index == 0) return _refuse(400, 'The first message cannot be deleted.');
    if (index < 1 || index > alts.length) {
      return _refuse(400, 'There is no alternate greeting $index.');
    }
    final seeds = alignGreetingSeeds(
      card.frontPorchExtensions?.greetingSeeds ?? const [],
      alts.length,
    )..removeAt(index - 1);
    final ok = await _characters.update(characterId, {
      'alternateGreetings': [...alts]..removeAt(index - 1),
      'greetingSeeds': [for (final s in seeds) s?.toFields()],
    });
    if (!ok) return _refuse(500, 'The greeting could not be deleted.');
    return {'ok': true, ..._greetingsOf(characterId)};
  }

  /// How [card] wrote its greetings: the full recipe when this run created
  /// it (the cache, persona and all lore included), else the stamp the card
  /// carries since creation, which survives a reload and a restart.
  GreetingRecipe recipeFor(String characterId, CharacterCard card) =>
      _recipes[characterId] ??
      readGreetingRecipe(card) ??
      const GreetingRecipe();

  /// Cache how a character created here wrote its greetings (the last few).
  void rememberRecipe(String? characterId, GreetingRecipe? recipe) {
    if (characterId == null || recipe == null) return;
    _recipes.remove(characterId);
    _recipes[characterId] = recipe;
    while (_recipes.length > 8) {
      _recipes.remove(_recipes.keys.first);
    }
  }

  Future<void> _writeGreeting(
    _GreetingJob job,
    CharacterCard card,
    String direction,
  ) async {
    var sentAt = DateTime.fromMillisecondsSinceEpoch(0);
    String? text;
    Object? failure;
    try {
      text = await job.gen.regenerateGreeting(
        card: card,
        index: job.index,
        direction: direction,
        recipe: recipeFor(job.characterId, card),
        onProgress: (s) {
          // The hub paints every ~33 ms anyway; a phone needs far fewer.
          final now = DateTime.now();
          if (now.difference(sentAt).inMilliseconds < 120) return;
          sentAt = now;
          _hub?.broadcast({
            'event': 'chargen_greeting_progress',
            'characterId': job.characterId,
            'index': job.index,
            'text': s,
          });
        },
      );
    } catch (e) {
      failure = e;
    }
    if (!identical(_greetingJob, job)) return; // stopped: nothing is saved
    _greetingJob = null;
    if (text == null) {
      return _greetingError(
        job,
        failure == null && job.gen.lastFailure == null
            ? 'Nothing came back from the model, so the greeting was left '
                  'as it was. Check that your model is running, then try '
                  'again.'
            : 'The greeting could not be written: '
                  '${failure ?? job.gen.lastFailure}',
      );
    }
    if (!await _saveGreeting(job.characterId, job.index, text)) {
      return _greetingError(job, 'The new greeting could not be saved.');
    }
    _hub?.broadcast({
      'event': 'chargen_greeting_done',
      'characterId': job.characterId,
      'index': job.index,
      'text': text,
      ..._greetingsOf(job.characterId),
    });
    await _advanceAll(job);
  }

  /// Put [text] in greeting [index] of the card as it is NOW (edits saved
  /// while it was written stay), through the shared character update path.
  Future<bool> _saveGreeting(String id, int index, String text) async {
    final card = _characters.cardByDbId(id);
    if (card == null) return false;
    if (index == 0) return _characters.update(id, {'firstMessage': text});
    final alts = [...card.alternateGreetings];
    final seeds = alignGreetingSeeds(
      card.frontPorchExtensions?.greetingSeeds ?? const [],
      alts.length,
    );
    if (index <= alts.length) {
      alts[index - 1] = text;
    } else {
      alts.add(text);
      seeds.add(null);
    }
    return _characters.update(id, {
      'alternateGreetings': alts,
      'greetingSeeds': [for (final s in seeds) s?.toFields()],
    });
  }

  Map<String, dynamic> _greetingsOf(String id) {
    final card = _characters.cardByDbId(id);
    return {
      'firstMessage': card?.firstMessage ?? '',
      'alternateGreetings': card?.alternateGreetings ?? const <String>[],
    };
  }

  void _greetingError(_GreetingJob job, String error) {
    if (_all?.characterId == job.characterId) _all = null;
    _hub?.broadcast({
      'event': 'chargen_greeting_error',
      'characterId': job.characterId,
      'index': job.index,
      'error': error,
    });
  }

  Map<String, dynamic> _refuse(int status, String error) => {
    'ok': false,
    'status': status,
    'error': error,
  };
}
