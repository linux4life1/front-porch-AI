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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/group_fork_source.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// Web Group Settings' "New chats" section: Realism, Needs and Inherit for
/// the group's new chats, and the twin of the desktop Edit Group notice for
/// a group made from a 1:1 before forks saved honest settings. Nothing here
/// touches a chat that already exists, except Inherit, which every chat of
/// the group reads live.
class GroupNewChats {
  GroupNewChats(this._groups, [this._db, this._worlds]);

  final GroupChatRepository _groups;
  final AppDatabase? _db;
  final WorldRepository? _worlds;

  World? _lookup(String id) => _worlds?.worldById(id);

  Future<ForkedGroupSource?> _sourceOf(GroupChat g) async {
    final db = _db;
    if (db == null) return null;
    try {
      return await findForkedGroupSource(db, g, lookup: _lookup);
    } catch (e) {
      debugPrint('[web/groups] could not read the chat a group came from: $e');
      return null;
    }
  }

  /// `{realism, needs, afterglow, inherit, forkSource}` for [groupId], or null when
  /// the group is unknown. `forkSource` is null unless the group was made
  /// from a 1:1 whose settings it is missing.
  Future<Map<String, dynamic>?> stateOf(String groupId) async {
    final g = _groups.getById(groupId);
    if (g == null) return null;
    final r = groupTemplateRealismOf(g.defaultMemberRealismState);
    final s = await _sourceOf(g);
    return {
      'realism': r.realismOn,
      'needs': r.needsOn,
      'afterglow': groupAfterglowIn(g.defaultMemberRealismState),
      'inherit': g.inheritCharacterLorebooks,
      'forkSource': s == null || !s.differsFrom(g)
          ? null
          : {
              'hostName': s.hostName,
              'realismMissing': s.realismMissingFrom(g),
              'needsOn': s.needsOn,
              'meet': s.worldMissingFrom(g)
                  ? groupMeetLine(s.worlds!, _lookup)
                  : null,
            },
    };
  }

  /// Saves the posted `realism`, `needs`, `afterglow` and `inherit` switches, and with
  /// `useForkSource: true` fills in what the 1:1 the group came from had,
  /// as the desktop notice's "Use the chat's settings" then Save does.
  /// False when the group is unknown.
  Future<bool> update(String groupId, Map<String, dynamic> body) async {
    final g = _groups.getById(groupId);
    if (g == null) return false;
    final members = await _groups.getMembersForGroup(groupId);
    final ids = [for (final m in members) m.id];
    final cur = groupTemplateRealismOf(g.defaultMemberRealismState);
    var realism = body['realism'] is bool ? body['realism'] as bool : null;
    var needs = body['needs'] is bool ? body['needs'] as bool : null;
    if (body['useForkSource'] == true) {
      final s = await _sourceOf(g);
      if (s != null && s.realismMissingFrom(g)) {
        realism = true;
        needs = s.needsOn;
      }
      if (s != null && s.worldMissingFrom(g)) {
        final f = s.worlds!.fields;
        g.worldIds = f.worldIds;
        g.loreWorldIds = f.loreWorldIds;
      }
    }
    if (realism != null || needs != null) {
      final blobs = switchGroupTemplateRealism(
        defaultMemberJson: g.defaultMemberRealismState,
        baselineJson: g.baselineRealismState,
        memberIds: ids,
        realismOn: realism ?? cur.realismOn,
        needsOn: needs ?? cur.needsOn,
      );
      g.defaultMemberRealismState = blobs.defaultMemberJson;
      g.baselineRealismState = blobs.baselineJson;
    }
    if (body['afterglow'] is bool) {
      g.defaultMemberRealismState = withGroupAfterglow(
        g.defaultMemberRealismState,
        body['afterglow'] as bool,
      );
    }
    if (body['inherit'] is bool) {
      g.inheritCharacterLorebooks = body['inherit'] as bool;
    }
    await _groups.save(g);
    return true;
  }
}
