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

/// Test/analyze class only. `echo`, `ls`, and `test -f` are not verify.
/// Every `&&` / `||` / `;` segment is scanned so `cd pkg && flutter test`
/// receipts. `--help` / `-h` / dry-run anywhere in the command (or any
/// segment) fails the whole receipt — a later clean segment is not an
/// escape (`flutter test --help || flutter test`).
bool waifuLooksVerifyCommand(String command) {
  final lowered = command.trim().toLowerCase();
  final segments = lowered.split(RegExp(r'(?:&&|\|\||[;|\n])'));
  List<String> wordsOf(String raw) => raw
      .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  bool theater(List<String> words) => words.any((w) {
    if (w == '-h' || w == '--help' || w.startsWith('--help')) return true;
    return w == '--dry-run' ||
        w == '--dryrun' ||
        w == '--dry_run' ||
        w.startsWith('--dry-run') ||
        w.startsWith('--dryrun');
  });
  if (theater(wordsOf(lowered))) return false;
  for (final segment in segments) {
    if (theater(wordsOf(segment))) return false;
  }
  for (final segment in segments) {
    final words = wordsOf(segment);
    if (words.isEmpty) continue;
    var cmd = words.first;
    if (cmd.contains('/')) cmd = cmd.split('/').last;
    if (cmd == 'npx' && words.length > 1) {
      if (const {'vitest', 'jest', 'eslint'}.contains(words[1])) return true;
      continue;
    }
    if (cmd == 'flutter' || cmd == 'dart') {
      if (words.length > 1 && const {'test', 'analyze'}.contains(words[1])) {
        return true;
      }
      continue;
    }
    if (cmd == 'swift') {
      // Compile/package/export is not a check on any stack.
      if (words.length > 1 && words[1] == 'test') return true;
      continue;
    }
    if (cmd == 'cargo') {
      if (words.length > 1 && const {'test', 'clippy'}.contains(words[1])) {
        return true;
      }
      continue;
    }
    if (cmd == 'go') {
      if (words.length > 1 && words[1] == 'test') return true;
      continue;
    }
    if (cmd == 'make') {
      if (words.length > 1 &&
          const {'test', 'check', 'lint'}.contains(words[1])) {
        return true;
      }
      continue;
    }
    if (cmd == 'npm' || cmd == 'pnpm' || cmd == 'yarn') {
      if (words.length > 1 && words[1] == 'test') return true;
      if (words.length > 2 && words[1] == 'run') {
        final script = words[2];
        if (script == 'test' ||
            script == 'lint' ||
            script == 'analyze' ||
            script.startsWith('test:')) {
          return true;
        }
      }
      continue;
    }
    if (cmd == 'python' || cmd == 'python3' || cmd == 'py') {
      if (words.length > 2 &&
          words[1] == '-m' &&
          const {'pytest', 'unittest'}.contains(words[2])) {
        return true;
      }
      continue;
    }
    if (const {'pytest', 'vitest', 'jest'}.contains(cmd)) return true;
  }
  return false;
}
