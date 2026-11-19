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
import 'package:front_porch_ai/services/chat/cast_detector.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';

/// Scene Guests (Lite NPCs): every field the feature owns, in one place.
///
/// Persistent guest characters added to a 1:1 scene. They are real library
/// characters that speak in their own bubble via the existing generation
/// engine but carry NO Realism Engine / Needs state (parity-safe). Stored as
/// dbIds inside the session's `groupRealismState` column (always '{}' for
/// plain 1:1 sessions) so no schema change is needed. Group sessions never use
/// these.
///
/// WHY THIS IS A STATE OBJECT AND NOT A SERVICE: the behaviour already lives
/// in `chat_service_scene_guest.dart`, `chat_service_cast.dart` and
/// `chat_service_guest_flow.dart` — parts of the ChatService library that read
/// and write these fields directly. Only the DECLARATIONS moved. Dart parts
/// cannot add fields to a class declared elsewhere, so an extension could
/// never have carried them; a plain holder is the one shape that gets ~150
/// lines out of the shell without changing a single line of logic.
///
/// The public switches `autoChimeEnabled` and `sceneDetectionEnabled` stay on
/// ChatService itself: they are part of its public surface, which
/// `FakeChatService implements ChatService` has to satisfy, and moving public
/// members off the class is exactly the dispatch trap documented in
/// CLAUDE.md's ChatService section.
class SceneGuestState {
  /// Guest dbIds and their resolved cards, in roster order.
  final List<String> ids = [];
  final List<CharacterCard> cards = [];

  /// A one-shot departure instruction consumed by the NEXT primary 1:1
  /// generation so the active character narrates the guest leaving. Set by
  /// `/exit`, cleared after a single injection.
  String? pendingDeparture;

  // ── Cast-chip queue hold (1:1) ─────────────────────────────────────────
  // The Scene Guest the cast chip's Next pill holds to answer the NEXT
  // user message — the promise an `@name` makes, made by a tap instead.
  // Keyed by guest dbId; a guest who leaves takes their promise with
  // them (resolution drops an id no longer in the scene). Null = the
  // host answers, which is the default. Group chats queue in
  // GroupTurnManager, not here.

  void queueHold(CharacterCard card, {String? hostDbId}) {
    nextQueuedSpeakerId = card.dbId != null &&
            card.dbId != hostDbId &&
            cards.any((c) => c.dbId == card.dbId)
        ? card.dbId
        : null;
  }

  /// The held guest, or null (host answers). Resolving drops a stale id.
  CharacterCard? resolveHold() {
    final id = nextQueuedSpeakerId;
    if (id == null) return null;
    final guest = cards.where((c) => c.dbId == id).firstOrNull;
    if (guest == null) nextQueuedSpeakerId = null;
    return guest;
  }

  /// Consume the hold: the next send honors it, however that turn routes.
  /// The spent promise does not survive to a third line.
  CharacterCard? takeHold() {
    final guest = resolveHold();
    nextQueuedSpeakerId = null;
    return guest;
  }

  String? nextQueuedSpeakerId;

  /// A pending request to open the Scene Guest picker (the `/join` flow).
  /// Holds the initial search filter ('' = show everyone); null = no picker
  /// pending. Surfaced to the chat UI exactly like [pendingDetection] — set +
  /// clear with notifyListeners; the page observes it and shows it once.
  String? pendingPickerFilter;
  bool pendingPickerFull = false;

  /// Transient one-line status for the create/join flow, shown as an inline
  /// banner above the input and NEVER saved to chat history (it replaced
  /// per-step 'System' chat messages that both littered the scene and were
  /// persisted into it). Updated in place across the steps, then auto-clears.
  String? activityStatus;
  bool activityIsError = false;
  Timer? statusClearTimer;

  /// True while a guest is being created/entered. The mint runs a separate LLM
  /// call that does NOT set `_isGenerating`, so this is the guard that blocks a
  /// user message (or regen/swipe) from racing the in-flight guest creation.
  bool busy = false;

  /// Set when a guest's background portrait was just written to its card PNG,
  /// so the UI can evict that path from the image cache and show the new art
  /// (the image cache lives in the widget layer; this service is
  /// foundation-only).
  String? avatarEvictPath;

  // ── /exit undo ──────────────────────────────────────────────────────────
  // After `/exit`, a brief UNDO is offered: delete the generated departure
  // message (reverting its host realism via deleteMessage's time-travel
  // rollback) and re-add the guest. Their evolution counts + RAG memory are
  // NOT cleared by exit, so re-adding the id restores full context. The offer
  // is consumed by the UI (one SnackBar) but the undo data stays valid until
  // the user sends a real message / switches chats.
  CharacterCard? exitUndoGuest;
  ChatMessage? exitUndoMessage;
  String? _exitUndoOfferName;
  String? get exitUndoOfferName => _exitUndoOfferName;

  /// Arming an offer also records [exitUndoName]; consuming it does not.
  set exitUndoOfferName(String? name) {
    _exitUndoOfferName = name;
    if (name != null) exitUndoName = name;
  }

  /// Who the open undo would bring back; not consumed by the SnackBar.
  String? exitUndoName;

  /// The open undo is {{user}}'s own `/director` step-out, not a guest's or
  /// member's exit: undoing it deletes the goodbye and leaves Director Mode.
  bool exitUndoUserStep = false;

  /// Set when a FULL group member's `/exit` is awaiting commit. They have said
  /// goodbye and left the live roster, but their DB row/realism/evolution/
  /// quests/memory are untouched and the real removal (plus any collapse to a
  /// 1:1) is deferred until the user continues — so undoLastExit can restore
  /// them losslessly. Committed in `sendMessage`.
  CharacterCard? pendingMemberExit;

  SceneGuestDirector? director;

  // ── Cast detection (Phase 2) ────────────────────────────────────────────
  // Periodically (not every turn) scans the primary's recent narration in a
  // 1:1 chat for a newly-introduced, recurring, named side character and
  // offers to promote it to a Scene Guest. Detection only reads text +
  // triggers the existing parity-safe mint/enter flow, so it adds ZERO
  // Realism/Needs work.

  /// Primary turns since the last cast-detection scan (zeroed at the same
  /// Scene Guest reset sites alongside `pendingDeparture = null`).
  int turnsSinceCastScan = 0;

  /// A detected candidate awaiting the user's accept/ignore choice. Surfaced
  /// to the chat UI exactly like the Chance Time wheel's pending flag.
  DetectedCharacter? pendingDetection;

  /// Names already offered (whether accepted or ignored) this session,
  /// lower-cased, so the same character is never re-offered. Cleared at the
  /// Scene Guest reset sites.
  final Set<String> offeredOrIgnoredNames = {};

  CastDetector? castDetector;

  bool resolving = false;
  bool resolvePending = false;
}
