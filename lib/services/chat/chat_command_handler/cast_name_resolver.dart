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

import 'package:front_porch_ai/models/models.dart';

/// Parse an optional `--full` / `--lite` (or `-full` / `-lite`) flag out of
/// the `/join` arguments, returning whether a full join was requested and the
/// remaining name text. Lite is the default. The flag may appear anywhere in
/// the arguments (e.g. `--full Mara` or `Mara --full`).
({bool full, String name}) parseJoinFlags(String args) {
  var full = false;
  final kept = <String>[];
  for (final token in args.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    switch (token.toLowerCase()) {
      case '--full':
      case '-full':
        full = true;
      case '--lite':
      case '-lite':
        full = false;
      default:
        kept.add(token);
    }
  }
  return (full: full, name: kept.join(' ').trim());
}

/// Name resolution shared by the Scene Guest slash commands. Emits its inline
/// errors through the injected system-message callback.
class CastNameResolver {
  CastNameResolver(this._onSystemMessage);

  final void Function(String message) _onSystemMessage;

  /// Exact name, then unique substring, against [porch] (host + present guests).
  CharacterCard? resolvePorchSpeaker(
    String wanted,
    List<CharacterCard> porch,
    String porchNames,
  ) {
    final lower = wanted.trim().toLowerCase();
    final exact = [
      for (final c in porch)
        if (c.name.toLowerCase() == lower) c,
    ];
    if (exact.length == 1) return exact.first;
    if (exact.length > 1) {
      _onSystemMessage(
        '⚠ "$wanted" matches more than one person. Use the full name. '
        'On the porch: $porchNames.',
      );
      return null;
    }
    final partial = [
      for (final c in porch)
        if (c.name.toLowerCase().contains(lower)) c,
    ];
    if (partial.length == 1) return partial.first;
    if (partial.length > 1) {
      _onSystemMessage(
        '⚠ "$wanted" matches more than one person. Use the full name. '
        'On the porch: $porchNames.',
      );
      return null;
    }
    _onSystemMessage(
      '⚠ "$wanted" is not on the porch. '
      'Present: $porchNames.',
    );
    return null;
  }

  /// Resolve a group member by name from `/exit` and `/speak` args — exact match,
  /// then unique case-insensitive substring. Emits the right inline error (and
  /// returns null) for empty / ambiguous / unknown input. [command] names the
  /// slash command and [emptyVerb] the action, so the empty-args prompt reads
  /// naturally (`Who should leave? Use /exit <name>` vs the `/speak` wording).
  CharacterCard? resolveGroupMember(
    String args,
    List<CharacterCard> members, {
    required String command,
    required String emptyVerb,
  }) {
    final names = members.map((m) => m.name).join(', ');
    final wanted = args.trim().toLowerCase();
    if (wanted.isEmpty) {
      _onSystemMessage(
        '⚠ Who should $emptyVerb? Use /$command <name> — $names.',
      );
      return null;
    }
    for (final m in members) {
      if (m.name.toLowerCase() == wanted) return m;
    }
    final partial = members
        .where((m) => m.name.toLowerCase().contains(wanted))
        .toList();
    if (partial.length > 1) {
      _onSystemMessage(
        '⚠ "$args" matches multiple members '
        '(${partial.map((m) => m.name).join(', ')}). Use the full name.',
      );
      return null;
    }
    if (partial.length == 1) return partial.first;
    _onSystemMessage('⚠ No group member named "$args" is here.');
    return null;
  }
}
