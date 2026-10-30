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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// The v64 step: from v1.6.1 until each chat's own Afterglow switch came
/// back, saving a 1:1 chat wrote Porch Life's Afterglow over the chat's
/// switch. Switching a chat off settles its Lust and recovery, and only a
/// chat with Afterglow running scores Lust either way, so a 1:1 chat stored
/// off that holds Lust, a recovery or a warmth tail was on: it is switched
/// back on. Group chats never read their stored flag and are left alone.
///
/// Run as an upgrade step, not on open: a rewind can bring a stamp's Lust
/// back into a chat switched off since, and an open-time check would read
/// that as the old overwrite and switch the chat on again. A re-run (an
/// older build stamped the version down) finds only what such a build saved.
///
/// Returns how many chats it switched on.
Future<int> repairAfterglowOverwrittenOff(DatabaseConnectionUser db) async {
  try {
    final n = await db.customUpdate(
      'UPDATE sessions SET nsfw_cooldown_enabled = 1 '
      'WHERE group_id IS NULL AND nsfw_cooldown_enabled = 0 AND ('
      'arousal_level <> 0 '
      // Minutes once written; a row from before v55 counts its turns.
      'OR COALESCE(refractory_minutes_remaining, cooldown_turns_remaining, 0)'
      ' > 0 '
      'OR COALESCE(refractory_tail_minutes, 0) > 0)',
    );
    debugPrint('[DB] v64: Afterglow back on in $n chats');
    return n;
  } catch (e) {
    debugPrint('[DB] v64: Afterglow repair skipped: $e');
    return 0;
  }
}
