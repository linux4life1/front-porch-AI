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

import 'dart:io';

import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:path/path.dart' as p;

part 'waifu_verify_theater.dart';
part 'waifu_verify_maven.dart';

/// Project-native check names. Receipt is step.verify, a user-named
/// command, a repo marker, or a **known runner** — never “argv[1] is
/// test”. Echo / ls / help / dry-run / build-without-test never receipt.
class WaifuVerifyContext {
  const WaifuVerifyContext({
    this.stepVerify = const [],
    this.named = const [],
    this.markers = const [],
  });

  final List<String> stepVerify;
  final List<String> named;
  final List<String> markers;

  Iterable<String> get hints sync* {
    yield* stepVerify;
    yield* named;
    yield* markers;
  }
}

/// Runner → check subcommands only. `grep test` / `rm test` are not here.
/// Wrapper binaries (`gradlew`, `mvnw`) peel to these keys — not a
/// second map.
const _kRunnerChecks = <String, Set<String>>{
  'cargo': {'test', 'clippy'},
  'go': {'test'},
  'dart': {'test', 'analyze'},
  'flutter': {'test', 'analyze'},
  'mvn': {'test', 'verify'},
  'gradle': {'test', 'check'},
  'dotnet': {'test'},
  'mix': {'test'},
  'zig': {'test'},
  'swift': {'test'},
  'make': {'test', 'check', 'lint'},
  'ruff': {'check'},
  'npm': {'test', 'lint'},
  'pnpm': {'test', 'lint'},
  'yarn': {'test', 'lint'},
  'bun': {'test', 'lint'},
  'deno': {'test', 'lint'},
};

/// Project wrapper argv0 → the runner key in [_kRunnerChecks].
/// Same spirit as `poetry run` / `uv run`: the binary *is* the runner.
const _kRunnerAliases = {'gradlew': 'gradle', 'mvnw': 'mvn'};

/// These runners put flags before the task (`make -j8 test`).
/// Everyone else is subcommand-first (`cargo new test` is not a check).
const _kFlagBeforeTaskRunners = {'make', 'gradle', 'mvn'};

const _kCheckBins = {
  'pytest',
  'rspec',
  'phpunit',
  'ctest',
  'vitest',
  'jest',
  'eslint',
  'clippy',
};

const _kPackageScripts = {
  'test',
  'tests',
  'lint',
  'check',
  'analyze',
  'typecheck',
  'type-check',
};

const _kJsHosts = {'npm', 'pnpm', 'yarn', 'bun', 'deno'};

const _kEnvHosts = {'poetry', 'pipenv', 'uv', 'hatch', 'bundle'};

const _kBuildOnly = {
  'build',
  'compile',
  'package',
  'export',
  'assemble',
  'publish',
  'bundle',
};

const _kDenyCmds = {'echo', 'ls', 'printf', 'true', 'false', 'cat', 'pwd'};

/// Unix utilities that are never a project check — even if argv[1] is
/// `test` or a plan quote names them. Not a second club: the known-runner
/// map simply does not include these heads.
const _kNeverCheckBins = {
  'rm',
  'mv',
  'cp',
  'mkdir',
  'rmdir',
  'unlink',
  'grep',
  'egrep',
  'fgrep',
  'rg',
  'sed',
  'awk',
  'git',
  'wc',
  'find',
  'chmod',
  'chown',
  'kill',
  'touch',
  'ln',
  'head',
  'tail',
  'sort',
  'tr',
  'cut',
  'tee',
  'xargs',
  'dd',
  'install',
};

const _kShellTestFlags = {'-f', '-d', '-e', '-s', '-w', '-r', '-x', '-z', '-n'};

/// ONE receipt. Ask ([waifuBashMutates]) and `tested` both call this
/// with the same [context].
bool waifuLooksVerifyCommand(String command, {WaifuVerifyContext? context}) {
  final lowered = command.trim().toLowerCase();
  if (lowered.isEmpty) return false;
  if (_verifyTheater(command.trim())) return false;
  if (_isBuildWithoutTest(lowered)) return false;
  if (context != null) {
    for (final hint in context.hints) {
      if (_commandFulfills(lowered, hint)) return true;
    }
  }
  return _looksKnownCheck(lowered);
}

bool waifuLooksVerifySegment(String segment, {WaifuVerifyContext? context}) =>
    waifuLooksVerifyCommand(segment, context: context);

List<String> waifuNamedVerifyCommands(String task) {
  final found = <String>{};
  for (final m in RegExp(r'''[`"'']([^`"']+)[`"'']''').allMatches(task)) {
    final cmd = m.group(1)!.trim();
    if (cmd.isEmpty) continue;
    final lowered = cmd.toLowerCase();
    if (_verifyTheater(cmd) || _isBuildWithoutTest(lowered)) continue;
    final words = _wordsOf(lowered);
    if (words.isEmpty || _denyCmd(words.first) || _neverCheck(words)) {
      continue;
    }
    found.add(cmd);
  }
  return found.toList();
}

Future<List<String>> waifuVerifyMarkerCommands(String root) async {
  Future<bool> has(String rel) => File(p.join(root, rel)).exists();
  final out = <String>[];
  if (await has('Cargo.toml')) out.addAll(['cargo test', 'cargo clippy']);
  if (await has('package.json')) {
    out.addAll(['npm test', 'pnpm test', 'yarn test', 'bun test']);
  }
  if (await has('go.mod')) out.add('go test');
  if (await has('pyproject.toml') ||
      await has('pytest.ini') ||
      await has('requirements.txt')) {
    out.add('pytest');
  }
  if (await has('pubspec.yaml')) {
    out.addAll(['dart test', 'dart analyze', 'flutter test']);
  }
  if (await has('pom.xml')) out.add('mvn test');
  if (await has('mvnw') || await has('mvnw.cmd')) out.add('./mvnw test');
  if (await has('build.gradle') || await has('build.gradle.kts')) {
    out.add('gradle test');
  }
  if (await has('gradlew') || await has('gradlew.bat')) {
    out.add('./gradlew test');
  }
  if (await has('mix.exs')) out.add('mix test');
  if (await has('Gemfile')) out.add('rspec');
  if (await has('composer.json')) out.add('phpunit');
  if (await has('CMakeLists.txt')) {
    out.addAll(['ctest', 'cmake --build . --target test']);
  }
  if (await has('build.zig')) out.add('zig test');
  if (await has('Package.swift')) out.add('swift test');
  if (await has('tsconfig.json')) out.add('tsc --noEmit');
  if (await has('Makefile') || await has('makefile')) {
    out.add('make test');
  }
  return out;
}

Future<WaifuVerifyContext> waifuBuildVerifyContext({
  required String folderRoot,
  required String task,
  WaifuPlan? plan,
}) async {
  final steps = <String>[
    if (plan != null)
      for (final step in plan.steps)
        if (step.verify.trim().isNotEmpty) step.verify.trim(),
  ];
  return WaifuVerifyContext(
    stepVerify: steps,
    named: waifuNamedVerifyCommands(task),
    markers: await waifuVerifyMarkerCommands(folderRoot),
  );
}

bool _isBuildWithoutTest(String lowered) {
  var sawBuild = false;
  var sawCheck = false;
  for (final segment in _segments(lowered)) {
    final words = _wordsOf(segment);
    if (words.isEmpty || _denyCmd(words.first)) continue;
    if (_looksKnownCheck(segment)) sawCheck = true;
    if (words.any(_kBuildOnly.contains)) sawBuild = true;
  }
  return sawBuild && !sawCheck;
}

bool _looksKnownCheck(String lowered) {
  for (final segment in _segments(lowered)) {
    if (_segmentIsKnownCheck(segment)) return true;
  }
  return false;
}

/// Known runner / wrapper / typecheck. Never “second token is test”.
bool _segmentIsKnownCheck(String segment) {
  final words = _wordsOf(segment);
  if (words.isEmpty) return false;
  if (_denyCmd(words.first) || _neverCheck(words) || _isShellTest(words)) {
    return false;
  }
  if (_isCmakeTestTarget(words) || _isTscNoEmit(words)) return true;
  final peeled = _peelWrappers(words);
  if (peeled.words.isEmpty) return false;
  final cmd = _base(peeled.words.first);
  if (_denyCmd(cmd)) return false;
  if (cmd == 'tsc') return _isTscNoEmit(peeled.words);
  if (_kCheckBins.contains(cmd)) return true;
  if (_argvHasKnownCheck(peeled.words)) return true;
  if (peeled.fromPackageRun) {
    final script = peeled.words.first;
    return _kPackageScripts.contains(script) || script.startsWith('test:');
  }
  return false;
}

bool _isCmakeTestTarget(List<String> words) {
  if (_base(words.first) != 'cmake') return false;
  for (var i = 0; i < words.length - 1; i++) {
    if (words[i] != '--target' && words[i] != '-t') continue;
    final t = words[i + 1];
    if (t == 'test' || t == 'tests') return true;
  }
  return false;
}

bool _isTscNoEmit(List<String> words) {
  if (_base(words.first) != 'tsc') return false;
  return words.any((w) => w == '--noemit' || w == '--no-emit');
}

({List<String> words, bool fromPackageRun}) _peelWrappers(List<String> words) {
  var out = words;
  var fromPackageRun = false;
  final cmd = _base(words.first);
  if (const {'python', 'python3', 'py'}.contains(cmd) &&
      words.length > 2 &&
      words[1] == '-m') {
    out = words.sublist(2);
  } else if (_kJsHosts.contains(cmd) &&
      words.length > 2 &&
      (words[1] == 'run' || words[1] == 'exec')) {
    out = words.sublist(2);
    fromPackageRun = words[1] == 'run';
  } else if (cmd == 'npx' && words.length > 1) {
    out = words.sublist(1);
  } else if (_kEnvHosts.contains(cmd) &&
      words.length > 2 &&
      (words[1] == 'run' || words[1] == 'exec')) {
    out = words.sublist(2);
  }
  if (out.isNotEmpty) {
    final key = _runnerKey(out.first);
    if (key != out.first) out = [key, ...out.skip(1)];
  }
  return (words: out, fromPackageRun: fromPackageRun);
}

bool _commandFulfills(String command, String expected) {
  final want = expected.trim().toLowerCase();
  if (want.isEmpty) return false;
  final wantWords = _wordsOf(want);
  if (wantWords.isEmpty ||
      _denyCmd(wantWords.first) ||
      _neverCheck(wantWords)) {
    return false;
  }
  if (command == want) return true;
  final wantCanon = _peelWrappers(wantWords).words;
  for (final segment in _segments(command)) {
    final got = segment.trim();
    if (got.isEmpty) continue;
    final words = _wordsOf(got);
    if (words.isEmpty ||
        _denyCmd(words.first) ||
        _neverCheck(words) ||
        _isShellTest(words)) {
      continue;
    }
    if (got == want || got.startsWith('$want ')) return true;
    final peeled = _peelWrappers(words);
    if (_wordsStartWith(peeled.words, wantCanon) ||
        _wordsStartWith(words, wantWords) ||
        _hintTaskFulfilled(peeled.words, wantCanon)) {
      return true;
    }
  }
  return false;
}

/// Same runner + named check token appears after flags (`make test`
/// fulfills `make -j8 test`; `gradle test` fulfills `:app:test`).
bool _hintTaskFulfilled(List<String> got, List<String> want) {
  if (!_argvHasKnownCheck(got)) return false;
  if (got.length < 2 || want.length < 2) return false;
  final cmd = _runnerKey(got.first);
  if (cmd != _runnerKey(want.first)) return false;
  if (_kRunnerChecks[cmd] == null) return false;
  final needed = want.skip(1).where((t) => !t.startsWith('-'));
  if (needed.isEmpty) return false;
  final have = got.skip(1).where((t) => !t.startsWith('-'));
  for (final n in needed) {
    if (have.contains(n)) continue;
    if (cmd == 'gradle' &&
        n == 'test' &&
        have.any(
          (t) =>
              t.endsWith(':test') ||
              (t.endsWith('unittest') &&
                  (t.startsWith('test') || t.contains(':'))),
        )) {
      continue;
    }
    return false;
  }
  return true;
}

bool _wordsStartWith(List<String> words, List<String> prefix) {
  if (prefix.isEmpty || words.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (words[i] != prefix[i]) return false;
  }
  return true;
}

/// After peel+alias: flag-before-task runners scan for a known check;
/// subcommand-first runners require that check as the first non-flag
/// (`+toolchain` tokens are skipped, not treated as the subcommand).
bool _argvHasKnownCheck(List<String> peeled) {
  if (peeled.length < 2) return false;
  final cmd = _runnerKey(peeled.first);
  if (_kRunnerChecks[cmd] == null) return false;
  final args = peeled.skip(1);
  if (_kFlagBeforeTaskRunners.contains(cmd)) {
    return args.any((t) => _runnerTaskMatches(cmd, t));
  }
  if (cmd == 'zig' && args.contains('build') && args.contains('test')) {
    return true;
  }
  for (final t in args) {
    if (t.startsWith('-') || (t.startsWith('+') && t.length > 1)) continue;
    return _runnerTaskMatches(cmd, t);
  }
  return false;
}

bool _runnerTaskMatches(String cmd, String token) {
  if (token.startsWith('-')) return false;
  final checks = _kRunnerChecks[cmd];
  if (checks != null && checks.contains(token)) return true;
  if (cmd != 'gradle') return false;
  if (token.endsWith(':test') || token.endsWith(':check')) return true;
  return token.endsWith('unittest') &&
      (token.startsWith('test') || token.contains(':'));
}

String _base(String cmd) => p.basename(cmd.replaceAll('\\', '/'));

/// `./gradlew` / `mvnw.cmd` → `gradle` / `mvn`. Identity for real runners.
String _runnerKey(String cmd) {
  var name = _base(cmd);
  if (name.endsWith('.bat') || name.endsWith('.cmd')) {
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
  }
  return _kRunnerAliases[name] ?? name;
}

bool _denyCmd(String cmd) => _kDenyCmds.contains(_base(cmd));

bool _neverCheck(List<String> words) =>
    words.isNotEmpty && _kNeverCheckBins.contains(_base(words.first));

bool _isShellTest(List<String> words) {
  return _base(words.first) == 'test' && words.any(_kShellTestFlags.contains);
}

List<String> _wordsOf(String raw) => raw
    .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

List<String> _segments(String command) =>
    command.split(RegExp(r'(?:&&|\|\||[;|\n])'));

/// CTest name / label / index / fixture / file filters and `-n`.
/// `-I` is index (raw). Any `-F*` short / `--fixture-` long.
/// `--rerun-failed`; `--no-tests` bare/empty/`=ignore` (`=error` full).
bool _ctestArgvTheater(List<String> args, List<String> rawArgs) {
  for (var i = 0; i < args.length; i++) {
    final t = args[i];
    if (t == '-n' || t == '-r' || t == '-e' || t == '-l') return true;
    if (t.startsWith('--tests-regex') ||
        t.startsWith('--exclude-regex') ||
        t.startsWith('--label-regex') ||
        t.startsWith('--label-exclude') ||
        t.startsWith('--exclude-label') ||
        t.startsWith('--tests-from-file') ||
        t.startsWith('--exclude-from-file') ||
        t.startsWith('--fixture-') ||
        t.startsWith('--rerun-failed') ||
        t == '--no-tests' ||
        t == '--no-tests=' ||
        t.startsWith('--no-tests=ignore')) {
      return true;
    }
    if (!t.startsWith('--') &&
        (t.startsWith('-r') && t.length > 2 ||
            t.startsWith('-e') && t.length > 2 ||
            t.startsWith('-l') && t.length > 2 ||
            t.startsWith('-f') && t.length >= 3)) {
      return true;
    }
    final raw = i < rawArgs.length ? rawArgs[i] : t;
    if (raw.length >= 2 &&
        raw[0] == '-' &&
        raw[1] == 'I' &&
        !raw.startsWith('--')) {
      return true;
    }
  }
  return false;
}

/// `test` / `test:*` after `npm run` share [_kJsFailedOnly].
Set<String>? _failedOnlyFor(String cmd) =>
    _kFailedOnlyFlags[cmd] ?? (cmd.startsWith('test:') ? _kJsFailedOnly : null);
