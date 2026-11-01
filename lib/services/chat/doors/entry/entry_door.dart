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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

import 'chat_entry.dart';
import 'entry_cover.dart';
import 'entry_deps.dart';
import 'group_director.dart';
import 'group_entry.dart';
import 'group_fork.dart';
import 'group_member_reads.dart';
import 'group_member_settings.dart';
import 'group_roster.dart';
import 'group_store_migrate.dart';

export 'chat_entry.dart';
export 'entry_cover.dart';
export 'entry_deps.dart';
export 'group_director.dart';
export 'group_entry.dart';
export 'group_fork.dart';
export 'group_member_reads.dart';
export 'group_member_settings.dart';
export 'group_roster.dart';
export 'group_store_migrate.dart';

/// Opening a chat and keeping a group's roster: a 1:1 ([ChatEntry]), a
/// group ([GroupEntry]), and the group's members ([GroupRoster]: join,
/// leave, the 1:1 to group fork, each member's switches, notes and
/// prompts, the legacy re-key of their stores), with the per-member reads
/// and Director Mode the group UI shows.
///
/// An entry is a sequence of calls on the other doors: the session store
/// clears and loads the row, the cast door resets guests and greetings,
/// the objectives door reloads quests. What this door owns is the state no
/// other door has: the group repository main.dart wires in, the forked
/// entrances' flag and the auto-chat budget.
///
/// Not a notifier: every piece calls the service's own notify in place
/// ([EntryDeps.notify]), as the parts it replaces did.
class EntryDoor {
  EntryDoor(this._d);

  final EntryDeps _d;

  /// Wired by main.dart so a group opens for every caller (creation, home
  /// taps, fork) even when the caller passes no repository.
  GroupChatRepository? groupRepository;

  /// True while forked-in character entrances are still playing (fire and
  /// forget after [GroupFork.forkToGroupChat]). Blocks user turns so the
  /// one-shot entrance directive can't be consumed by a racing user turn.
  bool entrancesInFlight = false;

  /// The running auto-chat's turn budget.
  final AutoChatBudget autoChat = AutoChatBudget();

  late final EntryCover cover = EntryCover(_d);
  late final ChatEntry chat = ChatEntry(this, _d);
  late final GroupEntry group = GroupEntry(this, _d);
  late final GroupRoster roster = GroupRoster(this, _d);
  late final GroupFork fork = GroupFork(this, _d);
  late final GroupMemberSettings members = GroupMemberSettings(this, _d);
  late final GroupStoreMigrate rekey = GroupStoreMigrate(this, _d);
  late final GroupMemberReads reads = GroupMemberReads(this, _d);
  late final GroupDirector director = GroupDirector(this, _d);

  ChatSessionState get _session => _d.session;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;

  /// Light in-place refresh after the active/focused character's card was
  /// edited: swap the reference (matched by dbId, so RENAMES stay light) and
  /// repaint — WITHOUT the full chat-entry dance. Never cancels an in-flight
  /// generation, never reloads the session, and is group-safe: editing a
  /// focused group member updates that member's reference instead of tearing
  /// the group down. (The deleted EditCharacterDialog called setActiveCharacter
  /// for this, which cancels generation, full-reloads on rename, and leaves the
  /// group — the exact failure modes this exists to avoid.)
  void refreshActiveCharacterCard(CharacterCard card) {
    if (_activeGroup != null) {
      // identical() first: the editor mutates the roster's own instance;
      // dbId (the member's row id) covers callers that hand back a copy.
      final i = _groupCharacters.indexWhere(
        (c) => identical(c, card) || (c.dbId != null && c.dbId == card.dbId),
      );
      if (i != -1) {
        // A copy from outside the chat (Edit group) has no expression images:
        // the chat inherits those from the library when it loads the roster.
        final old = _groupCharacters[i];
        if (!identical(old, card) && card.avatarImages == null) {
          card
            ..avatarImages = old.avatarImages
            ..primeAvatarIndex = old.primeAvatarIndex;
        }
        // Nor the row's provenance, its only link to its library card.
        if (!identical(old, card) &&
            card.originLibraryDbId == null &&
            card.originStableId == null) {
          card
            ..originLibraryDbId = old.originLibraryDbId
            ..originStableId = old.originStableId;
        }
        // characters is an unmodifiable view; writing it throws on Save.
        _session.groupManager?.replaceCharacterAt(i, card);
        // Only while a turn's pass has lent the pointer to this member.
        if (identical(_session.activeCharacter, old)) {
          _session.activeCharacter = card;
        }
      }
    } else if (_session.activeCharacter != null &&
        (_session.activeCharacter!.dbId == null ||
            _session.activeCharacter!.dbId == card.dbId)) {
      _session.activeCharacter = card;
    }
    _d.hooks.refreshEnjoysLowHygiene();
    unawaited(_d.services.birthdays().ensure());
    _d.notify();
  }

  /// Drops a removed member from the per-character group maps (realism
  /// slot, author notes, system prompts, RAG priorities).
  void forgetMember(String id) {
    final config = _d.sessions().groupConfig;
    _d.services.realism().groups.members.remove(id);
    config.authorNotes.remove(id);
    config.authorNoteStrengths.remove(id);
    config.characterSystemPrompts.remove(id);
    config.characterRAGPriorities.remove(id);
  }
}
