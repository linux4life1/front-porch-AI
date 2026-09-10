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

bool _verifyTheater(String command) {
  final lowered = command.toLowerCase();
  final rawSegs = _segments(command);
  final lowSegs = _segments(lowered);
  for (var s = 0; s < lowSegs.length; s++) {
    final words = _wordsOf(lowSegs[s]);
    if (words.isEmpty) continue;
    if (words.any(_isTheaterFlag)) return true;
    final peeled = _peelWrappers(words);
    if (peeled.words.length < 2) continue;
    final cmd = _runnerKey(peeled.words.first);
    final args = peeled.words.skip(1).toList();
    var rawArgs = args;
    if (s < rawSegs.length) {
      final rawPeeled = _peelWrappers(_wordsOf(rawSegs[s])).words;
      if (rawPeeled.length == peeled.words.length) {
        rawArgs = rawPeeled.skip(1).toList();
      }
    }
    if (cmd == 'make' && _makeArgvTheater(rawArgs)) return true;
    if (cmd == 'gradle' && args.contains('-m')) return true;
    if (cmd == 'gradle' && _gradleArgvTheater(args, rawArgs)) return true;
    if (cmd == 'mvn' && _mavenArgvTheater(args)) return true;
    if (cmd == 'ctest' && _ctestArgvTheater(args, rawArgs)) return true;
    if (cmd == 'go' && args.contains('-c')) return true;
    if (cmd == 'gradle' && _gradleInventoryTheater(args)) return true;
    if (cmd == 'gradle' && _excludesKnownCheck(cmd, args)) return true;
    if (_runnerFilterTheater(cmd, args)) return true;
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
  if (_mavenSkipProperty(w) || _polyglotSoftDone(w)) return true;
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

bool _mavenSkipProperty(String w) {
  if (!w.startsWith('-d')) return false;
  final body = w.substring(2);
  final eq = body.indexOf('=');
  final key = eq < 0 ? body : body.substring(0, eq);
  if (_kMavenFilterProps.contains(key)) {
    return eq < 0 ||
        _filteredSuiteTheater(body.substring(eq + 1), all: const {});
  }
  if (_kMavenWhenFalseProps.contains(key)) {
    return _gradlePropWhenFalse(w, '-d$key');
  }
  if (!_kMavenSkipProps.contains(key)) return false;
  return eq < 0 || body.substring(eq + 1) != 'false';
}

bool _filteredSuiteTheater(
  String val, {
  Set<String> all = const {},
  bool starOnly = false,
}) => starOnly ? val.isEmpty || val == '*' : val.isEmpty || !all.contains(val);

const _kFilterValueFlags = <String, Set<String>>{
  'cargo': {
    '--features',
    '-f',
    '--target',
    '--target-dir',
    '--manifest-path',
    '--message-format',
    '--color',
    '--config',
    '-j',
    '--jobs',
    '--profile',
    '--test-threads',
    '--format',
    '--shuffle-seed',
    '--logfile',
  },
  'go': {
    '-count',
    '-timeout',
    '-parallel',
    '-tags',
    '-exec',
    '-bench',
    '-coverprofile',
    '-mod',
    '-c',
  },
  'pytest': {
    '-n',
    '--numprocesses',
    '-o',
    '-p',
    '-c',
    '--maxfail',
    '--tb',
    '--basetemp',
    '--ignore',
    '--ignore-glob',
    '--rootdir',
    '--confcutdir',
    '--override-ini',
    '--durations',
  },
  'flutter': {
    '-d',
    '--device-id',
    '-j',
    '--concurrency',
    '--dart-define',
    '--flavor',
    '--coverage-path',
    '--timeout',
    '--reporter',
  },
  'dart': {
    '-j',
    '--concurrency',
    '--timeout',
    '--reporter',
    '-p',
    '--platform',
    '-c',
    '--compiler',
  },
  'phpunit': {'-c', '--configuration', '-d'},
  'rspec': {'-f', '--format', '-I', '--require'},
};

const _kSuiteFilterFlags = <String, Set<String>>{
  'gradle': {'--tests'},
  'dotnet': {'--filter'},
  'swift': {'--filter', '--skip'},
  'pytest': {'-k', '--keyword', '-m', '--sw', '--stepwise'},
  'flutter': {'--name', '--plain-name', '--tags', '--exclude-tags', '-t', '-x'},
  'dart': {'--name', '--plain-name', '--tags', '--exclude-tags', '-t', '-x'},
  'jest': {'-t', '--testnamepattern', '--testpathpattern'},
  'vitest': {'-t', '--testnamepattern', '--testpathpattern'},
  'phpunit': {'--filter', '--testsuite', '--group', '--exclude-group'},
  'rspec': {'-e', '--example', '--tag', '-t'},
  'npm': {'-t', '--testnamepattern', '--testpathpattern'},
  'pnpm': {'-t', '--testnamepattern', '--testpathpattern'},
  'yarn': {'-t', '--testnamepattern', '--testpathpattern'},
  'bun': {'-t', '--testnamepattern', '--testpathpattern', '--filter'},
  'deno': {'-t', '--filter'},
  'test': {'-t', '--testnamepattern', '--testpathpattern'},
};

const _kJsFailedOnly = {
  '--onlyfailures',
  '--onlychanged',
  '-o',
  '--lf',
  '--last-failed',
  '--ff',
  '--failed-first',
  '--changedsince',
  '--findrelatedtests',
  '--lastcommit',
  '--changed',
  '--related',
  '--watch',
  '--watchall',
  '--shard',
  '--project',
  '--selectprojects',
};
const _kFailedOnlyFlags = <String, Set<String>>{
  'pytest': {'--lf', '--last-failed', '--ff', '--failed-first'},
  'phpunit': {'-g', '--order-by', '--covers'},
  'jest': _kJsFailedOnly,
  'vitest': _kJsFailedOnly,
  'rspec': {'--only-failures', '--next-failure', '-n'},
  'npm': _kJsFailedOnly,
  'pnpm': _kJsFailedOnly,
  'yarn': _kJsFailedOnly,
  'bun': _kJsFailedOnly,
  'deno': _kJsFailedOnly,
  'test': _kJsFailedOnly,
  'mix': {'--failed', '--stale', '--only', '--exclude'},
  'go': {'-short', '-skip', '-list', '-fuzz'},
};

const _kCargoFeatureTargetGates = {
  '--no-default-features',
  '--features',
  '-f',
  '--target',
};

const _kCargoTestFilterFlags = {
  '-p',
  '--package',
  '--test',
  '--lib',
  '--bin',
  '--example',
  '--doc',
  '--bench',
  '--bins',
  '--benches',
  '--examples',
  '--tests',
  '--all-targets',
  '--workspace',
  '--exclude',
  '--all',
  '--ignored',
  '--skip',
  '--list',
  '--exclude-should-panic',
  '--exact',
  ..._kCargoFeatureTargetGates,
};

const _kCargoClippySubsetFlags = {
  '--lib',
  '--bin',
  '--bins',
  '--example',
  '--examples',
  '--bench',
  '--benches',
  '--test',
  '--tests',
  '--all-targets',
  '--exclude',
  '--doc',
  ..._kCargoFeatureTargetGates,
};

bool _runnerFilterTheater(String cmd, List<String> args) {
  final failedOnly = _failedOnlyFor(cmd);
  if (failedOnly != null &&
      args.any((t) => failedOnly.contains(t.split('=').first))) {
    return true;
  }
  String? flagVal(String name) {
    final eq = '$name=';
    final gluedShort =
        name.length == 2 && name.startsWith('-') && name[1] != '-';
    for (var i = 0; i < args.length; i++) {
      final t = args[i];
      if (t == name) {
        return i + 1 < args.length && !args[i + 1].startsWith('-')
            ? args[i + 1]
            : '';
      }
      if (t.startsWith(eq)) return t.substring(eq.length);
      if (gluedShort && t.startsWith(name) && t.length > name.length) {
        return t.substring(name.length);
      }
    }
    return null;
  }

  bool takesValue(String flag) {
    final bare = flag.contains('=') ? flag.split('=').first : flag;
    return (_kFilterValueFlags[cmd] ?? const <String>{}).contains(bare);
  }

  bool suiteFlags({Set<String> all = const {}}) {
    for (final f in _suiteFiltersFor(cmd) ?? const <String>{}) {
      final v = flagVal(f);
      if (v != null && _filteredSuiteTheater(v, all: all)) return true;
    }
    return false;
  }

  List<String>? afterCheck(String check) {
    var i = 0;
    while (i < args.length) {
      final t = args[i];
      if (t.startsWith('+') && t.length > 1) {
        i++;
        continue;
      }
      if (t.startsWith('-')) {
        if (takesValue(t) && !t.contains('=')) {
          i++;
          if (i < args.length && !args[i].startsWith('-')) i++;
        } else {
          i++;
        }
        continue;
      }
      return t == check ? args.sublist(i + 1) : null;
    }
    return null;
  }

  List<String> after(String check) => afterCheck(check) ?? const [];

  bool paths(List<String> rest, {Set<String> all = const {'.'}}) {
    for (var i = 0; i < rest.length; i++) {
      final t = rest[i];
      if (t == '--') continue;
      if (t.startsWith('-')) {
        if (takesValue(t) && !t.contains('=')) {
          if (i + 1 < rest.length && !rest[i + 1].startsWith('-')) i++;
        }
        continue;
      }
      if (!all.contains(t)) return true;
    }
    return false;
  }

  if (cmd == 'go') {
    final run = flagVal('-run');
    if (run != null &&
        _filteredSuiteTheater(run, all: const {'*', '.', '.*'})) {
      return true;
    }
    return paths(after('test'), all: const {'.', './...'});
  }
  if (suiteFlags(all: cmd == 'gradle' ? const {'*'} : const {})) {
    return true;
  }
  if (cmd == 'dotnet') {
    return args.any((t) => t.startsWith('--filter:'));
  }
  if (cmd == 'cargo') {
    final rest = afterCheck('test');
    if (rest == null) {
      if (afterCheck('clippy') == null) return false;
      for (final f in _kCargoClippySubsetFlags) {
        final v = flagVal(f);
        if (v != null && _filteredSuiteTheater(v, all: const {})) return true;
      }
      for (final f in const ['-p', '--package']) {
        final v = flagVal(f);
        if (v != null && _filteredSuiteTheater(v, starOnly: true)) return true;
      }
      return false;
    }
    for (final f in _kCargoTestFilterFlags) {
      final v = flagVal(f);
      if (v != null && _filteredSuiteTheater(v, all: const {})) return true;
    }
    for (var i = 0; i < rest.length; i++) {
      final t = rest[i];
      if (t == '--') continue;
      if (t.startsWith('-')) {
        if (takesValue(t) && !t.contains('=')) {
          if (i + 1 < rest.length && !rest[i + 1].startsWith('-')) i++;
        }
        continue;
      }
      return _filteredSuiteTheater(t, all: const {});
    }
    return false;
  }
  switch (cmd) {
    case 'pytest':
    case 'rspec':
    case 'phpunit':
    case 'jest':
    case 'vitest':
      return paths(args);
    case 'flutter':
    case 'dart':
    case 'mix':
    case 'deno':
    case 'bun':
      return paths(after('test'));
    case 'zig':
      if (args.contains('test')) {
        for (final f in const ['--test-filter', '-dtest-filter']) {
          final v = flagVal(f);
          if (v != null && _filteredSuiteTheater(v, all: const {})) return true;
        }
      }
      return paths(after('test'));
    case 'npm':
    case 'pnpm':
    case 'yarn':
      final rest = after('test');
      if (rest.isEmpty) return false;
      return paths(rest);
    default:
      return false;
  }
}

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
    if (excluded == null) continue;
    final token = excluded;
    if (_runnerTaskMatches(cmd, token)) return true;
    if (!token.contains('*') && !token.contains('?')) continue;
    final probes = <String>{
      ...?_kRunnerChecks[cmd],
      if (cmd == 'gradle') ...{
        'tests',
        'unittest',
        'testdebugunittest',
        ':app:test',
        ':app:check',
      },
    };
    if (probes.any((n) => _globMatches(token, n))) return true;
  }
  return false;
}

bool _globMatches(String glob, String name) {
  final buf = StringBuffer('^');
  for (final c in glob.split('')) {
    if (c == '*') {
      buf.write('.*');
    } else if (c == '?') {
      buf.write('.');
    } else {
      buf.write(RegExp.escape(c));
    }
  }
  buf.write(r'$');
  return RegExp(buf.toString(), caseSensitive: false).hasMatch(name);
}

/// Gradle `help` / `dependencies` / `components`. Not `--configuration-cache`.
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
