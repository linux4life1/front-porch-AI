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
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

/// Scene Guest lifecycle: the status banner, the single add-with-status
/// entry point, background portraits, the guest turn, the shared "enter"
/// tail, the `/exit` undo record, and who authored a message.
///
/// Scene Guests are 1:1-only and their turns carry NO Realism/Needs work
/// (the `guestSpeaker == null` guards in generation), so this cluster is
/// parity-safe by construction. Joins and the 1:1 to group conversion are
/// in [GuestJoin].
class GuestFlow {
  GuestFlow(this._door, this._d);

  final CastDoor _door;
  final CastDeps _d;

  /// Every Scene Guest field (ids, cards, banner, undo, detection).
  final SceneGuestState state = SceneGuestState();

  /// Guests may chime in on their own after a host turn.
  bool autoChimeEnabled = true;

  /// The last message when the user stopped a reply from the Realism
  /// overlay. The "you stopped this reply" notice shows while it is still
  /// the chat's last message (same anchor rule as ActionsDoor's suggestions).
  ChatMessage? stoppedReplyAnchor;

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();

  /// True when [m] was authored by a Scene Guest rather than the host,
  /// decided by the stable characterId stamped at guest-turn time, NOT by
  /// live scene membership or sender name. Stays correct after the guest has
  /// `/exit`-ed and when a guest shares the host's display name.
  /// Host/user/system/group messages are false.
  bool isGuestAuthoredMessage(ChatMessage m) {
    if (_session.activeGroup != null || m.isUser || m.sender == 'System') {
      return false;
    }
    final cid = m.characterId;
    if (cid == null || cid.isEmpty) return false; // legacy / host-authored
    final hostId = _session.activeCharacter != null
        ? _d.characterIdFor(_session.activeCharacter!)
        : null;
    return cid != hostId;
  }

  /// The PRESENT Scene Guest card that authored [m] (to regenerate/swipe
  /// as), or null when [m] is host-authored OR the authoring guest has left.
  /// Use [isGuestAuthoredMessage] to tell "host" from "departed guest".
  CharacterCard? sceneGuestForMessage(ChatMessage m) {
    if (!isGuestAuthoredMessage(m)) return null;
    final cid = m.characterId;
    for (final g in state.cards) {
      if (_d.characterIdFor(g) == cid) return g;
    }
    return null; // authored by a guest who is no longer present
  }

  /// Direct-address routing for BOTH cast surfaces, called once per user
  /// turn from `sendMessage`.
  ///
  /// **Group mode:** an explicit "@Member" forces that member as this turn's
  /// speaker through the same one-shot override the group UI's manual pick
  /// uses, so the per-speaker realism dance follows the pick exactly as it
  /// always has. The turn proceeds normally, so this returns null. Not gated
  /// on [autoChimeEnabled] (a 1:1 guest-chime preference).
  ///
  /// **1:1 with Scene Guests:** returns the guest the line directly addresses
  /// ("@Evelyn …" or a vocative); `sendMessage` then runs the guest's
  /// parity-safe turn INSTEAD of the host turn. Gated on [autoChimeEnabled]
  /// inside the director: chime-ins off means guests speak only via /speak.
  CharacterCard? directAddressRoutedGuest(String promptText) {
    if (_session.activeGroup != null) {
      final target = SceneGuestDirector.atMentionedCard(
        _session.groupCharacters,
        promptText,
      );
      if (target != null) _door.away.releaseHeldAway(target);
      if (target != null && !_h.groupSpeakerSkips(target)) {
        debugPrint(
          '[Cast] @-mention: ${target.name} forced as this turn\'s speaker.',
        );
        _h.setNextCharacter(target);
      }
      return null;
    }
    if (state.cards.isEmpty) return null;
    final guest = _h.guestDirector().directlyAddressedGuest(promptText);
    if (guest != null) {
      debugPrint(
        '[SceneGuest] User addressed ${guest.name} directly — '
        'routing this turn to the guest (host turn skipped).',
      );
    }
    return guest;
  }

  /// The one Scene Guest "enter" tail: register the guest's dbId,
  /// re-resolve the cards, persist, then have the guest speak its entrance
  /// through the parity-safe guest-turn path. Shared by `/create`, `/join`
  /// and the cast-detection accept flow.
  Future<void> enterSceneGuest(CharacterCard guest, {bool speak = true}) async {
    if (guest.dbId != null) state.ids.add(guest.dbId!);
    await resolveSceneGuestCards();
    await _d.saveChat();
    if (speak) await generateGuestTurn(guest);
  }

  /// Update the transient status line (the inline banner). [sticky] keeps it
  /// until the next update (in-progress steps); otherwise it auto-clears
  /// after a few seconds (errors linger a little longer).
  void setStatus(String? msg, {bool isError = false, bool sticky = false}) {
    state.statusClearTimer?.cancel();
    state.statusClearTimer = null;
    // The banner draws its own warning icon, so a '⚠' lead-in would show
    // twice; it still marks the line as an error.
    if (msg != null && msg.startsWith('⚠')) {
      msg = msg.substring(1).trimLeft();
      isError = true;
    }
    state.activityStatus = msg;
    state.activityIsError = isError;
    _d.notify();
    if (msg != null && !sticky) {
      state.statusClearTimer = Timer(Duration(seconds: isError ? 6 : 3), () {
        state.activityStatus = null;
        state.activityIsError = false;
        _d.notify();
      });
    }
  }

  /// The Realism overlay's Stop button ended the turn. A kept reply gets the
  /// short status line; a turn left with no reply gets [stoppedReplyNotice],
  /// which stays until the chat moves on. A greeting read gets neither.
  void noteStoppedReply({required bool replyKept}) {
    if (replyKept) {
      setStatus('Reply kept. Scene time and needs weren\'t updated.');
    } else if (_d.graph().evalStatus.evaluating &&
        _session.messages.isNotEmpty) {
      stoppedReplyAnchor = _session.messages.last;
    }
  }

  /// Plain words for a reply the user stopped before it was written; null
  /// when there is none. Gone once anything follows the line it was stopped
  /// on, another chat opens, Try again starts, or the user dismisses it.
  String? get stoppedReplyNotice {
    final anchor = stoppedReplyAnchor;
    if (anchor == null || _session.messages.isEmpty) return null;
    if (!identical(_session.messages.last, anchor)) return null;
    return 'You stopped this reply before it was written.';
  }

  /// Try again regenerates the trailing user line, so it is offered only
  /// while the chat still ends on one.
  bool get canRetryStoppedReply =>
      stoppedReplyNotice != null && _session.messages.last.isUser;

  void dismissStoppedReplyNotice() {
    if (stoppedReplyAnchor == null) return;
    stoppedReplyAnchor = null;
    _d.notify();
  }

  /// Clear the transient banner/busy/evict state. Called at every reset
  /// site (context switch, new chat, group) and on dispose so nothing leaks
  /// across chats. Does not notify (callers already do).
  void resetActivityState() {
    state.statusClearTimer?.cancel();
    state.statusClearTimer = null;
    state.activityStatus = null;
    state.activityIsError = false;
    state.busy = false;
    state.avatarEvictPath = null;
    clearExitUndo();
  }

  /// Capture undo state right after a `/exit` departure turn finished. The
  /// just-generated host message (if any) is the departure to delete on undo.
  void armExitUndo(CharacterCard guest) {
    final departure =
        (_session.messages.isNotEmpty &&
            !_session.messages.last.isUser &&
            _session.messages.last.sender != 'System')
        ? _session.messages.last
        : null;
    state.exitUndoGuest = guest;
    state.exitUndoMessage = departure;
    state.exitUndoOfferName = guest.name;
    state.exitUndoUserStep = false; // UNDO now means this exit
    _d.notify();
  }

  void clearExitUndo() {
    state.exitUndoGuest = null;
    state.exitUndoMessage = null;
    state.exitUndoOfferName = null;
    state.exitUndoName = null;
    state.exitUndoUserStep = false;
    // A pending full-member exit cleared WITHOUT committing (context switch,
    // new chat) is cancelled: the member's row was never deleted, so they
    // stay. The send path commits the pending exit before this.
    state.pendingMemberExit = null;
  }

  /// Single entry point for adding a Scene Guest with a busy guard and one
  /// live, in-place status line. Used by `/create`, `/join`, the picker and
  /// cast-detection accept. [existing] joins a library card directly;
  /// otherwise [mint] generates one first. A portrait starts after the
  /// guest enters.
  Future<void> addGuestWithStatus({
    required String displayName,
    CharacterCard? existing,
    Future<GuestMintResult> Function(void Function(String step) onStatus)? mint,
  }) async {
    // Don't race another creation OR an in-flight turn (the mint runs a
    // separate LLM call that doesn't set the generating flag).
    if (state.busy || _turn.isTurnBusy) {
      setStatus('Busy — try again in a moment.', isError: true);
      return;
    }
    // Reject a duplicate name when MINTING (join already excludes anyone
    // present): two same-named guests make /exit, chime-in targeting and
    // the host "do not voice" line ambiguous.
    if (existing == null && _door.roster.sceneNameTaken(displayName)) {
      setStatus('"$displayName" is already in the scene.', isError: true);
      return;
    }
    final token = _session.currentSessionId;
    state.busy = true;
    _d.notify();
    try {
      CharacterCard card;
      if (existing != null) {
        card = existing;
        setStatus('${card.name} is joining the scene…', sticky: true);
      } else {
        setStatus('Creating "$displayName"…', sticky: true);
        // Each generation sub-step ("$name · Running interview…") shows, so
        // the banner reflects progress instead of one static spinner.
        final result = await mint!((step) {
          if (_door.sceneChanged(token)) return; // not into another chat
          setStatus('$displayName · $step', sticky: true);
        });
        if (_door.sceneChanged(token)) return; // switched mid-generation
        if (!result.ok) {
          setStatus(
            'Couldn’t create "$displayName": ${result.error}',
            isError: true,
          );
          return;
        }
        card = result.card!;
      }
      setStatus('${card.name} is making an entrance…', sticky: true);
      if (_session.activeGroup != null) {
        await _door.roster.addLiteMemberToGroup(card);
      } else {
        await enterSceneGuest(card);
      }
      if (_door.sceneChanged(token)) return; // switched during the entrance
      setStatus('${card.name} joined the scene'); // auto-clears
      _maybeGenerateGuestPortrait(card); // background; never blocks entrance
    } finally {
      // Only clear busy if we still own this scene: a context switch already
      // reset it (and may have started new work we must not clobber).
      if (!_door.sceneChanged(token)) {
        state.busy = false;
        _d.notify();
      }
    }
  }

  /// Background portrait for a freshly added guest: with an image backend,
  /// generate art from the card's description, write it onto the guest's
  /// card PNG, then signal the UI to refresh that avatar. Fire-and-forget,
  /// ZERO Realism/Needs.
  void _maybeGenerateGuestPortrait(CharacterCard card) {
    final igs = _d.imageGen();
    final cardPath = card.imagePath;
    final desc = card.description.trim();
    if (igs == null || !igs.isConfigured) return;
    if (cardPath == null || cardPath.isEmpty || desc.isEmpty) return;
    final prompt = desc.length > 500 ? desc.substring(0, 500) : desc;
    final token = _session.currentSessionId;
    final dbId = card.dbId;
    unawaited(() async {
      String? tmpPath;
      try {
        final bytes = await igs.generateImage(prompt: prompt, isPortrait: true);
        if (bytes == null || bytes.isEmpty) return;
        // Image gen is slow: no art for a guest that has since left or had
        // its card deleted, or into a chat the user already left.
        if (_door.sceneChanged(token)) return;
        if (dbId != null && !state.ids.contains(dbId)) return;
        // saveCardAsPng takes a SOURCE IMAGE PATH, so stage the art to a
        // per-invocation temp file, then bake it in.
        tmpPath = path.join(
          Directory.systemTemp.path,
          'fp_guest_portrait_${dbId ?? card.name.hashCode}_'
          '${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await File(tmpPath).writeAsBytes(bytes);
        await V2CardService().saveCardAsPng(card, cardPath, tmpPath);
        if (_door.sceneChanged(token)) return; // re-check after the write
        state.avatarEvictPath = cardPath; // UI evicts the stale cached image
        _d.notify();
      } catch (e) {
        debugPrint('[SceneGuest] portrait generation failed: $e');
      } finally {
        if (tmpPath != null) {
          try {
            final f = File(tmpPath);
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }
      }
    }());
  }

  /// Force a present Scene Guest to take a turn NOW (the `/speak` macro),
  /// bypassing the chime-in heuristic. Busy-guarded like the create flow
  /// and context-guarded so a chat switch cannot leave `busy` stuck.
  Future<void> speakGuestNow(CharacterCard guest) async {
    if (_session.activeGroup != null) return;
    if (_turn.isTurnBusy || state.busy) {
      setStatus('Busy — try again in a moment.', isError: true);
      return;
    }
    final token = _session.currentSessionId;
    state.busy = true;
    _d.notify();
    try {
      await generateGuestTurn(guest);
    } finally {
      if (!_door.sceneChanged(token)) {
        state.busy = false;
        _d.notify();
      }
    }
  }

  /// A turn spoken by a Scene Guest inside a 1:1, through the normal engine
  /// with the guest as speaker and NO Realism/Needs work. Guest growth rides
  /// the shared growth pass. The exchange then embeds under the GUEST's own
  /// id (episodic memory), fire-and-forget.
  Future<void> generateGuestTurn(CharacterCard guest) async {
    await _turn.generate(GenerationMode.normal, guestSpeaker: guest);
    _turn.side.maybeEmbedMessages(
      characterIdOverride: _d.characterIdFor(guest),
    );
  }

  /// Re-resolve the guest cards from the guest ids. Called whenever the id
  /// list changes or on session load; drops ids that no longer resolve.
  ///
  /// A guest is NOT scenario-stripped on its shared library card here
  /// (the repository hands back its live reference); the scenario is blanked
  /// only in the prompt at guest-turn time.
  Future<void> resolveSceneGuestCards() async {
    if (_h.disposed()) return;
    final repo = _d.characters();
    if (repo == null) return;
    // Never two passes at once: each awaits per-id reads then mutates the
    // shared lists. Concurrent requests coalesce into one trailing re-run.
    if (state.resolving) {
      state.resolvePending = true;
      return;
    }
    final token = _session.currentSessionId;
    state.resolving = true;
    try {
      do {
        state.resolvePending = false;
        final resolved = <CharacterCard>[];
        final validIds = <String>[];
        for (final id in List<String>.from(state.ids)) {
          if (_door.sceneChanged(token)) {
            return; // disposed or chat switched mid-pass
          }
          final card = await repo.getCharacterCardById(id);
          if (card != null) {
            resolved.add(card);
            validIds.add(id);
          }
        }
        if (_door.sceneChanged(token)) return;
        state.ids
          ..clear()
          ..addAll(validIds);
        state.cards
          ..clear()
          ..addAll(resolved);
        _d.notify();
      } while (state.resolvePending && !_h.disposed());
    } finally {
      state.resolving = false;
    }
  }
}
