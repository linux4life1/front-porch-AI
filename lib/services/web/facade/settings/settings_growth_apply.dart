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

// The Growth Rings / Boons & Bogies switches a web settings body may carry
// (docs/design/boons-and-bogies.md §8). Split out of settings_writer to keep
// that file under the size law.

import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// Applies the booleans in [realism] that belong to [mem]. Absent keys are
/// older clients and are left alone.
Future<void> applyGrowthBooleans(
  MemorySettings mem,
  Map<dynamic, dynamic> realism,
) async {
  final setters = <String, Future<void> Function(bool)>{
    'characterEvolutionEnabled': mem.setCharacterEvolutionEnabled,
    'boonsBogiesEnabled': mem.setBoonsBogiesEnabled,
    'bogeyRollsEnabled': mem.setBogeyRollsEnabled,
    'milestonePopupsEnabled': mem.setMilestonePopupsEnabled,
  };
  for (final e in setters.entries) {
    final v = realism[e.key];
    if (v is bool) await e.value(v);
  }
}
