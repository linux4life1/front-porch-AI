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

part of 'waifu_verify.dart';

/// Compile / list / dry-run / help — not a real execute. One gate.
bool _verifyTheater(String lowered) {
  for (final segment in _segments(lowered)) {
    final words = _wordsOf(segment);
    if (words.isEmpty) continue;
    if (words.any(_isTheaterFlag)) return true;
    final peeled = _peelWrappers(words);
    if (peeled.words.length < 2) continue;
    final cmd = _runnerKey(peeled.words.first);
    final args = peeled.words.skip(1).toList();
    if (cmd == 'make' && (args.contains('-n') || args.contains('-q'))) {
      return true;
    }
    if (cmd == 'gradle' && args.contains('-m')) return true;
    if (cmd == 'ctest' && args.contains('-n')) return true;
    if (cmd == 'go' && args.contains('-c')) return true;
    if (cmd == 'gradle' && _gradleInventoryTheater(args)) return true;
    if (cmd == 'gradle' && _excludesKnownCheck(cmd, args)) return true;
    if (cmd == 'go') {
      for (var i = 0; i < args.length; i++) {
        final t = args[i];
        if (t == '-exec' &&
            i + 1 < args.length &&
            _base(args[i + 1]) == 'true') {
          return true;
        }
        if (t.startsWith('-exec=') && _base(t.split('=').last) == 'true') {
          return true;
        }
      }
    }
  }
  return false;
}

bool _isTheaterFlag(String w) {
  if (w == '-h' || w == '--help' || w.startsWith('--help')) return true;
  if (_mavenSkipProperty(w)) return true;
  if (w == '--co' ||
      w == '--listtests' ||
      w == '--listtestfiles' ||
      w == '--just-print' ||
      w == '--recon') {
    return true;
  }
  return w.startsWith('--show-only') ||
      w.startsWith('--collect-only') ||
      w.startsWith('--list-tests') ||
      w.startsWith('--list-suites') ||
      w.startsWith('--list-groups') ||
      w.startsWith('--no-run') ||
      w.startsWith('--question') ||
      w.startsWith('--dry-run') ||
      w.startsWith('--dryrun') ||
      w.startsWith('--dry_run');
}

/// `-DskipTests` / `-Dmaven.test.skip` skip the suite. `=false` still runs.
bool _mavenSkipProperty(String w) {
  if (w == '-dskiptests' || w.startsWith('-dskiptests=')) {
    return !w.endsWith('=false');
  }
  if (w == '-dmaven.test.skip' || w.startsWith('-dmaven.test.skip=')) {
    return !w.endsWith('=false');
  }
  return false;
}

/// Gradle `-x test` / `--exclude-task test` (or `:app:test`, unit-test
/// tasks). Excluding a non-check (`-x lint`) does not kill `test`.
bool _excludesKnownCheck(String cmd, List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final t = args[i];
    String? excluded;
    if (t == '-x' || t == '--exclude-task') {
      if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
        excluded = args[i + 1];
      }
    } else if (t.startsWith('--exclude-task=')) {
      excluded = t.substring('--exclude-task='.length);
    }
    if (excluded != null && _runnerTaskMatches(cmd, excluded)) return true;
  }
  return false;
}

/// Gradle `help` / `dependencies` / `components`, including `:app:help`.
/// `--configuration-cache` is a real run flag — not this.
bool _gradleInventoryTheater(Iterable<String> args) {
  final task = args.where((t) => !t.startsWith('-')).firstOrNull;
  final base = task?.split(':').last;
  if (base == 'help' || base == 'dependencies' || base == 'components') {
    return true;
  }
  final inventoryFlag = args.any(
    (t) =>
        t == '--configuration' ||
        t.startsWith('--configuration=') ||
        t == '--task' ||
        t.startsWith('--task='),
  );
  return inventoryFlag && (task == null || !_runnerTaskMatches('gradle', task));
}
