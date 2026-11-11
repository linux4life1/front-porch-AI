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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';

/// A group's members as the editor needs them: cards for the Details tab and
/// realism rows (mid, name, origin, avatar) for the Realism tab. The origin
/// lets the realism editor recover seeds from groups made before the
/// id-keying fix. A member whose private avatar is gone is skipped.
Future<({List<CharacterCard> cards, List<GroupRealismMember> realism})>
loadEditGroupRoster(
  GroupChatRepository groupRepo,
  StorageService storage,
  String groupId,
) async {
  final cards = <CharacterCard>[];
  final realism = <GroupRealismMember>[];
  for (final m in await groupRepo.getMembersForGroup(groupId)) {
    final fn = m.avatarFilename;
    if (fn == null) continue;
    final avatarPath = p.join(storage.groupsDir.path, groupId, 'avatars', fn);
    if (!await File(avatarPath).exists()) continue;
    final card = m.toCharacterCard(resolvedImagePath: avatarPath);
    cards.add(card);
    realism.add(
      GroupRealismMember(
        mid: m.id,
        name: m.name,
        originStableId: m.originStableId,
        avatarPath: avatarPath,
        extensions: card.frontPorchExtensions,
      ),
    );
  }
  return (cards: cards, realism: realism);
}

/// The roster the group editor holds: member cards, the realism rows built
/// from them, and each member's defaults for new chats as they were when
/// loaded (so Save writes only the members whose defaults changed).
class EditGroupRoster extends ChangeNotifier {
  final List<CharacterCard> members = [];
  final List<GroupRealismMember> realism = [];
  bool loaded = false;
  final Map<String, String> _stored = {};

  /// Reads the whole roster again.
  Future<void> load(
    GroupChatRepository repo,
    StorageService storage,
    String groupId,
  ) async {
    final roster = await loadEditGroupRoster(repo, storage, groupId);
    members
      ..clear()
      ..addAll(roster.cards);
    realism
      ..clear()
      ..addAll(roster.realism);
    loaded = true;
    _stored
      ..clear()
      ..addAll(extJson());
    notifyListeners();
  }

  /// Each member's extensions as JSON, keyed by member id.
  Map<String, String> extJson() => {
    for (final c in members)
      if (c.dbId != null) c.dbId!: jsonEncode(c.frontPorchExtensions?.toJson()),
  };

  /// Member [mid]'s defaults for new chats changed; held on their card
  /// until Save.
  void setDefaults(String mid, FrontPorchExtensions ext) {
    final i = members.indexWhere((c) => c.dbId == mid);
    if (i < 0) return;
    members[i].frontPorchExtensions = ext;
    final r = realism.indexWhere((m) => m.mid == mid);
    if (r >= 0) {
      final old = realism[r];
      realism[r] = GroupRealismMember(
        mid: old.mid,
        name: old.name,
        originStableId: old.originStableId,
        avatarPath: old.avatarPath,
        extensions: ext,
      );
    }
    notifyListeners();
  }

  /// A member editor saved a card whole: what the cards hold is stored.
  void markStored() {
    _stored
      ..clear()
      ..addAll(extJson());
    for (var i = 0; i < realism.length; i++) {
      final old = realism[i];
      final card = members.where((c) => c.dbId == old.mid).firstOrNull;
      if (card == null) continue;
      realism[i] = GroupRealismMember(
        mid: old.mid,
        name: old.name,
        originStableId: old.originStableId,
        avatarPath: old.avatarPath,
        extensions: card.frontPorchExtensions,
      );
    }
    notifyListeners();
  }

  /// Writes the members whose defaults changed (only their extensions, never
  /// the rest of their row) and, with a chat open on the group, hands each to
  /// it without touching its live switches.
  Future<void> saveDefaults(AppDatabase db, ChatService? openChat) async {
    for (final card in members) {
      final id = card.dbId;
      final ext = card.frontPorchExtensions;
      if (id == null || ext == null) continue;
      final now = jsonEncode(ext.toJson());
      final was = _stored[id];
      if (was == now) continue;
      final opened = was == null || was == 'null'
          ? true
          : FrontPorchExtensions.fromJson(
              Map<String, dynamic>.from(jsonDecode(was) as Map),
            ).afterglowEnabled;
      final before = openChat == null
          ? opened
          : liveMemberAfterglow(openChat, card, opened);
      await saveGroupMemberExtensions(db, card);
      if (openChat != null) {
        await applyMemberDefaultsToOpenChat(openChat, card, before);
      }
      _stored[id] = jsonEncode(card.frontPorchExtensions?.toJson());
    }
  }
}
