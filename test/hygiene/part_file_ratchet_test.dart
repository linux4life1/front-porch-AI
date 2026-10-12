// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// No mechanical part files. Moving code into a `part` file to get under the
// 500-line bar (god_file_ratchet_test.dart) is not a split: the library still
// shares one private namespace and one set of fields. A file nearing the bar
// extracts a real class, widget or plain-Dart helper with explicit inputs.
// See CLAUDE.md "Size law".
//
// This counts the handwritten `part '…';` directives in every library under
// lib/. Not counted: `part of`, a commented or quoted `part`, a part whose
// target is `*.g.dart` (Drift / riverpod codegen), and generated libraries
// (*.g.dart, protobuf, grpc/generated).
//
// It is a ratchet over test/baselines/part_files.json (library -> count):
//   1. A library not in the baseline may have no part directive.
//   2. A baselined library may never go above its count.
//   3. A baselined library that has fewer parts than recorded (or is gone)
//      must have its entry lowered or deleted in the same change, so the
//      freed slot cannot be refilled by a new mechanical split.
//
// The exceptions below are part libraries by design, not legacy. They obey
// the same three rules on purpose. ChatService's parts all hang off one
// shell, so its count is the group total: a new chat_service_*.dart part
// raises it and fails. ChatService work that keeps moving moves inside an
// existing part or out to a leaf class under lib/services/chat/, and neither
// changes the count. A ceiling that did not also lock in shrinks would let a
// removed part be swapped for a new one with no one noticing.
//
// With FPAI_TIGHTEN_BASELINES=1 the baseline is lowered to the tree (never
// raised). Any baseline edit still needs the approved-test-change label.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _baselinePath = 'test/baselines/part_files.json';

/// Libraries that are `part` libraries by design. Frozen: no new parts.
const _exceptions = {
  'lib/database/database.dart': 'the Drift database library',
  'lib/services/chat_service.dart': 'the ChatService shell',
};

const _advice =
    'extract a class/widget instead (see CLAUDE.md Size law); a part file '
    'is not a split';

final _partKeyword = RegExp(r'(?<![\w$.])part(?=\s)');

bool _generated(String path) =>
    path.endsWith('.g.dart') ||
    RegExp(r'\.pb\w*\.dart$').hasMatch(path) ||
    path.contains('grpc/generated');

/// Every handwritten `part 'x.dart';` directive in [source].
List<RatchetHit> partDirectives(DartSource source) {
  final targets = {for (final s in source.strings) s.start: s.body};
  final code = source.code;
  return source.hits(
    _partKeyword,
    allow: (m) {
      var j = m.end;
      while (j < code.length &&
          !targets.containsKey(j) &&
          code.codeUnitAt(j) <= 32) {
        j++;
      }
      final target = targets[j];
      return target == null || target.endsWith('.g.dart');
    },
  );
}

Map<String, List<RatchetHit>> _census() => {
  for (final path in dartFiles('lib').where((p) => !_generated(p)))
    path: partDirectives(DartSource.read(path)),
}..removeWhere((_, hits) => hits.isEmpty);

/// Rule 3: a baselined library that has fewer parts than recorded.
List<String> _stale(
  Map<String, int> baseline,
  Map<String, List<RatchetHit>> census,
) => [
  for (final MapEntry(key: path, value: recorded) in baseline.entries)
    if ((census[path]?.length ?? 0) case final now when now < recorded)
      now == 0
          ? '$path is in $_baselinePath with $recorded part directives but '
                'has none now (or is gone). Delete its entry in this same '
                'change so the baseline stays honest.'
          : '$path shrank: $recorded -> $now part directives. Good — now '
                'lower its entry in $_baselinePath to $now in this same '
                'change, so the freed slot cannot be refilled.',
];

void main() {
  test('part directives only ever shrink, and no new library gains one', () {
    final baseline = readBaseline(_baselinePath);
    final census = _census();
    tightenBaselineIfAsked(_baselinePath, baseline, census);
    final problems = [
      ...ratchetProblems(
        baseline: baseline,
        census: census,
        baselinePath: _baselinePath,
        noun: 'part directives',
        advice: (hit) => _exceptions.containsKey(hit.path)
            ? '${_exceptions[hit.path]} is frozen; $_advice'
            : _advice,
        fix:
            'Do not split a file into part files to get under 500 lines: '
            'extract a class/widget instead (see CLAUDE.md Size law).',
      ),
      ..._stale(baseline, census),
    ];
    if (problems.isNotEmpty) fail(problems.join('\n\n'));
  });

  test('every exception library is recorded in the baseline', () {
    final baseline = readBaseline(_baselinePath);
    expect(
      _exceptions.keys.where((path) => !baseline.containsKey(path)),
      isEmpty,
      reason: 'an exception without a baseline count has no ceiling',
    );
  });

  test('only real handwritten part directives count', () {
    final source = DartSource('fixture.dart', _fixture);
    final counted = partDirectives(source).map((h) => h.line).toList();
    final expected = [
      for (final (i, line) in _fixture.split('\n').indexed)
        if (line.contains('// counted')) i + 1,
    ];
    expect(counted, expected);
  });
}

const _fixture = r'''
library fixture;

import 'package:flutter/widgets.dart';

part 'fixture.g.dart';
part "fixture.freezed.g.dart";
part 'fixture_body.dart'; // counted
part "fixture_more.dart"; // counted
part // counted: split by a line break
    'fixture_split.dart';
part /* odd */ 'fixture_commented_gap.dart'; // counted
// part 'commented_out.dart';
/* part 'block_commented.dart'; */
/// part 'doc_comment.dart';

const note = "part 'in_a_string.dart';";
const other = 'part of fixture;';
final part = 'not a directive';
String apart(String part) => part.isEmpty ? note : part;
''';
