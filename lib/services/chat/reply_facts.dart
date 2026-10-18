// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/chat/climax_eval.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/pockets_ledger.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/chat/reply_facts_eval.dart';

/// The fused reply-facts prefetch — the one place the fusion decision is made.
///
/// Called from the post-generation phase (chat_service_generation_postgen
/// _engine.dart) immediately before the three bookkeeping passes it can
/// serve. The passes themselves stay in their own classes with their own
/// gates; this only answers "does ONE call cover this turn, and what came
/// back". Transport only. See ReplyFactsEval for the composition rules.
class ReplyFacts {
  ReplyFacts(
    this._scope,
    this._ledger, {
    required this.afterglowActive,
    required this.storyDayCount,
    required this.buildEval,
  });

  final RealismScope _scope;
  final PocketsLedger _ledger;

  /// The climax pass's own gate (`AfterglowPass.active`).
  final bool Function() afterglowActive;
  final int Function() storyDayCount;

  /// A stateless wrapper over the shared fire closure, built per turn.
  final ReplyFactsEval Function() buildEval;

  /// The fused carrier: null = no fusion (standalone calls fire), empty =
  /// the fused call failed (every pass skips). Cleared once the passes ran.
  String? raw;

  /// Decides whether fusion applies this turn (two or more of climax /
  /// pockets / posture live — every gate is the SAME expression its
  /// standalone pass uses) and, when it does, fires the one composed call
  /// and parks the raw answer in [raw] for the three passes to
  /// consume. Runs under the same speaker impersonation the passes run
  /// under, so the character context is the actual speaker's in groups too.
  ///
  /// Carrier protocol: null = no fusion (standalone calls fire as before);
  /// empty = fused call fired and failed (every pass skips — its own
  /// deterministic floor — rather than paying fallback calls on a backend
  /// that just demonstrated it is down).
  Future<void> prefetch(String reply) async {
    this.raw = null;
    if (reply.trim().isEmpty) return;
    final speaker = _scope.activeCharacter();
    if (speaker == null) return;

    // The three gates, verbatim from their owners: AfterglowPass.active is the
    // climax pass's own getter; the pockets line is PocketsPass.run's first
    // check; the posture guard mirrors evaluatePhysicalStateCall's
    // realism-and-not-observer preconditions.
    final askClimax = afterglowActive();
    final askPockets = _ledger.pocketsEnabledFor(
      _scope.characterIdFor(speaker),
    );
    final askPosture =
        _scope.realismEnabled() &&
        !(_scope.activeGroup() != null && _scope.observerMode());
    final live =
        (askClimax ? 1 : 0) + (askPockets ? 1 : 0) + (askPosture ? 1 : 0);
    if (live < 2) return;

    // Pockets context — the same record/roster resolution PocketsPass.run
    // performs (it will re-resolve the identical record when it consumes,
    // because pocketsFor is a map lookup and the prompt must show the record
    // as it stands NOW, before the ops apply).
    final charId = _scope.characterIdFor(speaker);
    final record = askPockets
        ? (_ledger.pocketsFor(charId) ??
              PocketsLedger.startingPocketsFor(speaker))
        : null;
    // Same lazy expiry the pass applies (idempotent — the pass re-runs it):
    // the fused prompt must never show yesterday's set-aside clothes, or the
    // model dutifully re-dresses them in them.
    record?.expireSetAside(storyDayCount());
    final others = askPockets
        ? _ledger.pocketTransferRoster(charId)
        : const <String>[];

    // Posture context — the same fragments TimeService's standalone branch
    // builds from the same scalars (the speaker's, loaded by the
    // impersonation dance above this call site).
    final emotionCtx = _scope.emotion().isNotEmpty
        ? '${speaker.name} is currently feeling ${_scope.emotion()} '
              '(${_scope.intensity()}). '
        : '';
    final postureCtx = _scope.relationship().spatialStance.isNotEmpty
        ? 'Recent position reference: ${speaker.name} was '
              '"${_scope.relationship().spatialStance}". '
        : '';

    final raw = await buildEval().fetch(
      charName: speaker.name,
      // Clamped like every judge window (the eval diet missed the fused
      // carrier — hostile review 2026-08-11).
      reply: clampEvalMessage(reply),
      recentExchange: recentExchange(_scope.messages),
      askClimax: askClimax,
      pockets: record,
      others: others,
      askPosture: askPosture,
      emotionCtx: emotionCtx,
      postureCtx: postureCtx,
      displayClock: _scope.time().displayClock,
      // The speaker's card (the same impersonation the passes run under),
      // so the fused and standalone climax lanes ask about one body.
      physiology: ClimaxEval.physiologyFor(speaker),
    );
    this.raw = raw ?? '';
    debugPrint(
      '[ReplyFacts] fused call for '
      '${[if (askClimax) 'climax', if (askPockets) 'pockets', if (askPosture) 'posture'].join('+')}'
      ' → ${raw == null ? 'FAILED (passes skip)' : '${raw.length} chars'}',
    );
  }
}
