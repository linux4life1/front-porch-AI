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

import 'package:drift/drift.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Refractory, RefractoryKeys;
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// The existing-chats question: when Porch Life starts allowing Afterglow,
/// the chats whose own switch is off are counted and, only if asked, switched
/// on. Nothing else in those chats changes (a group chat that never saved
/// its own blob takes its group's, see [_afterglowOff]), and no card or group
/// template is touched. A chat in the trash is left alone.
///
/// A 1:1 chat's switch is its `nsfw_cooldown_enabled` column; a group chat's
/// is the `afterglow` key of its realism blob, which falls back to the
/// group's template until the chat saves its own (as the chat reads it when
/// it opens). The chat open right now is read and switched live, so its next
/// save cannot write the old value back.
class ExistingChatsOffer {
  ExistingChatsOffer(this._db, this._chat);

  final AppDatabase _db;
  final ChatService? _chat;

  /// How many chats have their own Afterglow switch off.
  Future<int> countAfterglowOff() async => (await _afterglowOff()).length;

  /// Switches Afterglow on in every chat that has it off; returns how many.
  Future<int> turnAfterglowOn() async {
    final off = await _afterglowOff();
    var changed = 0;
    for (final chat in off) {
      if (chat.open) {
        // Read from memory, so it is only ever switched live: a chat left
        // since has saved its own state, which a blind write would replace.
        if (chat.id != _openSessionId) continue;
        await _chat!.setAfterglowEnabled(true);
      } else if (chat.id == _openSessionId) {
        // Opened since it was counted: its next save would write the old
        // value back over a raw write, so it is switched live too.
        await _chat!.setAfterglowEnabled(true);
      } else if (!chat.isGroup) {
        await _db.customUpdate(
          'UPDATE sessions SET nsfw_cooldown_enabled = 1 WHERE id = ?',
          variables: [Variable(chat.id)],
        );
      } else {
        await _db.customUpdate(
          'UPDATE sessions SET group_realism_state = ? WHERE id = ?',
          variables: [
            Variable(jsonEncode({...chat.blob, kGroupAfterglowKey: true})),
            Variable(chat.id),
          ],
        );
      }
      changed++;
    }
    return changed;
  }

  String? get _openSessionId => _chat?.currentSessionId;

  /// Each chat that has its switch off. A group chat carries the blob it
  /// reads, so turning it on keeps every other key. A group chat that never
  /// saved its own blob reads its group's; turning it on gives it that blob
  /// as its own, so it stops following later edits to the group's template.
  Future<List<_OffChat>> _afterglowOff() async {
    final open = _openSessionId;
    final off = <_OffChat>[];
    if (open != null && _chat != null && !_chat.afterglowChatSwitch) {
      off.add(_OffChat(open, isGroup: _chat.isGroupMode, open: true));
    }
    final solo =
        await (_db.select(_db.sessions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.groupId.isNull() &
                  t.nsfwCooldownEnabled.equals(false),
            ))
            .get();
    for (final r in solo) {
      if (r.id == open || _opensOn(r)) continue;
      off.add(_OffChat(r.id, isGroup: false));
    }
    final groups = await _db
        .customSelect(
          'SELECT s.id AS id, s.group_realism_state AS st, '
          'gr.default_member_realism_state AS d '
          'FROM sessions s JOIN groups gr ON gr.id = s.group_id '
          'WHERE s.deleted_at IS NULL',
        )
        .get();
    for (final r in groups) {
      final id = r.read<String>('id');
      if (id == open) continue;
      final own = r.readNullable<String>('st') ?? '';
      final blob = own.isEmpty || own == '{}'
          ? r.readNullable<String>('d') ?? ''
          : own;
      if (groupAfterglowIn(blob)) continue;
      off.add(_OffChat(id, isGroup: true, blob: _decode(blob)));
    }
    return off;
  }

  /// A 1:1 chat stored off that still holds Lust, a recovery or a warmth
  /// tail opens with Afterglow on (the on-open repair in session hydrate),
  /// so it does not have Afterglow off and is not asked about.
  static bool _opensOn(Session s) {
    final body = Refractory.read({
      RefractoryKeys.minutes: s.refractoryMinutesRemaining,
      RefractoryKeys.total: s.refractoryMinutesTotal,
      if (s.refractoryTailMinutes != null)
        RefractoryKeys.tail: {
          RefractoryKeys.minutes: s.refractoryTailMinutes,
          RefractoryKeys.total:
              s.refractoryTailTotal ?? s.refractoryTailMinutes,
        },
      RefractoryKeys.legacyTurns: s.cooldownTurnsRemaining,
      RefractoryKeys.legacyTotal: s.cooldownTurnsTotal,
    });
    return s.arousalLevel != 0 ||
        (body?.running ?? false) ||
        (body?.tailRunning ?? false);
  }

  static Map<String, dynamic> _decode(String json) {
    try {
      final v = jsonDecode(json);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

class _OffChat {
  _OffChat(
    this.id, {
    required this.isGroup,
    this.open = false,
    this.blob = const {},
  });

  final String id;
  final bool isGroup;

  /// The chat that was open when counted, read from memory.
  final bool open;
  final Map<String, dynamic> blob;
}
