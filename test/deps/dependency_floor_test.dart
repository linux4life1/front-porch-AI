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

// ─────────────────────────────────────────────────────────────────────────────
// DEPENDENCY REGRESSION GUARD
//
// WHY THIS EXISTS (the v1.1.0 Linux incident, 2026-07-28):
//
// Commit da0e49eb ("migrate Living Time providers to @riverpod codegen")
// re-resolved pubspec.lock as a side effect of adding the codegen stack.
// Nine packages silently went BACKWARDS in that commit. One of them was
// `sqlite3`, 3.2.0 -> 2.9.4.
//
// That single downgrade shipped a release with NO SQLITE ENGINE AT ALL on
// Linux. `sqlite3` 3.x bundles the native library itself; 2.x delegates that
// to `sqlite3_flutter_libs`, which was pinned at `0.6.0+eol` — a tombstone
// release whose source reads "This package does not do anything". Every Linux
// user who updated got "libsqlite3.so is missing" and was told their database
// was corrupted.
//
// It reached users because NOTHING FAILED: the build succeeded, the full test
// suite passed, and macOS + Windows silently fell back to their system SQLite
// (/usr/lib/libsqlite3.dylib and winsqlite3.dll). The maintainer's only test
// machine is a Mac, so the regression was structurally invisible.
//
// These tests are pure Dart with no native dependency, so they fail LOUDLY on
// every platform — including the macOS box where the original bug could never
// have reproduced.
//
// WHEN THIS TEST FAILS, DO NOT "FIX" IT BY REGENERATING THE BASELINE.
// A failure means a dependency moved backwards. Find out why, and only update
// test/deps/dependency_floors.json if the downgrade is genuinely intended and
// understood — which makes it a reviewed decision instead of silent churn.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Parses `name -> version` out of a pubspec.lock without a YAML dependency.
/// The lock's shape is stable and machine-generated: two-space package keys,
/// four-space `version:` entries.
Map<String, String> parseLock(String contents) {
  final versions = <String, String>{};
  final pkg = RegExp(r'^  ([A-Za-z0-9_]+):$');
  final ver = RegExp(r'^    version: "?([^"]+)"?$');
  String? current;
  for (final line in const LineSplitter().convert(contents)) {
    final p = pkg.firstMatch(line);
    if (p != null) {
      current = p.group(1);
      continue;
    }
    final v = ver.firstMatch(line);
    if (v != null && current != null) {
      versions[current] = v.group(1)!.trim();
    }
  }
  return versions;
}

/// Comparable version tuple. Build/pre-release metadata (`+eol`, `-dev.9`) is
/// dropped for ordering — we only care about the numeric precedence.
List<int> _parts(String version) {
  final core = version.split(RegExp(r'[+\-]')).first;
  return [
    for (final piece in core.split('.')) int.tryParse(piece) ?? 0,
  ];
}

/// Returns <0, 0, >0 like a comparator.
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// True when the resolved sqlite3 / sqlite3_flutter_libs pair can actually
/// produce a native SQLite library.
///
/// Exactly two valid worlds:
///   * `sqlite3` 3.x  — the binding bundles SQLite itself (native assets).
///     `sqlite3_flutter_libs` is then unnecessary; 0.6.0+eol is the correct
///     marker pin, and 0.5.x would wrongly reintroduce the old build scripts.
///   * `sqlite3` 2.x  — the binding does NOT bundle anything and requires
///     `sqlite3_flutter_libs` 0.5.x to compile and ship the library.
///
/// The lethal combination is `sqlite3` 2.x + `sqlite3_flutter_libs` 0.6.x:
/// nothing builds SQLite, and the failure is invisible until a Linux user
/// without libsqlite3-dev launches the app. That is exactly what v1.1.0 was.
bool sqliteBundlingIsCoherent({
  required String sqlite3,
  required String flutterLibs,
}) {
  final bindingMajor = _parts(sqlite3).first;
  final libsMinor = _parts(flutterLibs).length > 1
      ? _parts(flutterLibs)[1]
      : 0;
  if (bindingMajor >= 3) return libsMinor >= 6; // 3.x self-bundles
  return libsMinor == 5; // 2.x needs the real 0.5.x plugin
}

void main() {
  final lockFile = File('pubspec.lock');
  final baselineFile = File('test/deps/dependency_floors.json');

  late Map<String, String> resolved;
  late Map<String, String> floors;

  setUpAll(() {
    resolved = parseLock(lockFile.readAsStringSync());
    floors = (jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
  });

  test('pubspec.lock parses and is not empty', () {
    expect(lockFile.existsSync(), isTrue, reason: 'pubspec.lock must exist');
    expect(resolved.length, greaterThan(100),
        reason: 'lock parse produced suspiciously few packages — parser broke');
    expect(resolved.containsKey('sqlite3'), isTrue);
    expect(resolved.containsKey('drift'), isTrue);
  });

  test('NO DEPENDENCY MAY SILENTLY MOVE BACKWARDS', () {
    final regressions = <String>[];
    floors.forEach((name, floor) {
      final now = resolved[name];
      if (now == null) return; // removal is covered by the test below
      if (compareVersions(now, floor) < 0) {
        regressions.add('  $name: $floor -> $now  (DOWNGRADE)');
      }
    });

    expect(
      regressions,
      isEmpty,
      reason:
          '\n\n${regressions.length} dependency(ies) moved BACKWARDS versus the '
          'verified baseline:\n\n${regressions.join('\n')}\n\n'
          'This is how the v1.1.0 Linux outage happened: a codegen refactor '
          're-resolved the lock, sqlite3 fell 3.2.0 -> 2.9.4, and the release '
          'shipped with no database engine on Linux while macOS and Windows '
          'silently fell back to system SQLite.\n\n'
          'DO NOT regenerate test/deps/dependency_floors.json to make this '
          'pass. Work out WHY the resolver moved backwards first. If the '
          'downgrade is genuinely intended, update the baseline in the same '
          'commit, and say why in the commit message.\n',
    );
  });

  test('no baseline dependency disappears from the lock entirely', () {
    final missing = floors.keys.where((k) => !resolved.containsKey(k)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          '\n\nPackages present in the verified baseline are gone from '
          'pubspec.lock:\n  ${missing.join('\n  ')}\n\n'
          'A vanished dependency can remove shipped functionality just as '
          'quietly as a downgrade. Confirm the removal is intended, then '
          'update the baseline.\n',
    );
  });

  test('sqlite3 + sqlite3_flutter_libs can actually produce a native library',
      () {
    final binding = resolved['sqlite3']!;
    final libs = resolved['sqlite3_flutter_libs']!;

    expect(
      sqliteBundlingIsCoherent(sqlite3: binding, flutterLibs: libs),
      isTrue,
      reason:
          '\n\nBROKEN SQLITE PAIRING: sqlite3 $binding + '
          'sqlite3_flutter_libs $libs\n\n'
          'sqlite3 3.x bundles SQLite itself and pairs with '
          'sqlite3_flutter_libs 0.6.0+eol.\n'
          'sqlite3 2.x bundles NOTHING and requires sqlite3_flutter_libs '
          '0.5.x to build the library.\n\n'
          '2.x + 0.6.x produces a build with NO SQLITE AT ALL. It compiles, '
          'it passes tests, and it works on macOS and Windows because they '
          'fall back to system SQLite — then it bricks every Linux install '
          'with "libsqlite3.so is missing". That shipped as v1.1.0.\n',
    );
  });

  group('guard self-tests (these prove the guard actually catches the bug)', () {
    // The strongest possible proof: run the REAL check over the REAL lock
    // entries that shipped as the broken v1.1.0, captured verbatim from
    // `git show v1.1.0:pubspec.lock`.
    //
    // Note on methodology: an earlier attempt to verify this by swapping
    // pubspec.lock for the v1.1.0 one and re-running gave a FALSE PASS —
    // `flutter test` implicitly runs `pub get`, which re-resolved the lock
    // back to a valid state before the test ever read it. A checked-in
    // fixture is immune to that, because no resolver ever touches it.
    test('REGRESSION: rejects the real v1.1.0 lock that bricked Linux', () {
      final fixture =
          File('test/deps/fixtures/v1.1.0_broken.lock').readAsStringSync();
      final shipped = parseLock(fixture);

      // Sanity: the fixture really is the broken state.
      expect(shipped['sqlite3'], '2.9.4');
      expect(shipped['sqlite3_flutter_libs'], '0.6.0+eol');

      expect(
        sqliteBundlingIsCoherent(
          sqlite3: shipped['sqlite3']!,
          flutterLibs: shipped['sqlite3_flutter_libs']!,
        ),
        isFalse,
        reason: 'the pairing that shipped as v1.1.0 MUST be rejected — if this '
            'ever passes, the guard has stopped protecting Linux users',
      );
    });

    test('REGRESSION: flags the v1.1.0 downgrades against v1.0.0 floors', () {
      // What the floor check would have said had it existed on 2026-07-21,
      // with v1.0.0's versions as the baseline.
      const v100Floors = {
        'sqlite3': '3.2.0',
        'drift': '2.32.0',
        'analyzer': '10.0.1',
      };
      final shipped = parseLock(
        File('test/deps/fixtures/v1.1.0_broken.lock').readAsStringSync(),
      );

      final caught = <String>[];
      v100Floors.forEach((name, floor) {
        if (compareVersions(shipped[name]!, floor) < 0) caught.add(name);
      });

      expect(
        caught,
        containsAll(<String>['sqlite3', 'drift', 'analyzer']),
        reason: 'the floor check must flag every package that regressed in '
            'da0e49eb — this is the alarm that never rang',
      );
    });

    test('rejects the exact pairing that shipped as v1.1.0', () {
      expect(
        sqliteBundlingIsCoherent(sqlite3: '2.9.4', flutterLibs: '0.6.0+eol'),
        isFalse,
        reason: 'the v1.1.0 combination must be rejected',
      );
    });

    test('accepts both valid worlds', () {
      // v1.0.0's shipping configuration.
      expect(
        sqliteBundlingIsCoherent(sqlite3: '3.2.0', flutterLibs: '0.6.0+eol'),
        isTrue,
      );
      // The v1.1.1 hotfix configuration.
      expect(
        sqliteBundlingIsCoherent(sqlite3: '2.9.4', flutterLibs: '0.5.42'),
        isTrue,
      );
    });

    test('rejects 3.x paired with the resurrected old build scripts', () {
      expect(
        sqliteBundlingIsCoherent(sqlite3: '3.2.0', flutterLibs: '0.5.42'),
        isFalse,
      );
    });

    test('version comparison orders correctly, including build metadata', () {
      expect(compareVersions('3.2.0', '2.9.4'), greaterThan(0));
      expect(compareVersions('2.9.4', '3.2.0'), lessThan(0));
      expect(compareVersions('0.6.0+eol', '0.5.42'), greaterThan(0));
      expect(compareVersions('2.31.0', '2.32.0'), lessThan(0));
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      // Real regression pairs from the incident.
      expect(compareVersions('9.0.0', '10.0.1'), lessThan(0));
      expect(compareVersions('0.12.18', '0.12.19'), lessThan(0));
    });

    test('lock parser survives quoted and unquoted versions', () {
      const sample = '''
packages:
  drift:
    dependency: "direct main"
    description:
      name: drift
    source: hosted
    version: "2.31.0"
  sqlite3:
    dependency: transitive
    source: hosted
    version: 2.9.4
''';
      final parsed = parseLock(sample);
      expect(parsed['drift'], '2.31.0');
      expect(parsed['sqlite3'], '2.9.4');
    });
  });
}
