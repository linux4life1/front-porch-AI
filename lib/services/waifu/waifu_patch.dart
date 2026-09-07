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

class WaifuPatchResult {
  const WaifuPatchResult.applied(this.text) : error = null;
  const WaifuPatchResult.failed(this.error) : text = null;

  final String? text;
  final String? error;
  bool get ok => text != null && error == null;
}

/// Apply one-file unified hunks without spawning `patch` or `git apply`.
///
/// Supports ordinary `@@ -a,b +c,d @@` diffs and the familiar
/// `*** Begin Patch` / `*** Update File` envelope. Every old/context block
/// must match exactly once, so a vague model patch fails without a partial
/// write.
WaifuPatchResult waifuApplyPatch({
  required String before,
  required String patch,
}) {
  var raw = patch.replaceAll('\r\n', '\n');
  while (raw.endsWith('\n')) {
    raw = raw.substring(0, raw.length - 1);
  }
  if (raw.trim().isEmpty) {
    return const WaifuPatchResult.failed('apply_patch: patch is empty');
  }
  if (raw.contains('*** Delete File:')) {
    return const WaifuPatchResult.failed(
      'apply_patch: delete files with an explicit user-reviewed command',
    );
  }

  final hunks = <({String header, List<String> lines})>[];
  ({String header, List<String> lines})? active;
  final ungrouped = <String>[];
  for (final line in raw.split('\n')) {
    if (line == '*** Begin Patch' ||
        line == '*** End Patch' ||
        line.startsWith('*** Update File:') ||
        line.startsWith('*** Add File:') ||
        line.startsWith('*** Delete File:')) {
      continue;
    }
    if (line.startsWith('--- ') || line.startsWith('+++ ')) continue;
    if (line.startsWith('@@')) {
      active = (header: line, lines: <String>[]);
      hunks.add(active);
      continue;
    }
    if (line == r'\ No newline at end of file') continue;
    if (active != null) {
      active.lines.add(line);
    } else if (line.startsWith('+') ||
        line.startsWith('-') ||
        line.startsWith(' ')) {
      ungrouped.add(line);
    }
  }
  if (hunks.isEmpty && ungrouped.isNotEmpty) {
    hunks.add((header: '@@', lines: ungrouped));
  }
  if (hunks.isEmpty) {
    return const WaifuPatchResult.failed(
      'apply_patch: no unified diff hunks found',
    );
  }

  final keptTrailingNewline = before.endsWith('\n') || patch.endsWith('\n');
  final lines = before.isEmpty ? <String>[] : before.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty && before.endsWith('\n')) {
    lines.removeLast();
  }

  for (final hunk in hunks) {
    final oldLines = <String>[];
    final newLines = <String>[];
    for (final line in hunk.lines) {
      if (line.isEmpty) {
        return const WaifuPatchResult.failed(
          'apply_patch: every hunk line needs a space, +, or - prefix',
        );
      }
      final body = line.substring(1);
      switch (line[0]) {
        case ' ':
          oldLines.add(body);
          newLines.add(body);
          break;
        case '-':
          oldLines.add(body);
          break;
        case '+':
          newLines.add(body);
          break;
        default:
          return WaifuPatchResult.failed(
            'apply_patch: invalid hunk line "$line"',
          );
      }
    }

    if (oldLines.isEmpty) {
      final hinted = RegExp(r'\+(\d+)').firstMatch(hunk.header);
      final insertion = hinted == null
          ? lines.length
          : (int.parse(hinted.group(1)!) - 1).clamp(0, lines.length).toInt();
      lines.insertAll(insertion, newLines);
      continue;
    }

    final matches = <int>[];
    for (var start = 0; start + oldLines.length <= lines.length; start++) {
      var same = true;
      for (var offset = 0; offset < oldLines.length; offset++) {
        if (lines[start + offset] != oldLines[offset]) {
          same = false;
          break;
        }
      }
      if (same) matches.add(start);
    }
    if (matches.length != 1) {
      return WaifuPatchResult.failed(
        'apply_patch: hunk must match exactly once (found ${matches.length})',
      );
    }
    lines.replaceRange(
      matches.single,
      matches.single + oldLines.length,
      newLines,
    );
  }

  final after = '${lines.join('\n')}${keptTrailingNewline ? '\n' : ''}';
  if (after == before) {
    return const WaifuPatchResult.failed('apply_patch: patch made no changes');
  }
  return WaifuPatchResult.applied(after);
}
