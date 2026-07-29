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

/// Scene Guest turn/status lifecycle: authorship resolution, the shared "enter"
/// tail, the transient status banner, the single add-with-status entry point,
/// background portrait generation, and the parity-safe guest-turn path
/// (speakGuestNow / generateGuestTurn). Extracted verbatim from the god file
/// (zero behaviour change). Scene Guests are 1:1-only and their turns carry NO
/// Realism/Needs work (guarded by `guestSpeaker == null` in _generateResponse),
/// so this whole cluster is parity-safe by construction. The 1:1->group
/// conversion path (joinFull / promoteSceneToFull / _convertOneToOneToGroup)
/// and all guest state fields deliberately remain in chat_service.dart.
extension ChatServiceSceneGuest on ChatService {
  /// Resolve the Scene Guest card that authored message [m], or null when [m] is
  /// a host / group / system / user message. Used by regenerate + swipe so a
  /// guest message stays a parity-safe GUEST turn (no Realism/Needs, spoken as
  /// the guest) instead of being regenerated as the host. Guests are 1:1-only,
  /// so this is always null in group mode.
  /// True when [m] was authored by a Scene Guest rather than the host — decided
  /// by the stable characterId stamped at guest-turn time, NOT by live scene
  /// membership or sender name. Stays correct after the guest has `/exit`-ed and
  /// when a guest shares the host's display name (the name fallback previously
  /// here could misclassify a host message as a guest's). Host/user/system/group
  /// messages → false.
  bool _isGuestAuthoredMessage(ChatMessage m) {
    if (_activeGroup != null || m.isUser || m.sender == 'System') return false;
    final cid = m.characterId;
    if (cid == null || cid.isEmpty) return false; // legacy / host-authored
    final hostId = _activeCharacter != null
        ? _getCharacterIdFromCard(_activeCharacter!)
        : null;
    return cid != hostId;
  }

  /// The PRESENT Scene Guest card that authored [m] (to regenerate/swipe as), or
  /// null when [m] is host-authored OR the authoring guest has left the scene.
  /// Use [_isGuestAuthoredMessage] to tell "host" apart from "departed guest".
  CharacterCard? _sceneGuestForMessage(ChatMessage m) {
    if (!_isGuestAuthoredMessage(m)) return null;
    final cid = m.characterId;
    for (final g in _sceneGuestCards) {
      if (_getCharacterIdFromCard(g) == cid) return g;
    }
    return null; // authored by a guest who is no longer present
  }

  /// Direct-address routing for BOTH cast surfaces, called once per user turn
  /// from `sendMessage`:
  ///
  /// **Group mode:** an explicit "@Member" anywhere in the line forces that
  /// member as this turn's speaker via [setNextCharacter] — the SAME one-shot
  /// override the group UI's manual pick uses, so the per-speaker realism
  /// dance and objectives switch follow the pick exactly as they always have
  /// (parity by reuse, zero new realism surface). The turn itself proceeds
  /// normally, so this returns null. Not gated on autoChimeEnabled (that flag
  /// is a 1:1 guest-chime preference; forcing a group speaker is core group
  /// UX, same as tapping the member card).
  ///
  /// **1:1 with Scene Guests:** returns the guest the user's line directly
  /// addresses ("@Evelyn …" anywhere, or a vocative — see
  /// [SceneGuestDirector.directlyAddressedGuest]); `sendMessage` then runs
  /// the guest's parity-safe turn INSTEAD of the host turn. Gated on
  /// autoChimeEnabled inside the director on purpose: auto-chime OFF means
  /// "guests speak only via /speak", so routing must not fire either — and
  /// with chime-ins off the double-response this fixes cannot occur.
  CharacterCard? _directAddressRoutedGuest(String promptText) {
    if (_activeGroup != null) {
      final target = SceneGuestDirector.atMentionedCard(
        _groupCharacters,
        promptText,
      );
      if (target != null) {
        debugPrint(
          '[Cast] @-mention: ${target.name} forced as this turn\'s speaker.',
        );
        setNextCharacter(target);
      }
      return null;
    }
    if (_sceneGuestCards.isEmpty) return null;
    final guest = _ensureSceneGuestDirector().directlyAddressedGuest(
      promptText,
    );
    if (guest != null) {
      debugPrint(
        '[SceneGuest] User addressed ${guest.name} directly — '
        'routing this turn to the guest (host turn skipped).',
      );
    }
    return guest;
  }

  /// Generate a turn spoken by a Scene Guest (Lite NPC) inside a 1:1 chat.
  ///
  /// Reuses the normal generation engine with the guest as the speaker. Carries
  /// NO Realism Engine / Needs work (the guest turn is parity-safe — see the
  /// `guestSpeaker == null` guards in `_generateResponse`). Guest growth rides
  /// the shared growth pass (resolvePassOwners includes 1:1 guests who spoke
  /// in the window) — there is no per-guest trigger.
  ///
  /// Common Scene Guest "enter" tail: register the guest's dbId, re-resolve the
  /// resolved-card list, persist the session, then have the guest speak its
  /// entrance via the parity-safe guest-turn path. Shared by `/create`,
  /// `/join`, and the cast-detection accept flow so there is exactly ONE enter
  /// path (no duplicated add/resolve/save/generate logic).
  Future<void> _enterSceneGuest(CharacterCard guest) async {
    if (guest.dbId != null) _sceneGuestIds.add(guest.dbId!);
    await _resolveSceneGuestCards();
    await _saveChat();
    await generateGuestTurn(guest);
  }

  /// Update the transient Scene Guest status line (the inline banner). [sticky]
  /// keeps it shown until the next update (for in-progress steps); otherwise it
  /// auto-clears after a few seconds (errors linger a little longer).
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) {
    _guestStatusClearTimer?.cancel();
    _guestStatusClearTimer = null;
    _guestActivityStatus = msg;
    _guestActivityIsError = isError;
    notifyListeners();
    if (msg != null && !sticky) {
      _guestStatusClearTimer = Timer(Duration(seconds: isError ? 6 : 3), () {
        _guestActivityStatus = null;
        _guestActivityIsError = false;
        notifyListeners();
      });
    }
  }

  /// Clear the transient Scene Guest banner/busy/evict state. Called at every
  /// scene-guest reset site (context switch / new chat / group) and on dispose
  /// so nothing leaks across chats. Does not notify (callers already do).
  void _resetGuestActivityState() {
    _guestStatusClearTimer?.cancel();
    _guestStatusClearTimer = null;
    _guestActivityStatus = null;
    _guestActivityIsError = false;
    _guestBusy = false;
    _guestAvatarEvictPath = null;
    _clearExitUndo();
  }

  /// Single entry point for adding a Scene Guest with a busy guard + one live,
  /// in-place status line (no saved 'System' chat-message litter). Used by
  /// `/create`, `/join`, the picker, and cast-detection accept. [existing] joins
  /// a library card directly; otherwise [mint] generates one first. A background
  /// portrait kicks off after the guest enters.
  Future<void> _addGuestWithStatus({
    required String displayName,
    CharacterCard? existing,
    Future<GuestMintResult> Function(void Function(String step) onStatus)? mint,
  }) async {
    // Don't race another creation OR an in-flight turn (the mint runs a separate
    // LLM call that doesn't set _isGenerating).
    if (_guestBusy || _isGenerating) {
      _setGuestStatus('Busy — try again in a moment.', isError: true);
      return;
    }
    // Reject a duplicate name when MINTING a new guest (join already excludes
    // anyone present). Two same-named guests make /exit, chime-in targeting, and
    // the host "do not voice: X, X" injection ambiguous.
    if (existing == null) {
      final wanted = displayName.trim().toLowerCase();
      if (_sceneGuestCards.any((g) => g.name.trim().toLowerCase() == wanted)) {
        _setGuestStatus(
          '"$displayName" is already in the scene.',
          isError: true,
        );
        return;
      }
    }
    final token = _currentSessionId;
    _guestBusy = true;
    notifyListeners();
    try {
      CharacterCard card;
      if (existing != null) {
        card = existing;
        _setGuestStatus('${card.name} is joining the scene…', sticky: true);
      } else {
        _setGuestStatus('Creating "$displayName"…', sticky: true);
        // Surface each generation sub-step ("$name · Running interview…") so the
        // banner reflects progress instead of one static spinner.
        final result = await mint!((step) {
          if (_sceneChanged(token)) return; // don't paint into another chat
          _setGuestStatus('$displayName · $step', sticky: true);
        });
        if (_sceneChanged(token)) return; // user switched chats mid-generation
        if (!result.ok) {
          _setGuestStatus(
            'Couldn’t create "$displayName": ${result.error}',
            isError: true,
          );
          return;
        }
        card = result.card!;
      }
      _setGuestStatus('${card.name} is making an entrance…', sticky: true);
      await _enterSceneGuest(card);
      if (_sceneChanged(token)) return; // switched during the entrance turn
      _setGuestStatus('${card.name} joined the scene'); // auto-clears
      _maybeGenerateGuestPortrait(
        card,
      ); // background; never blocks the entrance
    } finally {
      // Only clear busy if we still own this scene — a context switch already
      // reset it (and may have started new work we must not clobber).
      if (!_sceneChanged(token)) {
        _guestBusy = false;
        notifyListeners();
      }
    }
  }

  /// Background portrait for a freshly-added guest: if an image backend is
  /// configured, generate art from the card's description and write it onto the
  /// guest's card PNG, then signal the UI to refresh that avatar. Fire-and-forget
  /// — the guest is already in the scene with an initials avatar; this just fills
  /// the art in when ready. ZERO Realism/Needs. No-op without an image backend.
  void _maybeGenerateGuestPortrait(CharacterCard card) {
    final igs = _imageGenService;
    final cardPath = card.imagePath;
    final desc = card.description.trim();
    if (igs == null || !igs.isConfigured) return;
    if (cardPath == null || cardPath.isEmpty || desc.isEmpty) return;
    final prompt = desc.length > 500 ? desc.substring(0, 500) : desc;
    final token = _currentSessionId;
    final dbId = card.dbId;
    unawaited(() async {
      String? tmpPath;
      try {
        final bytes = await igs.generateImage(prompt: prompt, isPortrait: true);
        if (bytes == null || bytes.isEmpty) return;
        // Image gen is slow: don't bake art for a guest that has since left the
        // scene / had its card deleted, or into a chat the user already left.
        if (_sceneChanged(token)) return;
        if (dbId != null && !_sceneGuestIds.contains(dbId)) return;
        // saveCardAsPng takes a SOURCE IMAGE PATH (not bytes), so stage the
        // generated art to a per-invocation temp file (unique so two portrait
        // generations can't corrupt each other mid-write), then bake it in.
        tmpPath = path.join(
          Directory.systemTemp.path,
          'fp_guest_portrait_${dbId ?? card.name.hashCode}_'
          '${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await File(tmpPath).writeAsBytes(bytes);
        await V2CardService().saveCardAsPng(card, cardPath, tmpPath);
        if (_sceneChanged(token)) return; // re-check after the slow write
        _guestAvatarEvictPath = cardPath; // UI evicts the stale cached image
        notifyListeners();
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
  /// bypassing the auto chime-in heuristic + LLM gate. Parity-safe — it runs the
  /// same `generateGuestTurn` (zero Realism/Needs). Busy-guarded like the create
  /// flow so it can't race a user turn / another guest creation, and
  /// context-guarded so a chat switch mid-turn can't leave `_guestBusy` stuck.
  Future<void> speakGuestNow(CharacterCard guest) async {
    if (_activeGroup != null) return;
    if (_isGenerating || _guestBusy) {
      _setGuestStatus('Busy — try again in a moment.', isError: true);
      return;
    }
    final token = _currentSessionId;
    _guestBusy = true;
    notifyListeners();
    try {
      await generateGuestTurn(guest);
    } finally {
      if (!_sceneChanged(token)) {
        _guestBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> generateGuestTurn(CharacterCard guest) async {
    await _generateResponse(GenerationMode.normal, guestSpeaker: guest);
    // Guest growth rides the shared growth pass (resolvePassOwners includes
    // 1:1 guests who spoke in the window) — no per-guest trigger needed.
    // Phase 4: give the guest EPISODIC MEMORY. The host's embed stays gated
    // behind `guestSpeaker == null` in `_generateResponse`; here we embed the
    // just-finished exchange under the GUEST's own id (the same id the guest
    // retrieves under in `_getMemorySourceIds`) by REUSING the host embed path.
    // Fire-and-forget; ZERO Realism/Needs. So a later guest turn — even in a
    // different chat — recalls what happened.
    _maybeEmbedMessages(characterIdOverride: _getCharacterIdFromCard(guest));
  }
}
