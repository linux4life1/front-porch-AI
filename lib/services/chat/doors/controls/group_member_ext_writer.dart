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

import 'package:drift/drift.dart' as drift;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

/// Writes a group member's extensions (the card copy the group keeps) to
/// their avatar PNG and the group-members row, one write at a time.
class GroupMemberExtWriter {
  GroupMemberExtWriter(this.deps);

  final ControlsDeps deps;

  Future<void> persist({String? memberId}) {
    if (deps.session.activeGroup == null) return Future<void>.value();
    // Who to write is read now: a write queued behind another can run after
    // the chat has moved to another group.
    final targets = [
      for (final c in deps.session.groupCharacters)
        if (memberId == null || deps.session.characterIdFor(c) == memberId) c,
    ];
    // One write at a time: two saves of one member race on its avatar PNG.
    // The queue only orders them; each caller still sees its own error.
    final groups = deps.graph().groups;
    final write = groups.memberExtWrites.then(
      (_) => _writeGroupMemberExtensions(targets),
    );
    groups.memberExtWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeGroupMemberExtensions(List<CharacterCard> targets) async {
    if (deps.characters() != null) {
      final v2Service = V2CardService();
      // The chat's own handle: in the app the same file as
      // AppDatabase.instance(), re-pointed with it on a swap.
      final db = deps.db();

      for (final char in targets) {
        final ext = char.frontPorchExtensions ?? FrontPorchExtensions();
        ext.ensureStableId();
        char.frontPorchExtensions = ext;

        if (char.imagePath != null) {
          final file = File(char.imagePath!);
          if (await file.exists()) {
            await v2Service.saveCardAsPng(
              char,
              char.imagePath!,
              char.imagePath!,
            );
          }
        }

        if (char.dbId != null) {
          await db.updateGroupMember(
            GroupMembersCompanion(
              id: drift.Value(char.dbId!),
              frontPorchExtensions: drift.Value(jsonEncode(ext.toJson())),
            ),
          );
        }
      }
    }

    await deps.saveChat();
    deps.notify();
  }
}
