// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_create.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_jobs.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_pending.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// The call running for the Profile step: a rewrite, a facts re-read, the
/// rest of the card, or a saved character's profile being saved (no model,
/// [gen] null). [characterId] is null for the pending run, else the saved
/// character it works on. Held from the first check, before any await, so
/// two quick taps cannot both start one.
class _ProfileJob {
  _ProfileJob(this.kind, this.gen, this.characterId);

  final String kind;
  final CharacterGenService? gen;
  final String? characterId;
}

/// The phone's Profile step. A create asked to pause stops after the
/// profile; the run waits here, written to a file so a reload after a relay
/// restart still finds it (memory is the cache). The author's texts arrive
/// with every action, so what they typed is what the model and the save
/// read. Rewrite and re-read also work on a saved character (the phone went
/// Back from Greetings), whose interview is the one its greeting recipe
/// carries. One model call at a time; a paused run is idle.
class ChargenProfile {
  ChargenProfile(
    this._characters,
    this._hub,
    this._storage,
    this._create, {
    required String? Function() busyReason,
  }) : _busyReason = busyReason;

  final CharacterFacade _characters;
  final StreamHub? _hub;
  final StorageService? _storage;
  final ChargenCreate _create;
  final String? Function() _busyReason;

  late final PendingProfileStore _store = PendingProfileStore(_storage);
  _ProfileJob? _job;

  /// Whether a Profile-step model call is running.
  bool get busy => _job != null;

  // ── Phase A ─────────────────────────────────────────────────────────

  /// Start a create that stops after the profile. A run already waiting is
  /// replaced (nothing of it was saved). The caller has checked that no
  /// model call is running.
  Map<String, dynamic> startPaused(
    String name,
    Map<String, dynamic> fields,
    LLMService svc,
  ) {
    final busy = _refuseBusy();
    if (busy != null) return busy;
    _create.creating = true;
    unawaited(_runProfile(name, fields, svc));
    return {'ok': true};
  }

  /// A new create, paused or not, replaces the waiting run: drop it, file
  /// and all, so a later Next cannot save it as a second character.
  Future<void> dropPending() => _store.discard();

  Future<void> _runProfile(
    String name,
    Map<String, dynamic> fields,
    LLMService svc,
  ) async {
    try {
      await dropPending();
      final mode = fields['mode']?.toString() ?? 'quick';
      final gen = CharacterGenService(svc);
      String? reported;
      final run = await gen.generateProfile(
        inputs: chargenInputsFromFields(name, fields),
        onStatus: (s) =>
            _hub?.broadcast({'event': 'chargen_status', 'data': s}),
        onError: (m) => reported = m,
      );
      if (run == null) {
        _hub?.broadcast(
          chargenErrorEvent(
            chargenFailure(gen, reported, 'generation produced no profile'),
          ),
        );
        return;
      }
      final pending = _store.value = PendingProfile(
        run,
        chargenSaveExtras(fields),
        mode,
      );
      await _store.save();
      _hub?.broadcast({'event': 'chargen_profile', ..._view(pending)});
    } catch (e) {
      _hub?.broadcast(chargenErrorEvent('$e'));
    } finally {
      _create.creating = false;
    }
  }

  // ── What the step shows ─────────────────────────────────────────────

  Map<String, dynamic> _viewOf(
    GenPausedRun run, {
    required String mode,
    String? characterId,
  }) => profileViewOf(run, mode: mode, characterId: characterId);

  Map<String, dynamic> _view(PendingProfile pending) =>
      _viewOf(pending.run, mode: pending.mode);

  /// `GET /api/chargen/profile`: the run waiting for Next, or with
  /// [characterId] the saved character's profile. `writing` names the
  /// model call running on it.
  Future<Map<String, dynamic>> profile({String characterId = ''}) async {
    if (characterId.isNotEmpty) {
      final run = savedProfileRun(_characters, _create, characterId);
      if (run == null) return chargenRefuse(404, 'character not found');
      // The wizard mode it was created in (Automated keeps its description
      // on a rewrite); `saved` only when the card does not say.
      final stamped = readCreatorInputs(run.card)?.mode ?? '';
      return {
        'ok': true,
        'pending': {
          ..._viewOf(
            run,
            mode: stamped.isEmpty ? 'saved' : stamped,
            characterId: characterId,
          ),
          'writing': _writingFor(characterId),
        },
      };
    }
    await _store.load();
    final pending = _store.value;
    return {
      'ok': true,
      'creating': _create.creating,
      'pending': pending == null
          ? null
          : {..._view(pending), 'writing': _writingFor(null)},
    };
  }

  String? _writingFor(String? characterId) {
    final job = _job;
    return job != null && job.characterId == characterId ? job.kind : null;
  }

  // ── The run an action works on ──────────────────────────────────────

  /// The run [body] names (a `characterId`, else the pending one) with the
  /// author's texts from [body] written in; or a refusal.
  Future<(GenPausedRun, String?)?> _target(Map<String, dynamic> body) async {
    final id = body['characterId']?.toString().trim() ?? '';
    final GenPausedRun? run;
    if (id.isNotEmpty) {
      run = savedProfileRun(_characters, _create, id);
    } else {
      await _store.load();
      run = _store.value?.run;
    }
    if (run == null) return null;
    final texts = profileTextsOf(body);
    if (texts != null) {
      run.card
        ..description = texts.description
        ..personality = texts.personality
        ..scenario = texts.scenario;
    }
    if (id.isEmpty) await _store.save();
    return (run, id.isEmpty ? null : id);
  }

  Map<String, dynamic>? _refuseBusy() {
    if (_job != null) {
      return chargenRefuse(409, 'The profile is being written. Wait for it.');
    }
    final reason = _busyReason();
    return reason == null ? null : chargenRefuse(409, reason);
  }

  /// Check and hold the Profile step's one slot in the same synchronous
  /// step (no await between them), or answer why not. [needsModel] is false
  /// for a saved character's Next, which only saves.
  ({_ProfileJob? job, Map<String, dynamic>? refusal}) _reserve(
    String kind,
    Map<String, dynamic> body, {
    bool needsModel = true,
  }) {
    final busy = _refuseBusy();
    if (busy != null) return (job: null, refusal: busy);
    final svc = needsModel ? _create.readyService : null;
    if (needsModel && svc == null) {
      return (
        job: null,
        refusal: chargenRefuse(400, 'the LLM backend is not ready'),
      );
    }
    final id = body['characterId']?.toString().trim() ?? '';
    final job = _job = _ProfileJob(
      kind,
      svc == null ? null : CharacterGenService(svc),
      id.isEmpty ? null : id,
    );
    return (job: job, refusal: null);
  }

  /// Let go of [job]'s slot if it still holds it.
  void _release(_ProfileJob job) {
    if (identical(_job, job)) _job = null;
  }

  static const _nothingPending =
      'Nothing is waiting on the Profile step. Generate the character again.';

  // ── Rewrite ─────────────────────────────────────────────────────────

  /// Rewrite the profile from its interview, steered by `direction`.
  Future<Map<String, dynamic>> startRewrite(Map<String, dynamic> body) async {
    final (:job, :refusal) = _reserve('rewrite', body);
    if (job == null) return refusal!;
    final target = await _target(body);
    if (target == null) {
      _release(job);
      return chargenRefuse(404, _nothingPending);
    }
    unawaited(_rewrite(job, target.$1, body['direction']?.toString() ?? ''));
    return {'ok': true};
  }

  Future<void> _rewrite(_ProfileJob job, GenPausedRun run, String dir) async {
    final throttle = ProgressThrottle();
    final idField = {
      if (job.characterId != null) 'characterId': job.characterId,
    };
    ProfileRewrite? result;
    Object? failure;
    try {
      result = await job.gen!.rewriteProfile(
        paused: run,
        description: run.card.description,
        personality: run.card.personality,
        scenario: run.card.scenario,
        direction: dir,
        onProgress: (acc) {
          if (!throttle.ready) return;
          final v = parseProfileStream(acc);
          _hub?.broadcast({
            'event': 'chargen_profile_progress',
            ...idField,
            'field': v.writing.name,
            'description': v.description,
            'personality': v.personality,
            'scenario': v.scenario,
          });
        },
      );
    } catch (e) {
      failure = e;
    }
    if (!identical(_job, job)) return; // stopped: the old text stays
    _job = null;
    if (result == null) {
      _hub?.broadcast({
        'event': 'chargen_profile_error',
        ...idField,
        'error': failure != null || job.gen!.lastFailure != null
            ? 'The profile could not be rewritten: '
                  '${chargenFailure(job.gen!, failure?.toString(), '')}'
            : 'The rewrite came back the same as before, so nothing was '
                  'changed. Try a clearer direction, or check that your '
                  'model is running.',
      });
      return;
    }
    run.card
      ..description = result.description
      ..personality = result.personality
      ..scenario = result.scenario;
    final facts = _merged(run, result.facts);
    if (job.characterId == null) {
      final pending = _store.value;
      if (pending != null && identical(pending.run.card, run.card)) {
        _store.value = pending.withRun(pending.run.copyWith(facts: facts));
        await _store.save();
      }
    }
    _hub?.broadcast({
      'event': 'chargen_profile_done',
      ...idField,
      'description': result.description,
      'personality': result.personality,
      'scenario': result.scenario,
      'facts': facts.toJson(),
    });
  }

  /// [read] over what [run]'s card has: a value the read left empty keeps
  /// the one before, so a thin answer never wipes a field.
  IdentityFacts _merged(GenPausedRun run, IdentityFacts? read) {
    if (read == null) return run.facts ?? identityFactsOfCard(run.card);
    applyIdentityFacts(run.card, read, nsfw: run.inputs.nsfwEnabled);
    final now = identityFactsOfCard(run.card);
    return IdentityFacts.fromJson({...now.toJson(), 'warmth': read.warmth});
  }

  /// Stop the profile rewrite, the re-read, or the rest of the card being
  /// written. Nothing it wrote is kept; a stopped Next leaves the profile
  /// waiting as it was (the rest is written on a copy).
  bool stop(Map<String, dynamic> body) {
    final id = body['characterId']?.toString().trim() ?? '';
    final job = _job;
    if (job == null || job.gen == null) return false;
    if ((job.characterId ?? '') != id) return false;
    _job = null;
    job.gen!.abort();
    _hub?.broadcast({
      'event': 'chargen_profile_stopped',
      'characterId': ?job.characterId,
      if (job.kind == 'complete') 'phase': 'complete',
    });
    return true;
  }

  // ── Facts ───────────────────────────────────────────────────────────

  /// Read the identity facts again from the profile as the author has it.
  Future<Map<String, dynamic>> startFacts(Map<String, dynamic> body) async {
    final (:job, :refusal) = _reserve('facts', body);
    if (job == null) return refusal!;
    final target = await _target(body);
    if (target == null) {
      _release(job);
      return chargenRefuse(404, _nothingPending);
    }
    unawaited(_facts(job, target.$1));
    return {'ok': true};
  }

  Future<void> _facts(_ProfileJob job, GenPausedRun run) async {
    final idField = {
      if (job.characterId != null) 'characterId': job.characterId,
    };
    IdentityFacts? read;
    try {
      read = await job.gen!.rereadIdentityFacts(
        paused: run,
        description: run.card.description,
        personality: run.card.personality,
        scenario: run.card.scenario,
      );
    } catch (e) {
      debugPrint('[chargen] facts re-read failed: $e');
    }
    if (!identical(_job, job)) return;
    _job = null;
    if (read == null) {
      _hub?.broadcast({
        'event': 'chargen_facts_error',
        ...idField,
        'error': job.gen!.lastFailure != null
            ? 'The facts could not be read again: ${job.gen!.lastFailure}'
            : 'The facts could not be read again. Check that your model is '
                  'running, then try again.',
      });
      return;
    }
    final facts = _merged(run, read);
    if (job.characterId == null) {
      final pending = _store.value;
      if (pending != null && identical(pending.run.card, run.card)) {
        _store.value = pending.withRun(pending.run.copyWith(facts: facts));
        await _store.save();
      }
    }
    _hub?.broadcast({
      'event': 'chargen_facts_done',
      ...idField,
      'facts': facts.toJson(),
    });
  }

  // ── Next ────────────────────────────────────────────────────────────

  /// Next on the Profile step: the pending run's texts and facts as the
  /// author left them, then the rest of the card and the save
  /// (`chargen_done`). For a saved character (`characterId`), the texts and
  /// facts are saved to it and nothing is written by the model.
  Future<Map<String, dynamic>> startContinue(Map<String, dynamic> body) async {
    final saved = (body['characterId']?.toString().trim() ?? '').isNotEmpty;
    final (:job, :refusal) = _reserve(
      saved ? 'save' : 'complete',
      body,
      needsModel: !saved,
    );
    if (job == null) return refusal!;
    final target = await _target(body);
    final pending = _store.value;
    if (target == null || (!saved && pending == null)) {
      _release(job);
      return chargenRefuse(404, _nothingPending);
    }
    final (run, id) = target;
    final rawFacts = body['facts'];
    final facts = rawFacts is Map
        ? IdentityFacts.fromJson(Map<String, dynamic>.from(rawFacts))
        : null;
    if (id != null) {
      try {
        return await _saveProfile(id, run, facts);
      } finally {
        _release(job);
      }
    }
    final nsfw = run.inputs.nsfwEnabled;
    if (facts != null) writeEditedFacts(run.card, facts, nsfw: nsfw);
    final edited = _store.value = pending!.withRun(run.copyWith(facts: facts));
    await _store.save();
    unawaited(_complete(job, edited));
    return {'ok': true, 'phase': 'complete'};
  }

  Future<void> _complete(_ProfileJob job, PendingProfile pending) async {
    final gen = job.gen!;
    String? reported;
    try {
      final card = await gen.completeCharacter(
        paused: pending.run,
        onStatus: (s) =>
            _hub?.broadcast({'event': 'chargen_status', 'data': s}),
        onError: (m) => reported = m,
      );
      // Stopped: the profile waits as it was, and nothing is saved.
      if (!identical(_job, job)) return;
      final id = await _create.saveGenerated(
        card,
        gen,
        pending.run.inputs,
        pending.extras,
        mode: pending.mode,
        failure: reported,
      );
      if (id != null && identical(_store.value, pending)) {
        _store.value = null;
        await _store.save();
      }
    } catch (e) {
      _hub?.broadcast(chargenErrorEvent('$e'));
    } finally {
      if (identical(_job, job)) _job = null;
    }
  }

  Future<Map<String, dynamic>> _saveProfile(
    String id,
    GenPausedRun run,
    IdentityFacts? facts,
  ) => saveProfileToCard(_characters, id, run, facts);
}
