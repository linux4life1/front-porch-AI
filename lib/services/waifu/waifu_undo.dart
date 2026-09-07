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

import 'dart:io';

import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';

/// Undo/redo of Waifu Coder write/edit records only — not git reset of user work.
class WaifuUndo {
  final _undo = <WaifuWriteRecord>[];
  final _redo = <WaifuWriteRecord>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(WaifuWriteRecord rec) {
    _undo.add(rec);
    _redo.clear();
  }

  Future<WaifuWriteRecord?> undo(
    String root, {
    WaifuPathMode pathMode = WaifuPathMode.folderJail,
  }) async {
    if (_undo.isEmpty) return null;
    final rec = _undo.removeLast();
    await _apply(
      root,
      rec.relativePath,
      rec.before,
      deleteIfEmpty: rec.before.isEmpty,
      pathMode: pathMode,
    );
    _redo.add(rec);
    return rec;
  }

  Future<WaifuWriteRecord?> redo(
    String root, {
    WaifuPathMode pathMode = WaifuPathMode.folderJail,
  }) async {
    if (_redo.isEmpty) return null;
    final rec = _redo.removeLast();
    await _apply(
      root,
      rec.relativePath,
      rec.after,
      deleteIfEmpty: false,
      pathMode: pathMode,
    );
    _undo.add(rec);
    return rec;
  }

  Future<void> _apply(
    String root,
    String relative,
    String bytes, {
    required bool deleteIfEmpty,
    required WaifuPathMode pathMode,
  }) async {
    final hit = await WaifuJail.resolveLive(root, relative, pathMode: pathMode);
    if (!hit.ok) return;
    if (waifuIsProtectedSecretPath(hit.path!) ||
        waifuIsCriticalSystemMutationPath(hit.path!, workingDirectory: root)) {
      return;
    }
    final file = File(hit.path!);
    if (deleteIfEmpty && bytes.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(bytes);
  }
}
