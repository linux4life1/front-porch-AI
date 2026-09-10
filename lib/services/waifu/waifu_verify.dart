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

/// Project-native check names. Receipt is step.verify, a user-named
/// command, a repo marker, or the test/analyze class — not a VIP runner
/// club. Echo / ls / help / dry-run / build-without-test never receipt.
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

const _kVerifyVerbs = {
  'test',
  'tests',
  'analyze',
  'lint',
  'check',
  'clippy',
  'pytest',
  'unittest',
  'rspec',
  'phpunit',
  'ctest',
  'vitest',
  'jest',
  'eslint',
};

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

const _kShellTestFlags = {'-f', '-d', '-e', '-s', '-w', '-r', '-x', '-z', '-n'};

/// Hosts that wrap a real check (`poetry run pytest`, `bundle exec rspec`).
/// Not a VIP receipt club — payload after these still has to be a verify
/// verb or a context hint.
const _kRunnerHosts = {
  'npx',
  'npm',
  'pnpm',
  'yarn',
  'bun',
  'deno',
  'poetry',
  'pipenv',
  'uv',
  'hatch',
  'bundle',
};

const _kRunnerWords = {'run', 'exec'};

bool waifuLooksVerifyCommand(String command, {WaifuVerifyContext? context}) {
  final lowered = command.trim().toLowerCase();
  if (lowered.isEmpty) return false;
  if (_verifyTheater(lowered)) return false;
  if (_isBuildWithoutTest(lowered)) return false;
  if (context != null) {
    for (final hint in context.hints) {
      if (_commandFulfills(lowered, hint)) return true;
    }
  }
  return _looksTestAnalyzeClass(lowered);
}

bool waifuLooksVerifySegment(String segment, {WaifuVerifyContext? context}) =>
    waifuLooksVerifyCommand(segment, context: context);

List<String> waifuNamedVerifyCommands(String task) {
  final found = <String>{};
  for (final m in RegExp(r'''[`"'']([^`"']+)[`"'']''').allMatches(task)) {
    final cmd = m.group(1)!.trim();
    if (waifuLooksVerifyCommand(cmd)) found.add(cmd);
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
  if (await has('build.gradle') || await has('build.gradle.kts')) {
    out.add('gradle test');
  }
  if (await has('mix.exs')) out.add('mix test');
  if (await has('Gemfile')) out.add('rspec');
  if (await has('composer.json')) out.add('phpunit');
  if (await has('CMakeLists.txt')) out.add('ctest');
  if (await has('build.zig')) out.add('zig test');
  if (await has('Package.swift')) out.add('swift test');
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

bool _verifyTheater(String lowered) {
  for (final segment in _segments(lowered)) {
    final words = _wordsOf(segment);
    if (words.any((w) {
      if (w == '-h' || w == '--help' || w.startsWith('--help')) return true;
      return w == '--dry-run' ||
          w == '--dryrun' ||
          w == '--dry_run' ||
          w.startsWith('--dry-run') ||
          w.startsWith('--dryrun');
    })) {
      return true;
    }
  }
  return false;
}

bool _isBuildWithoutTest(String lowered) {
  var sawBuild = false;
  var sawCheck = false;
  for (final segment in _segments(lowered)) {
    final words = _wordsOf(segment);
    if (words.isEmpty) continue;
    if (_denyCmd(words.first)) continue;
    if (_isShellTest(words)) continue;
    for (final w in words) {
      if (_kVerifyVerbs.contains(w) || w.startsWith('test:')) sawCheck = true;
      if (_kBuildOnly.contains(w)) sawBuild = true;
    }
  }
  return sawBuild && !sawCheck;
}

bool _looksTestAnalyzeClass(String lowered) {
  for (final segment in _segments(lowered)) {
    if (_segmentIsTestAnalyze(segment)) return true;
  }
  return false;
}

bool _segmentIsTestAnalyze(String segment) {
  final words = _wordsOf(segment);
  if (words.isEmpty) return false;
  if (_denyCmd(words.first) || _isShellTest(words)) return false;
  final payload = _payloadWords(words);
  if (payload.isEmpty) return false;
  final cmd = payload.first.contains('/')
      ? payload.first.split('/').last
      : payload.first;
  if (_denyCmd(cmd)) return false;
  if (_kVerifyVerbs.contains(cmd) || cmd.startsWith('test:')) return true;
  return payload.length > 1 && _kVerifyVerbs.contains(payload[1]);
}

bool _commandFulfills(String command, String expected) {
  final want = expected.trim().toLowerCase();
  if (want.isEmpty) return false;
  if (command == want) return true;
  final wantWords = _wordsOf(want);
  if (wantWords.isEmpty) return false;
  for (final segment in _segments(command)) {
    final got = segment.trim();
    if (got.isEmpty) continue;
    final words = _wordsOf(got);
    if (words.isEmpty || _denyCmd(words.first) || _isShellTest(words)) {
      continue;
    }
    if (got == want || got.startsWith('$want ')) return true;
    final payload = _payloadWords(words);
    if (_wordsStartWith(payload, wantWords) ||
        _wordsStartWith(words, wantWords)) {
      return true;
    }
  }
  return false;
}

List<String> _payloadWords(List<String> words) {
  if (words.isEmpty) return words;
  var cmd = words.first;
  if (cmd.contains('/')) cmd = cmd.split('/').last;
  if (const {'python', 'python3', 'py'}.contains(cmd) &&
      words.length > 2 &&
      words[1] == '-m') {
    return words.sublist(2);
  }
  if (_kRunnerHosts.contains(cmd)) {
    var i = 1;
    if (i < words.length && _kRunnerWords.contains(words[i])) i++;
    return i < words.length ? words.sublist(i) : const <String>[];
  }
  return words;
}

bool _wordsStartWith(List<String> words, List<String> prefix) {
  if (prefix.isEmpty || words.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (words[i] != prefix[i]) return false;
  }
  return true;
}

bool _denyCmd(String cmd) {
  final base = cmd.contains('/') ? cmd.split('/').last : cmd;
  return _kDenyCmds.contains(base);
}

bool _isShellTest(List<String> words) {
  final cmd = words.first.contains('/')
      ? words.first.split('/').last
      : words.first;
  return cmd == 'test' && words.any(_kShellTestFlags.contains);
}

List<String> _wordsOf(String raw) => raw
    .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

List<String> _segments(String command) =>
    command.split(RegExp(r'(?:&&|\|\||[;|\n])'));
