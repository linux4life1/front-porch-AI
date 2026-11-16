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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/persona/persona.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'send_spine.dart';

/// The body of a user turn once [SendSpine.sendMessage]'s guards passed:
/// the cast settles, the line is saved, a parked dream surfaces, a blind
/// model's photo is captioned, the lore scan and the Chaos clear, the
/// direct-address route, the Chaos wheel's park, the call-model swap, the
/// player's time skip and the pre-reply goal check; then [SendHandoff].
/// Continue does not tick — that path never enters this file.
class SendTurn {
  SendTurn(this._s);

  final SendSpine _s;

  ChatSessionState get _session => _s.session;
  StorageService get _storageService => _s.storage;
  RealismGraph get realism => _s.graph;
  MediaDoor get mediaDoor => _s.media;
  CastDoor get _cast => _s.cast;
  ControlsDoor get _controls => _s.controls;
  ChanceTime get _chance => _controls.chance;
  bool get _clockRunning => _controls.clockRunning;
  TimeService get _timeService => realism.time;
  DreamService get _dreamService => realism.dreams;
  JournalStore get _journalStore => realism.journalStore;
  String get _characterEmotion => realism.registers.emotion;
  LorebookScanner get _lorebookScanner => realism.lore.scanner;
  ChaosModeService get _chaosModeService => realism.chaos;
  PorchMemoryImportService get _porchMemoryImport => realism.porchImport;
  RealismScope _realismScope() => realism.scope;
  PlayerSkip _buildPlayerSkip() => realism.playerSkip();
  bool get _isNewChat => _s.sessions.isNewChat;
  set _isNewChat(bool v) => _s.sessions.isNewChat = v;
  set _lastUserMessageAt(DateTime? at) => _s.prompts.lastUserMessageAt = at;
  Future<void> _saveChat() => _s.saveChat();
  void notifyListeners() => _s.notify();
  bool _sceneChanged(String? token) => _cast.sceneChanged(token);
  void _setGuestStatus(String? msg, {bool isError = false}) =>
      _cast.guests.setStatus(msg, isError: isError);
  Future<void> _commitPendingMemberExit() =>
      _cast.roster.commitPendingMemberExit();
  void _clearExitUndo() => _cast.guests.clearExitUndo();
  void _cancelIdleTimer() => _cast.idle.cancelIdleTimer();
  CharacterCard? _directAddressRoutedGuest(String promptText) =>
      _cast.guests.directAddressRoutedGuest(promptText);
  Future<bool> _bridgeLongSkip({
    required DateTime from,
    required int skipped,
    required ChatMessage skipLine,
    required String? token,
  }) => _cast.stage.bridgeLongSkip(
    from: from,
    skipped: skipped,
    skipLine: skipLine,
    token: token,
  );
  bool checkAndTickChaosPressure() => _chance.checkAndTickChaosPressure();
  List<String> spinWheelEvents({GroupMemberRealism? memberBag}) =>
      _chance.spinWheelEvents(memberBag: memberBag);
  String get chanceTimeSpeakerName => _s.chanceReveal.chanceTimeSpeakerName;
  void _enterCallEvalModelSwap() => _s.enterCallModelSwap();
  void _exitCallEvalModelSwap() => _s.exitCallModelSwap();
  Future<SkipVerdict?> _askSkip(PendingSkip question, String? token) =>
      _s.gates.askSkip(question, token);

  /// The pre-reply goal check. Send runs it; Continue and Regen do not
  /// (objective_check_gate_test reads this name in this file).
  Future<void> _maybeCheckTaskCompletionSync() =>
      _s.objectives.completion.maybeCheckSync();

  /// Runs inside [SendSpine.sendMessage]'s user-turn hold, after every
  /// guard, the slash command and the start-of-turn clears.
  Future<void> run({
    required String outbound,
    required Uint8List? imageBytes,
    required SkipTag skipTag,
    required LookupForceParse lookup,
  }) async {
    // Sending a real message ends the /exit undo window. A pending full-member
    // exit commits now (real removal + any collapse to a 1:1) so this turn runs
    // in the settled cast; lite-guest undo state is just cleared.
    await _commitPendingMemberExit();
    _clearExitUndo();

    // Save the attachment to disk only now that every guard has passed — the
    // composer passes bytes, not a path, so a guard bail above can't orphan a
    // file. Null when there are no bytes / the image service isn't wired.
    // Director Mode: {{user}} is off stage and the line is a director's
    // note. It runs the same turn as any send (dreams, time skips, chaos,
    // @Name cues, Needs, the clock); only the judges that score the user's
    // message stand down, because there is no user message to score.
    final directing = _s.entry.director.directing;
    final imagePath = directing
        ? null
        : await mediaDoor.persistTurnImage(imageBytes);

    // Stamped by id: several personas can share a name, and the bubble
    // must show the one that actually spoke.
    final speaker = _s.deps.services.personas.persona;
    // An @Name routes the turn, then leaves the line: the bubble and the
    // prompt carry what was said, routing keeps the typed line.
    final cleaned = directing ? outbound : _cast.guests.shownUserText(outbound);
    final shown = cleaned.isEmpty && imageBytes == null ? outbound : cleaned;
    final userMsg = directing
        ? directorNoteMessage(outbound)
        : ChatMessage(
            text: shown,
            sender: speaker.name,
            isUser: true,
            metadata: {
              kUserPersonaIdMeta: speaker.id,
              if (shown != outbound) kAtMentionRawTextMeta: outbound,
              if (imagePath != null) ...{
                'is_user_image': true,
                'image_path': imagePath,
              },
            },
          );
    // Session token for the caption writes below — captured NOW so a chat
    // switch anywhere during the (long) turn voids the stamp+save.
    final sessionToken = _session.currentSessionId;
    // Per-member memory: who is in the scene as this line is said.
    _cast.memory.stamp(userMsg);
    _session.messages.add(userMsg);
    await _saveChat();
    notifyListeners();

    // ── Dreams (Living Time §1) — a night passed, so the dream surfaces
    // before this morning's exchange. The text was PRE-GENERATED at the end
    // of the turn whose clock crossed the night (_maybeKickDreamPrefetch,
    // called from the post-generation phase), so this await is on an
    // almost-always-completed future and the send path no longer waits on a
    // model call (eval review item 6 — dreams were one of the two calls
    // still blocking a send). Owner rules, insertion position, the journal
    // card and the silent-skip floor are unchanged.
    //
    // The bookkeeping call here is anchor-only (nothing at entry consumes
    // pending any more): it runs BEFORE this turn's pre-generation clock
    // advance, so the first turn after a chat load anchors on the pre-advance
    // day exactly as the old design did. Without it the first post-generation
    // kick would anchor AFTER the advance and a night crossed on that very
    // first turn would be missed.
    _dreamService.checkRollover(
      sessionId: _session.currentSessionId,
      dayCount: _timeService.dayCount,
    );
    final parkedDream = _dreamService.takePrefetch(_session.currentSessionId);
    if (parkedDream != null) {
      try {
        final dream = await parkedDream.dream;
        if (_sceneChanged(sessionToken)) return;
        if (dream != null) {
          _session.messages.insert(
            _session.messages.length - 1,
            ChatMessage(
              text: dream,
              sender: parkedDream.ownerName,
              isUser: false,
              characterId: parkedDream.ownerCharacterId,
              metadata: {'is_dream': true},
            ),
          );
          notifyListeners();
          await _journalStore.addCard(
            sessionId: sessionToken!,
            characterId: parkedDream.ownerId,
            content: dream,
            category: 'moment',
            kind: 'dream',
            emotionLabel: _characterEmotion.isEmpty ? null : _characterEmotion,
            storyDay: _timeService.dayCount,
            storyClock: _timeService.storyClockIso,
            maxCards: _storageService.memorySettings.journalMaxCards,
          );
          await _saveChat();
        }
      } catch (e) {
        debugPrint('[Dreams] skipped: $e');
      }
    }

    // ── Blind-model photo fallback: caption BEFORE generating ───────────────
    // Vision-capable models return true immediately (their pixels ride along
    // and their caption runs post-turn); blind models run the offline
    // captioner so this turn's history already carries the gist. Returns false
    // when the scene changed during the (multi-second) caption await — abort
    // rather than run decay/realism/generation against a newly loaded chat.
    if (imagePath != null) {
      final stillHere = await mediaDoor.runBlindPhotoCaption(
        userMsg,
        imagePath,
        sessionToken,
      );
      if (!stillHere) return;
    }

    // Reset the idle timer — user is interacting
    _cancelIdleTimer();

    // Clear the new chat flag after first user message to allow memory retrieval
    if (_isNewChat) {
      _isNewChat = false;
      debugPrint('[sendMessage] Cleared new chat flag, memories now allowed');
    }

    // {{idle_duration}} clock: the user just spoke.
    _lastUserMessageAt = DateTime.now();

    // Scan for lore keywords (thin to scanner; the user message is already
    // in _session.messages, so the scanner windows over recent history from there).
    _lorebookScanner.scanLatest();

    // ── Clear consumed chaos event from the previous turn ───────────────
    // Only clear if the event was already delivered in a response.
    // This preserves manual-spin events that haven't been used yet.
    // Delegated to service (core state moved). PR 5b: the same clear per
    // member's parked event — delivered ones rode THEIR regen, not a
    // stranger's.
    _chance.clearDeliveredPendingsAllOwners();
    // Clear Mafia force-ack only after a prior turn *showed* it and the user
    // is now continuing (regen of that AI reply still re-injects until here).
    unawaited(_porchMemoryImport.clearAfterAcceptedUserTurn());

    // ── Direct-address turn routing (both cast surfaces) ─────────────────
    // 1:1: "@Evelyn …" anywhere (or a vocative — "Evelyn - can you clarify…")
    // routes this turn to the GUEST via the parity-safe guest path; the host
    // turn and its prep below (chaos tick/wheel, decay, pre-gen eval) are
    // skipped — guests carry ZERO Realism/Needs, the host simply didn't take
    // a turn. Fixes the "responds twice per message" Discord report
    // (2026-07-28). Group: "@Member" forces that member as this turn's
    // speaker (inside the call; returns null — the turn proceeds normally).
    // Decision logic lives in the scene-guest leaf.
    final addressedGuest = _directAddressRoutedGuest(
      AtMentionText.routingText(userMsg),
    );

    // ── Chaos Mode: check + pause for wheel if triggered ─────────────────
    // 1:1 rolls the chat's own gauge, exactly as always. A group turn
    // belongs to ONE member (PR 5b): the gate resolves the pinned
    // upcoming speaker and ticks, rolls and parks THEIR gauge and wheel —
    // a chaos-off owner ticks nobody, and a parked event for another
    // member never rides this turn (Error Book: the tick-that-hit-everyone
    // trap, scoped here and in the injection, not just the UI).
    final chaosGate = addressedGuest == null
        ? _chance.chaosGateForTurn()
        : null;
    if (chaosGate != null) {
      final gateBag = chaosGate.bag;
      final fires = gateBag == null
          ? checkAndTickChaosPressure()
          : _chaosModeService.checkAndTickMember(gateBag);
      if (fires) {
        // Create a completer so sendMessage pauses here until the wheel resolves
        _chance.completer = Completer<void>();
        _chance.pendingTrigger = true;
        // Pre-pick the one event the web/mobile reveal modal shows + accepts
        // (the desktop spins its own wheel instead — same pool, same accept).
        final webWheel = spinWheelEvents(memberBag: gateBag);
        _chance.webEvent = webWheel.isNotEmpty
            ? webWheel.first
            : 'Fate intervenes in an unexpected way.';
        _chance.webName = chanceTimeSpeakerName;
        notifyListeners(); // UI observes this to show the wheel
        // Wait for the user to spin + accept fate (completes in applyChanceTimeResult)
        await _chance.completer!.future;
        _chance.completer = null;
        _chance.webEvent = null;
        _chance.webName = null;
      }
    }

    // Note: depth decrement happens after AI response completes (see _generateResponse finalization).
    // This ensures lore triggered by the user message is visible in the current turn's prompt.

    // Voice call safe speed lane: swap to the fast call model BEFORE the
    // pre-generation work below, so the objective check, the realism judges
    // and the time eval all answer on it — not just the reply. The
    // helper self-gates (call mode + remote + a call model picked); guests
    // are excluded because a routed guest turn skips the host prep entirely.
    // The request phase adopts the swap into the turn's restore machinery;
    // the cancel return below and the callMode setter release an orphaned one.
    if (addressedGuest == null) _enterCallEvalModelSwap();

    // ── The player's time skip ──────────────────────────────────────────
    // PoT is the only clock driver. The skip reader reads the line (or a
    // `/skip` says it exactly) whenever the story clock is live, engine
    // on or off, before anything scores or answers it, and after the call
    // model swap so a voice call reads it on the fast model too.
    if (_clockRunning) {
      final before = _timeService.clock;
      final skipped = await _buildPlayerSkip().apply(
        outbound,
        exact: skipTag.verdict,
        recent: recentExchange(
          _session.messages.sublist(0, _session.messages.length - 1),
          take: 4,
        ),
        stale: () => _sceneChanged(sessionToken),
        ask: (question) => _askSkip(question, sessionToken),
      );
      if (_sceneChanged(sessionToken)) {
        _exitCallEvalModelSwap();
        return;
      }
      await realism.episodeCrumbs.maybeMint(before, _timeService.clock);
      // A day or more (this line, or the calendar since the last turn):
      // settle the moment the scene left; a skip line also gets the
      // narrator to fill in the gap before anyone replies.
      if (_timeService.bodyBeatLivedOwed) {
        LongSkipSettle(_realismScope()).settle();
      }
      if (skipped >= kLongSkipMinutes) {
        final stillHere = await _bridgeLongSkip(
          from: before,
          skipped: skipped,
          skipLine: userMsg,
          token: sessionToken,
        );
        if (!stillHere) {
          _exitCallEvalModelSwap();
          return;
        }
      }
    } else if (skipTag.present) {
      _setGuestStatus(kSkipNeedsClock, isError: true);
    }

    // Check objective task completion BEFORE generating response
    // so the AI gets the updated task in its prompt
    await _maybeCheckTaskCompletionSync();

    await _s.handoff.sendDecayAndGenerate(
      addressedGuest: addressedGuest,
      userMsg: userMsg,
      imagePath: imagePath,
      sessionToken: sessionToken,
      forcedWebQuery: lookup.accepted ? lookup.webQuery : null,
      forcedWikiQuery: lookup.accepted ? lookup.wikiQuery : null,
    );
  }
}
