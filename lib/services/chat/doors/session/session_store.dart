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

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

import 'context_window.dart';
import 'group_session_config.dart';
import 'group_state_load.dart';
import 'new_chat.dart';
import 'new_chat_prep.dart';
import 'session_deps.dart';
import 'session_forker.dart';
import 'session_hydrator.dart';
import 'session_loader.dart';
import 'session_saver.dart';
import 'session_scalars.dart';
import 'session_seed.dart';
import 'today_sentence.dart';
import 'walk_back.dart';

export 'context_window.dart';
export 'group_session_config.dart';
export 'group_state_load.dart';
export 'new_chat.dart';
export 'new_chat_prep.dart';
export 'session_deps.dart';
export 'session_forker.dart';
export 'session_hydrator.dart';
export 'session_loader.dart';
export 'session_saver.dart';
export 'session_scalars.dart';
export 'session_seed.dart';
export 'today_sentence.dart';
export 'walk_back.dart';

/// The open chat's session: its row and everything stored with it. Load,
/// save, the scalar capture and restore, a fork, a new chat, an imported
/// chat's seed, the tail-first history window and the today line.
///
/// It owns the session-scoped state the row carries: the recap ("Where we
/// are") and its cursor, the Author's Note, per-chat generation settings
/// and theme, the chat's name, description, gallery looks and fork
/// lineage, a group's per-member settings, and the open/switch flags.
///
/// Not a notifier: every piece calls the service's own notify in place
/// ([SessionDeps.notify]), as the parts it replaces did; a coalesced
/// notify would merge the loading cover's transitions.
class SessionStore {
  SessionStore(this._d) {
    today.addListener(_d.notify);
  }

  final SessionDeps _d;

  // ── Recap ─────────────────────────────────────────────────────────────

  String summary = '';
  int summaryLastIndex = 0;

  /// Session id whose in-memory recap matches the row. Until hydrate, a
  /// save must not blank or replace `sessions.summary`.
  String? recapBoundSessionId;

  /// The editor or a timeline rewrite cleared "Where we are" on purpose.
  bool recapClearArmed = false;

  // Secondary runtime flags (like isSummaryGenerating); zeroed on *all*
  // reset/new-chat/0-session/group/setActive/load/delete paths or pause
  // state leaks across contexts.
  bool summaryPaused = false;
  bool isSummaryGenerating = false;

  // ── Author's Note, per-chat settings, metadata ────────────────────────

  String authorNote = '';
  int authorNoteStrength = 4;

  /// Per-session generation overrides.
  ChatGenerationSettings genSettings = ChatGenerationSettings();

  /// Per-chat theme overrides (preset, colours, font, background, border).
  ChatThemeOverrides themeOverrides = ChatThemeOverrides();
  String? sessionName;
  String? sessionDescription;

  /// {characterId: selectedLookAvatarId} for THIS session, decoded from the
  /// row's selected-look column on load. A map so a group remembers a look
  /// per participant; empty when no session.
  Map<String, String> selectedLooks = {};

  // Chat branching.
  String? parentSessionId;
  int? forkIndex;

  /// A group's per-member notes, prompts and RAG knobs (the session blob).
  final GroupSessionConfig groupConfig = GroupSessionConfig();

  // ── Open, switch, history window ──────────────────────────────────────

  /// Marks a fresh chat so memory retrieval skips it.
  bool isNewChat = false;
  bool isLoadingSession = false;

  /// New chat / loadSession runs in flight; sends wait them out.
  int chatSwitches = 0;
  final SessionHistoryWindow history = SessionHistoryWindow();
  Future<void> saveChain = Future.value();

  /// While a last-session hydrate runs, a save must not stamp the
  /// still-live previous chat's persona onto the row being loaded.
  bool preserveSessionPersona = false;

  // ── Real-absence awareness (Living Time §2) ──
  // Computed in memory at load from the last saved message's updatedAt;
  // nothing is stored or transmitted (absence_tracker.dart). Story clock
  // untouched.
  Duration absenceGap = Duration.zero;
  bool absenceAckPending = false;
  bool absenceAckConsumed = false;

  final TodaySentence today = TodaySentence();

  // ── The pieces ────────────────────────────────────────────────────────

  late final SessionSaver saver = SessionSaver(_d, this);
  late final SessionHydrator hydrator = SessionHydrator(_d, this);
  late final SessionScalars scalars = SessionScalars(_d, this);
  late final GroupStateLoad groupState = GroupStateLoad(_d, this);
  late final SessionLoader loader = SessionLoader(_d, this);
  late final SessionForker forker = SessionForker(_d, this);
  late final NewChatPrep prep = NewChatPrep(_d, this);
  late final NewChatOpener newChat = NewChatOpener(_d, this);
  late final SessionSeed seed = SessionSeed(_d, this);
  late final WalkBack walk = WalkBack(_d);
  late final ContextWindow window = ContextWindow(_d, this);

  /// Persist the open chat (see [SessionSaver.save]).
  Future<void> save({bool replaceAll = false}) =>
      saver.save(replaceAll: replaceAll);

  /// An edit of the open chat's recap. Binds the row so the following
  /// save writes this text, including a deliberate clear.
  void rememberRecapEdit(String text) {
    summary = text;
    final id = _d.session.currentSessionId;
    if (id != null) recapBoundSessionId = id;
    recapClearArmed = text.trim().isEmpty;
  }

  /// Blank recap, caught up to [lastIndex] (a transcript-only import).
  void catchUpRecap(int lastIndex) {
    summary = '';
    summaryLastIndex = lastIndex;
  }

  /// The settings dialog's write: keep, save, repaint.
  void setGenSettings(ChatGenerationSettings value) {
    genSettings = value;
    save();
    _d.notify();
  }

  void setThemeOverrides(ChatThemeOverrides value) {
    themeOverrides = value;
    // Persist only when a chat is actually open. The web facade already
    // guards this, but a bare `currentSessionId!` would crash any other
    // caller that sets the theme with no active session (session close
    // mid-save, tests).
    final sid = _d.session.currentSessionId;
    if (sid != null) {
      _d.services.db().setThemeOverrides(sid, value.toJsonString());
    }
    _d.notify();
  }

  /// Coarse absence bucket ("a few days"), or null under the threshold /
  /// fresh chat. Words only — never digits (see AbsenceTracker).
  String? get absencePhrase => AbsenceTracker.bucketPhrase(
    absenceGap,
    thresholdHours: _d.services.storage.realismSettings.absenceThresholdHours,
  );

  /// Real-absence gap (Living Time §2) from the freshly loaded DB rows —
  /// computed BEFORE any save this session can refresh their updatedAt, so
  /// the anchor is genuinely "when this chat last had activity". Shared by
  /// both load paths (keep them in sync). Fresh/empty chats stay at zero.
  void computeAbsenceGap(List<Message> dbMessages) {
    absenceGap = Duration.zero;
    absenceAckPending = false;
    absenceAckConsumed = false;
    DateTime? last;
    for (final m in dbMessages) {
      if (last == null || m.updatedAt.isAfter(last)) last = m.updatedAt;
    }
    if (last == null) return;
    final gap = DateTime.now().difference(last);
    if (gap.isNegative) return;
    absenceGap = gap;
    absenceAckPending = absencePhrase != null;
  }

  /// The per-chat gallery look selected for [characterId] in the active
  /// session, or null (no look chosen → the character's library face
  /// shows). Keyed by the character's library id so the same character
  /// shares one selection across a group cast.
  String? selectedLookFor(String characterId) => selectedLooks[characterId];

  /// Set (or clear, when [lookId] is null) the per-chat gallery look for
  /// [characterId] in the active session, persist the whole map to the
  /// session's selected-look column, and repaint. Never touches
  /// `imagePath` — the library face is independent of which look shows.
  Future<void> setLookForCharacter(String characterId, String? lookId) async {
    final sid = _d.session.currentSessionId;
    if (sid == null || characterId.isEmpty) return; // never key by a blank id
    // decodeSelectedLooks also drops empty keys, so a blank would silently
    // fail to round-trip; refuse it here so the caller notices instead.
    if (lookId == null) {
      selectedLooks.remove(characterId);
    } else {
      selectedLooks[characterId] = lookId;
    }
    _d.notify();
    await _d.services.db().setSelectedLookForSession(
      sid,
      encodeSelectedLooks(selectedLooks),
    );
  }
}
