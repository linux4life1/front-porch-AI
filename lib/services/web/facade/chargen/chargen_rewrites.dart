// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_create.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_jobs.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// The example dialogue or lorebook being rewritten, so Stop reaches it.
class _RewriteJob {
  _RewriteJob(this.characterId, this.field, this.gen);

  final String characterId;

  /// `mesExample` or `lorebook`.
  final String field;
  final CharacterGenService gen;
}

/// The two review rewrites at the foot of the phone's Greetings step (the
/// desktop's Review step): new example dialogue, or a new lorebook that
/// keeps the entries edited by hand. Each is its own run from the saved
/// card, steered by the author; the result is saved only when it is done,
/// so Stop leaves the card as it was. Events: `chargen_rewrite_progress`,
/// `_done` (saved), `_error`, `_stopped`.
class ChargenRewrites {
  ChargenRewrites(
    this._characters,
    this._hub,
    this._create, {
    required GreetingRecipe Function(String id, CharacterCard card) recipeFor,
    required String? Function() busyReason,
  }) : _recipeFor = recipeFor,
       _busyReason = busyReason;

  final CharacterFacade _characters;
  final StreamHub? _hub;
  final ChargenCreate _create;
  final GreetingRecipe Function(String id, CharacterCard card) _recipeFor;
  final String? Function() _busyReason;

  _RewriteJob? _job;

  bool get busy => _job != null;

  /// Which field of [characterId] is being rewritten, or null.
  String? writing(String characterId) {
    final job = _job;
    return job != null && job.characterId == characterId ? job.field : null;
  }

  /// Start rewriting [field] (`mesExample` or `lorebook`) of the character
  /// in [body], steered by `direction`.
  Map<String, dynamic> start(String field, Map<String, dynamic> body) {
    final id = body['characterId']?.toString().trim() ?? '';
    if (id.isEmpty) return chargenRefuse(400, 'characterId is required');
    final card = _characters.cardByDbId(id);
    if (card == null) return chargenRefuse(404, 'character not found');
    if (_job != null) {
      return chargenRefuse(409, 'Something is being rewritten. Wait for it.');
    }
    final reason = _busyReason();
    if (reason != null) return chargenRefuse(409, reason);
    final svc = _create.readyService;
    if (svc == null) return chargenRefuse(400, 'the LLM backend is not ready');
    final job = _job = _RewriteJob(id, field, CharacterGenService(svc));
    unawaited(_run(job, card, body['direction']?.toString() ?? ''));
    return {'ok': true};
  }

  /// Stop the rewrite running for [characterId]; nothing it wrote is saved.
  bool stop(String characterId) {
    final job = _job;
    if (job == null || job.characterId != characterId) return false;
    _job = null;
    job.gen.abort();
    _hub?.broadcast({
      'event': 'chargen_rewrite_stopped',
      'characterId': characterId,
      'field': job.field,
    });
    return true;
  }

  Future<void> _run(_RewriteJob job, CharacterCard card, String dir) async {
    final throttle = ProgressThrottle();
    void progress(String text) {
      if (!throttle.ready) return;
      _hub?.broadcast({
        'event': 'chargen_rewrite_progress',
        'characterId': job.characterId,
        'field': job.field,
        'text': text,
      });
    }

    final recipe = _recipeFor(job.characterId, card);
    final inputs = _create.inputsFor(job.characterId);
    String? text;
    Lorebook? book;
    Object? failure;
    try {
      if (job.field == 'mesExample') {
        text = await job.gen.regenerateExampleDialogue(
          card: card,
          recipe: recipe,
          direction: dir,
          onProgress: progress,
        );
      } else {
        book = await job.gen.rewriteLorebook(
          card: card,
          recipe: recipe,
          concept: inputs?.concept ?? card.description,
          loreCategories: inputs?.loreCategories ?? const [],
          loreDepth: inputs?.loreDepth ?? 'Standard',
          direction: dir,
          onProgress: progress,
        );
      }
    } catch (e) {
      failure = e;
    }
    if (!identical(_job, job)) return; // stopped: nothing is saved
    _job = null;
    if (text == null && book == null) {
      return _error(
        job,
        failure != null
            ? 'The rewrite failed: $failure'
            : 'Nothing usable came back from the model, so it was left as '
                  'it was. Check that your model is running, then try again.',
      );
    }
    // Into the card as it is now; the merged book keeps each entry's
    // extensions (the fingerprint that marks the generator's own text).
    final live = _characters.cardByDbId(job.characterId);
    if (live == null) return _error(job, 'The character is gone.');
    if (text != null) live.mesExample = text;
    if (book != null) live.lorebook = book;
    if (!await _characters.update(job.characterId, const {})) {
      return _error(job, 'The rewrite could not be saved.');
    }
    _hub?.broadcast({
      'event': 'chargen_rewrite_done',
      'characterId': job.characterId,
      'field': job.field,
      'text': ?text,
      if (book != null) 'lorebook': lorebookRows(book),
    });
  }

  void _error(_RewriteJob job, String error) => _hub?.broadcast({
    'event': 'chargen_rewrite_error',
    'characterId': job.characterId,
    'field': job.field,
    'error': error,
  });
}

/// [book]'s entries as the phone's lorebook card lists them: name, a
/// preview of the content, and whether the author edited it by hand.
List<Map<String, dynamic>> lorebookRows(Lorebook? book) => [
  for (final e in book?.entries ?? const <LorebookEntry>[])
    {'name': e.name, 'content': e.content, 'handEdited': isHandEdited(e)},
];
