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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// A Porch Life feature the existing-chats question asks about.
enum ExistingChatsFeature { afterglow, needs, realism }

/// Whether Porch Life allows [feature] now, so the question may be asked
/// and answered. Needs and Afterglow run only inside Realism, so they are
/// asked about only while Realism is allowed (desktop and the phone's relay).
bool existingChatsFeatureAllowed(
  RealismSettings rs,
  ExistingChatsFeature feature,
) => switch (feature) {
  ExistingChatsFeature.realism => rs.realismAllowed,
  ExistingChatsFeature.needs => rs.realismAllowed && rs.needsSimDefault,
  ExistingChatsFeature.afterglow => rs.realismAllowed && rs.afterglowEnabled,
};

/// The existing-chats question: when Porch Life starts allowing a feature,
/// the chats whose own switch is off are counted and, only if asked, switched
/// on. Nothing else in those chats changes (a group chat that never saved
/// its own blob takes its group's, see [_afterglowOff]), and no card or group
/// template is touched. A chat in the trash is left alone.
///
/// Afterglow: a 1:1 chat's switch is its `nsfw_cooldown_enabled` column; a
/// group chat's is the `afterglow` key of its realism blob, which falls back
/// to the group's template until the chat saves its own (as the chat reads it
/// when it opens). Needs: every chat's switch is its `needs_sim_enabled`
/// column; Realism, its `realism_enabled` column. The chat open right now is
/// read and switched live, so its next save cannot write the old value back.
/// [cards] is the library, read for a card's own Needs choice. A closed
/// chat switched to Realism is owed its starting-point scan, so turning
/// Realism on needs [realism] (ChatService._scoreStartIfSavedBlocked pays).
class ExistingChatsOffer {
  ExistingChatsOffer(
    this._db,
    this._chat, {
    List<CharacterCard>? cards,
    RealismSettings? realism,
  }) : _cards = cards ?? const [],
       _realism = realism;

  final AppDatabase _db;
  final ChatService? _chat;
  final List<CharacterCard> _cards;
  final RealismSettings? _realism;

  /// How many chats have their own Afterglow switch off.
  Future<int> countAfterglowOff() => countOff(ExistingChatsFeature.afterglow);

  /// Switches Afterglow on in every chat that has it off; returns how many.
  Future<int> turnAfterglowOn() => turnOn(ExistingChatsFeature.afterglow);

  /// How many chats have their own switch for [feature] off.
  Future<int> countOff(ExistingChatsFeature feature) async =>
      (await _off(feature)).length;

  /// Switches [feature] on in every chat that has it off; returns how many.
  ///
  /// Realism needs [realism]: each closed chat it switches on is owed its
  /// starting-point scan, written once for all of them before any switch,
  /// so no chat is turned on without its debt.
  Future<int> turnOn(ExistingChatsFeature feature) async {
    final owes = _realism;
    final isRealism = feature == ExistingChatsFeature.realism;
    if (isRealism && owes == null) {
      throw StateError('turning Realism on in chats needs RealismSettings');
    }
    final off = await _off(feature);
    if (isRealism) {
      await owes!.oweRealismStart([
        for (final c in off)
          if (!c.open && c.id != _openSessionId) c.id,
      ]);
    }
    var changed = 0;
    for (final chat in off) {
      if (chat.open) {
        // Read from memory, so it is only ever switched live: a chat left
        // since has saved its own state, which a blind write would replace.
        if (chat.id != _openSessionId) continue;
        await _switchOpenOn(feature);
      } else if (chat.id == _openSessionId) {
        // Opened since it was counted: its next save would write the old
        // value back over a raw write, so it is switched live too.
        await _switchOpenOn(feature);
      } else if (feature == ExistingChatsFeature.needs) {
        await _db.customUpdate(
          'UPDATE sessions SET needs_sim_enabled = 1 WHERE id = ?',
          variables: [Variable(chat.id)],
        );
      } else if (feature == ExistingChatsFeature.realism) {
        await _db.customUpdate(
          'UPDATE sessions SET realism_enabled = 1 WHERE id = ?',
          variables: [Variable(chat.id)],
        );
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

  Future<void> _switchOpenOn(ExistingChatsFeature feature) => switch (feature) {
    ExistingChatsFeature.needs => _chat!.setNeedsSimEnabled(true),
    ExistingChatsFeature.afterglow => _chat!.setAfterglowEnabled(true),
    // Live, so the open chat scores its starting point now if it has none.
    ExistingChatsFeature.realism => _chat!.setRealismEnabled(true),
  };

  Future<List<_OffChat>> _off(ExistingChatsFeature feature) =>
      switch (feature) {
        ExistingChatsFeature.needs => _needsOff(),
        ExistingChatsFeature.afterglow => _afterglowOff(),
        ExistingChatsFeature.realism => _realismOff(),
      };

  /// Each chat with its own Realism switch off, 1:1 and group alike: the
  /// `realism_enabled` column every chat opens with.
  Future<List<_OffChat>> _realismOff() async {
    final open = _openSessionId;
    final off = <_OffChat>[];
    if (open != null && _chat != null && !_chat.realismChatSwitch) {
      off.add(_OffChat(open, isGroup: _chat.isGroupMode, open: true));
    }
    final rows =
        await (_db.select(_db.sessions)..where(
              (t) => t.deletedAt.isNull() & t.realismEnabled.equals(false),
            ))
            .get();
    for (final r in rows) {
      if (r.id == open) continue;
      off.add(_OffChat(r.id, isGroup: r.groupId != null));
    }
    return off;
  }

  /// Each chat with Needs off. A 1:1 chat stored off with no saved vector at
  /// all (saved before chats recorded their choice) is decided when it opens
  /// by its card's choice, or its own Realism when the card says nothing
  /// (`needsSimAfterHydrate` with Porch Life's Needs on), so it counts only
  /// when that would open it off.
  Future<List<_OffChat>> _needsOff() async {
    final open = _openSessionId;
    final off = <_OffChat>[];
    if (open != null && _chat != null && !_chat.needsSimEnabled) {
      off.add(_OffChat(open, isGroup: _chat.isGroupMode, open: true));
    }
    final rows =
        await (_db.select(_db.sessions)..where(
              (t) => t.deletedAt.isNull() & t.needsSimEnabled.equals(false),
            ))
            .get();
    for (final r in rows) {
      if (r.id == open) continue;
      final isGroup = r.groupId != null;
      final vector = r.needsVector;
      if (!isGroup && (vector == null || vector.isEmpty)) {
        final card = _cards.where((c) => c.dbId == r.characterId).firstOrNull;
        if (card?.frontPorchExtensions?.needsSimChoice ?? r.realismEnabled) {
          continue;
        }
      }
      off.add(_OffChat(r.id, isGroup: isGroup));
    }
    return off;
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
    // The stored switch alone decides: a chat switched off keeps its Lust
    // and recovery, so holding either says nothing about the switch.
    for (final r in solo) {
      if (r.id == open) continue;
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
