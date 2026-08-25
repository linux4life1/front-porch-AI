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

/// Greeting + baseline-eval subsystem: the once-per-session post-greeting
/// baseline eval, the retroactive baseline scan (Realism toggled on mid-chat),
/// alternate-greeting cycling, and first-message macro resolution. Extracted
/// verbatim from the god file (zero behaviour change) — these run on the active
/// character's scalars via the normal eval path (no `_groupRealism` load/save),
/// so 1:1 and group baseline behaviour is unchanged.
extension ChatServiceGreeting on ChatService {
  /// WHERE SHE IS WHEN IT IS HER TURN TO SPEAK FOR THE FIRST TIME.
  ///
  /// Posture became a POST-generation question on 2026-08-08, because a
  /// position a character establishes in her own words cannot be known by a
  /// judge that ran before those words existed. That fixed the teleporting —
  /// and left turn one with nothing at all. The maintainer's requirement is
  /// both halves, verbatim: "we need the part that informs the character where
  /// they are when they start their turn. and the post gen portion that comes
  /// after their response so they know where they moved to." This is the first
  /// half.
  ///
  /// ── WHY IT IS A GUARD RATHER THAN A CALL SITE ───────────────────────────
  ///
  /// The obvious fix — seed it wherever a chat begins — was tried and is what
  /// produced the regression this replaces. A conversation can begin four
  /// different ways (startNewChat, setActiveCharacter with no prior session,
  /// setActiveGroup, and a reload of a session that predates the feature), and
  /// the seed shipped wired to exactly one of them, behind two gates it did
  /// not need: `frontPorchExtensions == null` — which excludes every card
  /// authored in Front Porch AI and every card downloaded from The Stoop, i.e.
  /// almost every real card — and `_activeGroup == null`, which excluded
  /// groups entirely.
  ///
  /// So the question is asked at the ONE moment that is common to all of them:
  /// just before a speaker's turn is evaluated, once, when nothing is on
  /// record. `spatialStance.isEmpty` is the whole guard, and it is exact:
  ///   * it is per-SPEAKER, because the group dance has already loaded this
  ///     speaker's scalars from their own `_groupRealism` slot — so a cast of
  ///     five gets five separate openings and none of them inherits the
  ///     first speaker's,
  ///   * it survives a reload, because the stance it reads is the persisted
  ///     one (`sessions.spatial_stance` for 1:1, the per-member blob for a
  ///     group) rather than a flag that would reset to "unseeded" and re-fire
  ///     over a real position,
  ///   * and it CANNOT overwrite a post-reply value on any later turn, which
  ///     is the ruling this must not violate: it only ever runs when there is
  ///     no value to overwrite. The instant any post-generation pass succeeds
  ///     the guard closes for good, and posture is a post-reply question again
  ///     for the rest of the conversation.
  ///
  /// The one case it re-fires is a post-generation pass that answered "none"
  /// (`setSpatialStance` normalises that to empty). That is a retry, not a
  /// stale overwrite: this pass reads the same window the post-generation one
  /// did — the transcript up to and including the reply — so it can never be
  /// older than the answer it replaces.
  ///
  /// Costs one eval call on the opening turn of a chat and nothing after it.
  ///
  /// ── WHY IT IS SINGLE-FLIGHT ─────────────────────────────────────────────
  ///
  /// Two callers reach here, and neither knows about the other: the greeting
  /// baseline fires this in the background the moment a chat opens, and the
  /// pre-turn dance fires it again just before the first speaker is
  /// evaluated. The guard they share — "no stance on record" — is a read of a
  /// value only the COMPLETED call writes, so while the baseline's request is
  /// still on the wire the dance sees an empty stance too and asks the same
  /// question a second time. That is a wasted call on the opening turn of
  /// every chat, and worse: two independent answers race to be the opening
  /// position, so which one a chat starts from depends on network timing.
  ///
  /// `_openingPostureSeed` makes the second caller WAIT for the first instead
  /// of duplicating it. The guards are re-read after the wait rather than
  /// short-circuited, which is what keeps the retry semantics above intact
  /// (a pass that answered "none" leaves the stance empty and the waiter is
  /// free to try again) and what makes a chat switch mid-flight safe (the
  /// waiter re-checks against the chat it is actually in).
  Future<void> _seedOpeningPosture() async {
    // Loop rather than a single await: two waiters released together would
    // both re-check an empty stance and both fire. Terminates because only
    // these two entry points ever create a seed.
    while (_openingPostureSeed != null) {
      await _openingPostureSeed;
    }
    if (!_realismActiveThisMode) return;
    if (_relationshipService.spatialStance.isNotEmpty) return;
    // ONCE PER CHAT, not once per empty stance.
    //
    // The guard above is `isEmpty`, and setSpatialStance normalises both ''
    // and 'none' to empty — so a scene the model reads as having no clear
    // position (which is a perfectly ordinary answer) leaves the stance empty
    // and this fired AGAIN on the very next turn, and every turn after that,
    // forever. That is an extra model call per reply for the rest of the chat,
    // against a Rawhide bullet promising "one short request at the very start
    // of a conversation and nothing afterwards" — and, until the call site
    // grew a catch, one more chance per turn to take the whole engine down.
    //
    // Attempted-once is the right rule: the seed exists only to cover the gap
    // before the first reply exists. From the first reply onward the
    // post-generation pass reads where she actually is, which is the whole
    // point of moving posture after the reply.
    // Keyed on session AND SPEAKER. A group has one session but a cast, and
    // every member needs their own opening position in their own _groupRealism
    // slot — keying on the session alone seeded whoever spoke first and left
    // the rest of the cast with no Position line for the whole chat. Caught by
    // posture_opening_seed_test's "EVERY member gets their own opening
    // position in their own slot", which is exactly the 1:1-vs-group parity
    // rule this project treats as law.
    //
    // `?? ''` rather than a null-guard: a chat whose row has not been written
    // yet (the first turn of a brand-new chat, and every unit test) has a null
    // id, and skipping the mark for it is what let the seed fire on every turn
    // anyway — the exact bug, still there, just narrower.
    final key =
        '${_currentSessionId ?? ''}|'
        '${_activeCharacter == null ? '' : _getCharacterIdFromCard(_activeCharacter!)}';
    if (_openingPostureSeededFor == key) return;
    _openingPostureSeededFor = key;
    debugPrint('[Realism:Posture] Seeding opening position (none on record)');
    final seed = _evaluatePhysicalStateCall(postureOnly: true);
    // The waiter's copy swallows failures: a seed that blew up is the OWNER's
    // problem to surface (it still awaits `seed` raw, exactly as before this
    // was single-flight), and must not become an exception thrown at whoever
    // happened to arrive second.
    _openingPostureSeed = seed
        .catchError((Object _) {})
        .whenComplete(() => _openingPostureSeed = null);
    await seed;
  }

  /// Evaluates emotion + relationship baseline from the greeting message only.
  /// Runs once per new session, silently in the background.
  Future<void> _runPostGreetingEval() async {
    if (!_realismEnabled) return;
    final evalChar = _activeCharacter ??
        _greetingOwnerCard() ??
        (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
    // Groups have a null _activeCharacter; still Read the Room when an
    // unauthored opener reached this path.
    if (evalChar == null && _activeGroup == null) return;
    testPostGreetingEvalEntered = true;
    final token = _greetingEvalGen;
    final indexStamp = _greetingIndex;
    final previousActive = _activeCharacter;
    if (_activeCharacter == null && evalChar != null) {
      _activeCharacter = evalChar;
    }
    _greetingEvalPending = false; // consume the pending flag
    debugPrint('[Realism] Running post-greeting baseline eval...');
    await runZoned(() async {
      _isProcessingGreeting = true;
      notifyListeners();
      try {
        await Future.wait([
          // delegates to _llmEvalEngine (step 9 thins; full bodies excised)
          _evaluateEmotionalStateCall(),
          Future.delayed(
            _kEvalDispatchStagger,
            () => _evaluateRelationshipCall(),
          ),
          // WHERE SHE IS WHEN THE STORY OPENS. The greeting IS the opening scene
          // — "she is rocking in the armchair when you walk in" — so the baseline
          // is the earliest moment the opening position can be read, and reading
          // it here means the sidebar shows a position before the user has typed
          // anything. It is the SAME seed the pre-turn path uses, and the seed
          // is single-flight (see _seedOpeningPosture): this one is a head
          // start, and a pre-turn dance that arrives while it is still in flight
          // waits for this answer instead of asking again.
          Future.delayed(_kEvalDispatchStagger * 2, () => _seedOpeningPosture()),
        ]);

        if (_realismEvalCancelled ||
            token != _greetingEvalGen ||
            indexStamp != _greetingIndex) {
          debugPrint('[Realism] Post-greeting eval cancelled or stale');
          _realismEvalCancelled = false;
          return;
        }

        // Check for cancellation after each eval
        if (_realismEvalCancelled ||
            token != _greetingEvalGen ||
            indexStamp != _greetingIndex) {
          debugPrint('[Realism] Post-greeting eval cancelled or stale');
          _realismEvalCancelled =
              false; // Reset the flag so future messages can proceed
          return;
        }

        // Store initial emotion in metadata on the greeting message itself
        if (_messages.isNotEmpty) {
          _messages.first.activeMetadata ??= {};
          if (_characterEmotion.isNotEmpty) {
            _messages.first.activeMetadata!['emotion_label'] = _characterEmotion;
            _messages.first.activeMetadata!['realism_state'] =
                _captureRealismState();
          }
        }
        // Unauthored group RtR writes live scalars only unless we put them
        // back in the member slot before persist / first-speaker load.
        if (_activeGroup != null) {
          _writeBackGreetingEvalToGroupSlots(evalChar);
        }
        await _saveChat();
        notifyListeners();
        debugPrint(
          '[Realism] Post-greeting baseline: emotion=$_characterEmotion, bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}',
        );
      } catch (e) {
        debugPrint('[Realism] Post-greeting eval failed: $e');
      } finally {
        // Per-eval Zone token only. Do not reintroduce a global slot.
        if (_activeGroup != null) {
          _activeCharacter = previousActive;
        }
        _isProcessingGreeting = false;
        notifyListeners();
      }
    }, zoneValues: {
      _kGreetingEvalToken: token,
      _kGreetingEvalIndex: indexStamp,
    });
  }

  /// Retroactive baseline eval — fires when Realism is enabled mid-conversation
  /// with no prior state captured. Evaluates the full visible message history
  /// so the engine catches up on emotion, bond, and scene state.
  Future<void> _runRetroactiveBaselineEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    debugPrint(
      '[Realism] Running retroactive baseline scan (${_messages.length} messages)...',
    );
    _isProcessingGreeting = true; // reuse the greeting overlay
    notifyListeners();
    try {
      if (_oneShotActive) {
        await _evaluateOneShotCall(); // step 10 thin (full in realism_evals)

        // Check for cancellation after one-shot eval
        if (_realismEvalCancelled) {
          debugPrint('[Realism] Retroactive scan cancelled');
          _realismEvalCancelled =
              false; // Reset the flag so future messages can proceed
          return;
        }
      } else {
        await Future.wait([
          _evaluateRelationshipCall(),
          Future.delayed(
            _kEvalDispatchStagger,
            () => _evaluateEmotionalStateCall(),
          ),
          Future.delayed(
            _kEvalDispatchStagger * 2,
            () => _evaluatePhysicalStateCall(),
          ),
          Future.delayed(
            _kEvalDispatchStagger * 3,
            () => _evaluateNarrativeCall(),
          ),
        ]);

        if (_realismEvalCancelled) {
          debugPrint('[Realism] Retroactive scan cancelled');
          _realismEvalCancelled = false;
          return;
        }
      }

      // Where the history left her. Shared by BOTH branches above and placed
      // after them for exactly that reason: one-shot's fused JSON no longer
      // carries posture, and the four-call branch's physical-state call is
      // now the clock alone, so neither branch produces a position on its
      // own. Without this, switching Realism on mid-conversation caught the
      // engine up on mood and bond and then wrote the next reply with no
      // staging at all — the same hole turn one had. Guarded like every other
      // seed: a chat that already knows where she is keeps that answer.
      await _seedOpeningPosture();

      // Stamp the baseline on the most recent message so it persists
      if (_messages.isNotEmpty) {
        _messages.last.activeMetadata ??= {};
        _messages.last.activeMetadata!['emotion_label'] = _characterEmotion;
        _messages.last.activeMetadata!['realism_state'] =
            _captureRealismState();
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Retroactive scan complete: emotion=$_characterEmotion, bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}',
      );
    } catch (e) {
      debugPrint('[Realism] Retroactive baseline scan failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Bump [_greetingEvalGen] and cancel any in-flight unauthored RtR so a
  /// late apply cannot paint the previous opening onto a newly loaded
  /// first_mes (New Chat, switch character/group, swipe, load, import, fork).
  Future<void> _invalidateGreetingEval() async {
    _greetingEvalGen++;
    await cancelRealismEval();
    _realismEvalCancelled = false;
  }

  /// Cycle the first message through alternate greetings.
  /// Commit-once: the same [selectGreeting] path the picker uses.
  Future<void> cycleGreeting(int direction) async {
    if (_messages.isEmpty) return;
    final allGreetings = openingAllGreetings;
    if (allGreetings.length <= 1) return;

    var next = (_greetingIndex + direction) % allGreetings.length;
    if (next < 0) next += allGreetings.length;
    await selectGreeting(next);
  }

  String _buildFirstMessage(CharacterCard character, {String? greetingText}) {
    String msg = greetingText ?? character.firstMessage;
    return _macroResolver.resolve(
      msg,
      MacroContext(
        userName: _userPersonaService.persona.name,
        characterName: character.name,
      ),
      section: 'firstMessage',
    );
  }

  /// First displayed member greet — same as 1:1 [CharacterCard.allGreetings].
  /// Empty when the member has no usable opening (whitespace first_mes and
  /// no alts). Group open must not gate on [CharacterCard.firstMessage] alone.
  String _memberOpeningGreetingText(CharacterCard member) {
    final opening = member.allGreetings;
    if (opening.isEmpty) return '';
    return _buildFirstMessage(member, greetingText: opening.first);
  }
}
