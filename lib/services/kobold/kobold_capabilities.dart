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

/// What the installed KoboldCpp understands. An unknown version (no version
/// file yet) is treated as current: the app downloads the engine itself.
class KoboldCapabilities {
  const KoboldCapabilities({
    this.quantKvAsText = true,
    this.moeCpu = true,
    this.smartCache = true,
  });

  static const KoboldCapabilities current = KoboldCapabilities();

  /// Cache type by name ("q8_0"). Before 1.112 only the index was accepted.
  final bool quantKvAsText;

  /// `moecpu` works for current MoE models from 1.111.1.
  final bool moeCpu;

  /// Chat snapshots in system memory arrived in 1.104.
  final bool smartCache;

  factory KoboldCapabilities.forVersion(String? version) {
    final v = _parse(version);
    if (v == null) return current;
    return KoboldCapabilities(
      quantKvAsText: _atLeast(v, const [1, 112, 0]),
      moeCpu: _atLeast(v, const [1, 111, 1]),
      smartCache: _atLeast(v, const [1, 104, 0]),
    );
  }

  static List<int>? _parse(String? version) {
    final m = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(version ?? '');
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
    ];
  }

  static bool _atLeast(List<int> v, List<int> min) {
    for (var i = 0; i < 3; i++) {
      if (v[i] != min[i]) return v[i] > min[i];
    }
    return true;
  }
}
