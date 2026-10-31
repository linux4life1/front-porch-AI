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

import 'package:drift/drift.dart' show Variable;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// The existing-chats question: when Porch Life starts allowing Afterglow,
/// the chats whose own switch is off are counted and, only if asked, switched
/// on. Nothing else in those chats changes, and no card or group template is
/// touched. A chat in the trash is left alone.
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
    for (final chat in off) {
      if (chat.id == _openSessionId) {
        await _chat!.setAfterglowEnabled(true);
      } else if (chat.blob == null) {
        await _db.customUpdate(
          'UPDATE sessions SET nsfw_cooldown_enabled = 1 WHERE id = ?',
          variables: [Variable(chat.id)],
        );
      } else {
        await _db.customUpdate(
          'UPDATE sessions SET group_realism_state = ? WHERE id = ?',
          variables: [
            Variable(jsonEncode({...chat.blob!, kGroupAfterglowKey: true})),
            Variable(chat.id),
          ],
        );
      }
    }
    return off.length;
  }

  String? get _openSessionId => _chat?.currentSessionId;

  /// Each chat that has its switch off: its id, and for a group chat the
  /// blob it reads (so turning it on keeps every other key).
  Future<List<({String id, Map<String, dynamic>? blob})>>
  _afterglowOff() async {
    final rows = await _db
        .customSelect(
          'SELECT s.id AS id, s.group_id AS g, '
          's.nsfw_cooldown_enabled AS n, s.group_realism_state AS st, '
          'gr.default_member_realism_state AS d '
          'FROM sessions s LEFT JOIN groups gr ON gr.id = s.group_id '
          'WHERE s.deleted_at IS NULL',
        )
        .get();
    final off = <({String id, Map<String, dynamic>? blob})>[];
    for (final r in rows) {
      final id = r.read<String>('id');
      final isGroup = r.readNullable<String>('g') != null;
      if (id == _openSessionId) {
        if (!_chat!.afterglowChatSwitch) off.add((id: id, blob: null));
        continue;
      }
      if (!isGroup) {
        if (r.readNullable<bool>('n') != true) off.add((id: id, blob: null));
        continue;
      }
      final own = r.readNullable<String>('st') ?? '';
      final blob = own.isEmpty || own == '{}'
          ? r.readNullable<String>('d') ?? ''
          : own;
      if (groupAfterglowIn(blob)) continue;
      off.add((id: id, blob: _decode(blob)));
    }
    return off;
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
