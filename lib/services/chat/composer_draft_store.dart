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

// Composer drafts: a half-typed message the user left in the message box
// when they closed a chat comes back when they reopen it. Two homes, one
// router (see saveDraft for the rule): saved chats carry their draft on
// the sessions row (v65 sessions.composer_draft), so deleting the chat
// deletes the draft with it; a brand-new chat whose first message was
// never sent has no row yet, and its draft rides SharedPreferences keyed
// by the chat's OWNER (the character's stableGroupId, or `group_<id>`)
// so a fresh session of the same character can pick it up.

import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';

/// Owner key for a 1:1 chat's prefs-routed draft — the same identity the
/// session picker uses (imagePath basename, NOT the dbId UUID; see the
/// gotcha note in home_chat_opener.dart).
String composerDraftOwnerForCharacter(String stableGroupId) =>
    'composer_draft.$stableGroupId';

/// Owner key for a group chat's prefs-routed draft.
String composerDraftOwnerForGroup(String groupId) =>
    'composer_draft.group_$groupId';

/// Read/write router for composer drafts. Thin over the DB and prefs —
/// every decision lives in [saveDraft] / [loadDraft] so one file answers
/// "where does this chat's draft live".
class ComposerDraftStore {
  ComposerDraftStore(this._db);

  final AppDatabase _db;

  /// Persist [text] for the chat identified by [sessionId] + [ownerKey].
  /// [fresh] means the chat has no user message yet — the same rule the
  /// web twin reads from its transcript, and the reason it is the door
  /// and not row-existence alone: opening a card DOES materialize the
  /// row (the greeting save), so a router that trusted the row alone
  /// would strand a never-sent new chat's draft in a session the user
  /// is about to throw away.
  ///
  /// Empty text clears BOTH homes: the row draft and the owner's prefs
  /// draft. Clearing both is deliberate — right after the first send the
  /// draft crosses from mailbox to row, and a clear that only touched
  /// one home would leave the other to haunt the reopen. (Consequence:
  /// the per-owner mailbox holds one letter — a new draft replaces a
  /// still-pending one for the same character.)
  Future<void> saveDraft({
    required String? sessionId,
    required String ownerKey,
    required bool fresh,
    required String text,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      if (sessionId != null) {
        await _db.setComposerDraft(sessionId, null);
      }
      await prefs.remove(ownerKey);
      return;
    }
    if (!fresh && sessionId != null && await _db.sessionExists(sessionId)) {
      await _db.setComposerDraft(sessionId, text);
    } else {
      await prefs.setString(ownerKey, text);
    }
  }

  /// The draft to seed the composer with, or '' for none.
  ///
  /// Strict twin of [saveDraft]'s routing: a chat that has already spoken
  /// reads ONLY its row; a chat with no user message yet — new, or a
  /// greeting-only resume — reads ONLY the owner mailbox. So a draft
  /// left in a spoken chat never shows up in a different chat, and the
  /// mailbox only ever answers the new-chat door.
  Future<String> loadDraft({
    required String? sessionId,
    required String ownerKey,
    required bool fresh,
  }) async {
    if (!fresh && sessionId != null && await _db.sessionExists(sessionId)) {
      return await _db.getComposerDraft(sessionId) ?? '';
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(ownerKey) ?? '';
  }
}
