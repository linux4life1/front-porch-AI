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

import 'package:front_porch_ai/services/waifu/waifu_session.dart';

/// Unique relative paths in write order. One path can appear twice if
/// they patched it, then wrote again — chrome still lists it once.
List<String> waifuTurnTouchedPaths(Iterable<WaifuWriteRecord> writes) {
  final seen = <String>{};
  final out = <String>[];
  for (final rec in writes) {
    final path = rec.relativePath.trim();
    if (path.isEmpty || !seen.add(path)) continue;
    out.add(path);
  }
  return out;
}

/// "Mira changed lib/a.dart" or "Mira changed 3 files": the turn's
/// receipt, told with the coworker's name.
String waifuTurnReceiptHeadline(
  Iterable<WaifuWriteRecord> writes, {
  required String name,
}) {
  final paths = waifuTurnTouchedPaths(writes);
  if (paths.isEmpty) return '';
  if (paths.length == 1) return '$name changed ${paths.single}';
  return '$name changed ${paths.length} files';
}

String waifuTurnVerifyLine(Iterable<String> paths) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in paths) {
    final path = raw.trim();
    if (path.isEmpty || !seen.add(path)) continue;
    out.add(path);
  }
  if (out.isEmpty) return '';
  return 'Verified: ${out.join(', ')}';
}

bool waifuTurnReceiptVisible({
  WaifuWriteRecord? lastWrite,
  Iterable<WaifuWriteRecord> writes = const [],
}) => lastWrite != null || waifuTurnTouchedPaths(writes).isNotEmpty;
