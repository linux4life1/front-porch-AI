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

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat_lifetime.dart';
import 'package:front_porch_ai/services/chat/chat_wiring.dart';
import 'package:front_porch_ai/services/chat/planner_today_fate.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

/// The chat's ties to the services around it: the listeners it registers
/// on storage, the LLM provider, the character library and the tool probe;
/// the database's deleted-chat stream; and what it starts at construction
/// and stops at dispose. Every callback registered here is a plain method
/// tear-off, which Dart canonicalizes, so `removeListener` finds it again.
class ChatBindings {
  ChatBindings({
    required KoboldService kobold,
    required StorageService storage,
    required BoundServices bound,
    required ChatLifetime life,
    required ChatWiring wiring,
    required void Function() notify,
  }) : _kobold = kobold,
       _storage = storage,
       _bound = bound,
       _life = life,
       _w = wiring,
       _notify = notify;

  final KoboldService _kobold;
  final StorageService _storage;
  final BoundServices _bound;
  final ChatLifetime _life;
  final ChatWiring _w;
  final void Function() _notify;

  /// The database's word of every chat it deletes, for KoboldCpp's saved
  /// cache of it. Moves with the database, so it is re-made on a swap.
  StreamSubscription<String>? _deletedChats;

  /// Everything the chat's constructor does.
  ///
  /// The shell's `notifyListeners` is a plain instance method, so its
  /// tear-off ([_notify]) stays `==`-equal to the one [dispose] passes to
  /// `removeListener`.
  void init() {
    _w.forwardDoorNotify(_w.mediaDoor);
    _w.forwardDoorNotify(_w.actionsDoor);
    // Probe verdicts land from background passes and the manual test alike —
    // rebroadcast so the sidebar's tool-calling pill repaints live.
    _w.realism.transport.probe.addListener(_notify);
    // Settled verdicts outlive the run (a known model is not asked again).
    _w.realism.transport.wireToolVerdicts();
    // Local model path / remote model name changes alter the eval identity —
    // retest tool support for the new model (sidebar pill contract).
    _storage.addListener(_onBackendIdentityMaybeChanged);
    // Porch Life's Realism permission, read now so a later change is seen.
    _storage.addListener(_w.controlsDoor.permission.settingsChanged);
    _w.sessionStore.today.onTodayAbandoned = (held) {
      // Sour mood first — deactivate is DB I/O and must not gate the
      // feeling. Day-ate already journals then deactivates; abandon
      // used to wait on the isolate and leave emotion empty under load.
      final planner = _w.realism.planner;
      unawaited(
        planner.journalResolvedToday(held, fate: PlannerTodayFate.abandoned),
      );
      unawaited(planner.deactivateTodayObjective());
    };
  }

  /// Everything the chat's dispose does except `super.dispose()`.
  void dispose() {
    _life.dispose();
    _w.castDoor.idle.cancelIdleTimer();
    _w.turnEngine.progress.cancelStreamNotifyThrottle();
    _w.castDoor.guests.state.statusClearTimer?.cancel();
    _bound.characters?.removeListener(_onCharacterLibraryChanged);
    _storage.removeListener(_onBackendIdentityMaybeChanged);
    _storage.removeListener(_w.controlsDoor.permission.settingsChanged);
    _bound.llmProvider?.removeListener(_onBackendIdentityMaybeChanged);
    _w.realism.transport.probe.removeListener(_notify);
    _w.realism.toolSupportTester.dispose();
    _w.lanes.dispose();
    unawaited(_deletedChats?.cancel());
  }

  /// Point the chat — and the MemoryService it owns — at [db].
  ///
  /// Used both to wire the database in at startup and to re-point it after a
  /// swap (stable-DB import, storage-root move, backup restore). The
  /// MemoryService caches its own handle, so leaving it out meant RAG memory
  /// kept querying the closed database until the app was restarted; it is null
  /// during startup wiring, which the null-aware call covers.
  void updateDatabase(AppDatabase db) {
    _bound.db = db;
    _bound.memory?.updateDatabase(db);
    unawaited(_deletedChats?.cancel());
    _deletedChats = db.deletedSessions.listen(_letGoOfDeletedChat);
  }

  /// A deleted chat's saved cache is let go. This runs inside the database's
  /// delete: what goes wrong is said in the log and goes no further.
  void _letGoOfDeletedChat(String chat) {
    try {
      _kobold.forgetChat(chat);
    } on Object catch (e) {
      debugPrint('[Chat] letting go of a deleted chat\'s cache failed: $e');
    }
    // A deleted chat is owed no starting-point scan any more.
    unawaited(
      _storage.realismSettings.settleRealismStart(chat).catchError((Object e) {
        debugPrint('[Realism] forgetting a deleted chat\'s scan failed: $e');
      }),
    );
  }

  /// Set the CharacterRepository so group mode can look up characters.
  void setCharacterRepository(CharacterRepository repo) {
    if (identical(_bound.characters, repo)) return;
    _bound.characters?.removeListener(_onCharacterLibraryChanged);
    _bound.characters = repo;
    repo.addListener(_onCharacterLibraryChanged);
  }

  /// Set the LLMProvider after construction (to break circular dependency in
  /// provider tree).
  void setLLMProvider(LLMProvider provider) {
    // Idempotent like [setCharacterRepository]: the ProxyProvider `update` that
    // owns this wiring re-runs on every Kobold log line, so an unguarded
    // addListener would append one callback per frame, forever.
    if (identical(_bound.llmProvider, provider)) return;
    _bound.llmProvider?.removeListener(_onBackendIdentityMaybeChanged);
    _bound.llmProvider = provider;
    // Backend switches and local-engine ready transitions flow through the
    // provider — retest tool support when the identity changes and is ready.
    provider.addListener(_onBackendIdentityMaybeChanged);
  }

  void _onBackendIdentityMaybeChanged() {
    if (_life.disposed) return;
    ToolChoiceStyleProbe.instance.reset(_w.realism.transport.backendIdentity);
    _w.realism.toolSupportTester.onBackendMaybeChanged();
  }

  /// Silently prune Scene Guests whose library card no longer exists. Deleting a
  /// character PNG is a deliberate user action, so a deleted guest is dropped
  /// from the open scene with NO `/exit` narration — `resolveSceneGuestCards`
  /// removes any id that no longer resolves. Self-heals the "deleted card but
  /// still treated as present" case (e.g. cast detection skipping a re-narrated
  /// character because the stale guest was still in the scene list).
  void _onCharacterLibraryChanged() {
    if (_life.disposed) return;
    final guests = _w.castDoor.guests;
    if (guests.state.busy || guests.state.ids.isEmpty) return;
    // Defer out of the repository's notify callback so we never start a DB read
    // from inside its in-progress write/transaction; re-check guards (and that
    // the chat hasn't switched) on the microtask. resolveSceneGuestCards also
    // self-guards on the token, so a stale resolve can't write the wrong chat.
    final token = _w.session.currentSessionId;
    scheduleMicrotask(() {
      if (_w.castDoor.sceneChanged(token) ||
          guests.state.busy ||
          guests.state.ids.isEmpty) {
        return;
      }
      guests.resolveSceneGuestCards();
    });
  }
}

/// The RAG receipt of the latest reply, or null. Reads the list it is
/// handed (the chat's public messages), never the session itself.
Map<String, dynamic>? lastRagReceiptIn(List<ChatMessage> messages) {
  for (final m in messages.reversed) {
    if (m.isUser || m.sender == 'System') continue;
    return (m.activeMetadata?['rag_receipt'] as Map?)?.cast<String, dynamic>();
  }
  return null;
}
