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

// THE GOD-FILE RATCHET. The CI bar is 500 lines for handwritten Dart under
// lib/. After the mixed-file debt payback, leftover files over 500 were
// split so this test can fail loud at the product cap — not at 1,000.
//
// This test lives in test/ ON PURPOSE: it runs in the ordinary unit suite
// on every platform and inside the ci-local container, and
// test-integrity.yml blocks any PR that edits this file or the baseline
// without the maintainer's approved-test-change label — the same protection
// dependency_floors.json gets, for the same reason: a check whose inputs a
// PR can rewrite is not a check.
//
// The mechanism is a one-way ratchet over test/baselines/god_files.json.
// The campaign's victory condition is an empty baseline (`{}`). Do not add
// grandfather entries for handwritten leftovers — split the file instead.
//
//   1. A file NOT in the baseline may never reach 500 lines. Split before
//      you cross, not after.
//   2. A baseline file may never exceed its recorded count. The monsters
//      can only shrink.
//   3. When a baseline file shrinks, the recorded count must be lowered to
//      match in the same change. Otherwise the gap is slack a later edit
//      could silently grow back into.
//   4. When a baseline file drops below 500, its entry must be DELETED.
//      Rule 1 then guards it forever — a beaten god file cannot return.
//
// Generated Dart is excluded here (*.g.dart, protobuf, grpc/generated).
// `lib/database/database.g.dart` is the named exception the maintainer
// called out: it is owned by generated_dart_size_test.dart (ceilings +
// Drift `generate_manager: false`), not by this handwritten ratchet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const int kGodFileBar = 500;
const String kBaselinePath = 'test/baselines/god_files.json';

bool _excluded(String path) =>
    path.endsWith('.g.dart') ||
    RegExp(r'\.pb\w*\.dart$').hasMatch(path) ||
    path.contains('grpc/generated');

/// Line counts for every hand-written Dart file under lib/, keyed by
/// forward-slash relative path so the baseline is identical across platforms.
Map<String, int> _census() {
  final counts = <String, int>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (_excluded(path)) continue;
    counts[path] = entity.readAsLinesSync().length;
  }
  return counts;
}

void main() {
  test('god files only ever shrink, and no file ever becomes one', () {
    final baselineFile = File(kBaselinePath);
    expect(
      baselineFile.existsSync(),
      isTrue,
      reason: 'the ratchet baseline is missing — it must never be deleted; '
          'an empty {} is the campaign\'s victory condition, absence is not',
    );
    final baseline = (jsonDecode(baselineFile.readAsStringSync()) as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toInt()));

    final counts = _census();
    final problems = <String>[];

    // Rules 2-4: the files we are burning down.
    baseline.forEach((path, recorded) {
      final current = counts[path];
      if (current == null) {
        problems.add(
          '$path is in the baseline but no longer exists — delete its entry '
          '(deleted or renamed files leave the baseline; a rename must not '
          'carry god-file headroom to a new name).',
        );
        return;
      }
      if (current > recorded) {
        problems.add(
          '$path GREW: $recorded -> $current lines. Baseline files may only '
          'shrink. Extract something in this same change instead — see '
          'CLAUDE.md "Code File Size Limits".',
        );
      } else if (current < kGodFileBar) {
        problems.add(
          '$path is now $current lines — BELOW the bar. Delete its baseline '
          'entry in this change to lock the win in; rule 1 guards it from '
          'here on.',
        );
      } else if (current < recorded) {
        problems.add(
          '$path shrank: $recorded -> $current lines. Good — now lower its '
          'baseline entry to $current in this same change, so the freed '
          'headroom cannot silently grow back.',
        );
      }
    });

    // Rule 1: everything else stays under the bar, forever.
    counts.forEach((path, lines) {
      if (lines >= kGodFileBar && !baseline.containsKey(path)) {
        problems.add(
          '$path is $lines lines and NOT in the baseline. New god files are '
          'banned — split it before it crosses $kGodFileBar. The baseline '
          'only ever shrinks; adding entries needs the maintainer\'s '
          'approved-test-change label and an explicit decision.',
        );
      }
    });

    expect(
      problems,
      isEmpty,
      reason: 'god-file ratchet violations:\n\n${problems.join('\n\n')}',
    );
  });
}
