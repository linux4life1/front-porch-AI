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

part of '../chat_service.dart';

/// The fused reply-facts prefetch — the one place the fusion decision is made.
///
/// Called from the post-generation phase (chat_service_generation_postgen.dart)
/// immediately before the three bookkeeping passes it can serve. The passes
/// themselves stay in their own part files with their own gates; this
/// extension only answers "does ONE call cover this turn, and what came back".
/// See ReplyFactsEval for the composition rules.
extension ChatServiceReplyFacts on ChatService {
  /// Decides whether fusion applies this turn (two or more of climax /
  /// pockets / posture live — every gate is the SAME expression its
  /// standalone pass uses) and, when it does, fires the one composed call
  /// and parks the raw answer in [_replyFactsRaw] for the three passes to
  /// consume. Runs under the same speaker impersonation the passes run
  /// under, so the character context is the actual speaker's in groups too.
  ///
  /// Carrier protocol: null = no fusion (standalone calls fire as before);
  /// empty = fused call fired and failed (every pass skips — its own
  /// deterministic floor — rather than paying fallback calls on a backend
  /// that just demonstrated it is down).
  Future<void> _prefetchReplyFacts(String reply) async {
    _replyFactsRaw = null;
    if (reply.trim().isEmpty) return;
    final speaker = _activeCharacter;
    if (speaker == null) return;

    // The three gates, verbatim from their owners: _afterglowActive is the
    // climax pass's own getter; the pockets line is _runPocketsPass's first
    // check; the posture guard mirrors evaluatePhysicalStateCall's
    // realism-and-not-observer preconditions.
    final askClimax = _afterglowActive;
    final askPockets = _storageService.realismSettings.pocketsEnabled;
    final askPosture =
        _realismEnabled && !(_activeGroup != null && _observerMode);
    final live =
        (askClimax ? 1 : 0) + (askPockets ? 1 : 0) + (askPosture ? 1 : 0);
    if (live < 2) return;

    // Pockets context — the same record/roster resolution _runPocketsPass
    // performs (it will re-resolve the identical record when it consumes,
    // because pocketsFor is a map lookup and the prompt must show the record
    // as it stands NOW, before the ops apply).
    final charId = _getCharacterIdFromCard(speaker);
    final record = askPockets
        ? (pocketsFor(charId) ?? startingPocketsFor(speaker))
        : null;
    // Same lazy expiry the pass applies (idempotent — the pass re-runs it):
    // the fused prompt must never show yesterday's set-aside clothes, or the
    // model dutifully re-dresses them in them.
    record?.expireSetAside(storyDayCount);
    final transfersOn =
        askPockets &&
        _storageService.realismSettings.pocketTransfersEnabled &&
        _activeGroup != null;
    final others = transfersOn
        ? [
            for (final c in _groupCharacters)
              if (_getCharacterIdFromCard(c) != charId) c.name,
          ]
        : const <String>[];

    // Posture context — the same fragments TimeService's standalone branch
    // builds from the same scalars (the speaker's, loaded by the
    // impersonation dance above this call site).
    final emotionCtx = _characterEmotion.isNotEmpty
        ? '${speaker.name} is currently feeling $_characterEmotion '
              '($_emotionIntensity). '
        : '';
    final postureCtx = _relationshipService.spatialStance.isNotEmpty
        ? 'Recent position reference: ${speaker.name} was '
              '"${_relationshipService.spatialStance}". '
        : '';

    final raw = await _buildReplyFactsEval().fetch(
      charName: speaker.name,
      // Clamped like every judge window (the eval diet missed the fused
      // carrier — hostile review 2026-08-11).
      reply: clampEvalMessage(reply),
      recentExchange: recentExchange(_messages),
      askClimax: askClimax,
      pockets: record,
      others: others,
      askPosture: askPosture,
      emotionCtx: emotionCtx,
      postureCtx: postureCtx,
      displayClock: _timeService.displayClock,
    );
    _replyFactsRaw = raw ?? '';
    debugPrint(
      '[ReplyFacts] fused call for '
      '${[if (askClimax) 'climax', if (askPockets) 'pockets', if (askPosture) 'posture'].join('+')}'
      ' → ${raw == null ? 'FAILED (passes skip)' : '${raw.length} chars'}',
    );
  }
}
