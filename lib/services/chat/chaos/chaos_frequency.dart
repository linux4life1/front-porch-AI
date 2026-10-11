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

/// How often Chance Time pops on its own. Each user turn adds [growth] to the
/// pressure gauge; the roll fires below `base + pressure`. After an event
/// lands, [cooldown] user turns pass with no growth and no roll.
enum ChaosFrequency {
  rare(base: 2, growth: 2, cooldown: 4, label: 'Rare'),
  normal(base: 5, growth: 5, cooldown: 2, label: 'Normal'),
  wild(base: 10, growth: 10, cooldown: 0, label: 'Wild');

  const ChaosFrequency({
    required this.base,
    required this.growth,
    required this.cooldown,
    required this.label,
  });

  final int base;
  final int growth;
  final int cooldown;
  final String label;

  /// Parses a stored name; anything unknown is [normal].
  static ChaosFrequency fromName(String? name) => ChaosFrequency.values
      .firstWhere((f) => f.name == name, orElse: () => ChaosFrequency.normal);
}
