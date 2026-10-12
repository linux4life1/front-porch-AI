// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// One writer for the story clock. writeSlotClockPair runs only inside
// backfillSlotClocks and _writeSlotClock; applySlotClock only inside
// _applyTipClock, exactly one _applyDay1Clock and exactly one
// _rewindLiveToSlotBefore. Empty-pre-user Day 1 and the fork share that
// Day-1 helper. Abort goes through _writeSlotClock then _applyTipClock.
// Any identifier reference counts (calls, tear-offs, assignments,
// arguments), not only `name(`. Comments, strings and the definitions
// themselves do not.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _writeAllowed = {'_writeSlotClock', 'backfillSlotClocks'};
const _applyAllowed = {
  '_applyTipClock',
  '_applyDay1Clock',
  '_rewindLiveToSlotBefore',
};
const _helpers = {..._writeAllowed, ..._applyAllowed};

final _reference = RegExp(r'\b(writeSlotClockPair|applySlotClock)\b');

class _Site {
  const _Site(this.file, this.line, this.enclosing);

  final String file;
  final int line;

  /// Enclosing function names, outermost first; empty at top level.
  final List<String> enclosing;

  String get innermost => enclosing.isEmpty ? '<top>' : enclosing.last;

  bool allowedBy(Set<String> allowed) => enclosing.any(allowed.contains);

  @override
  String toString() =>
      '$file:$line ${enclosing.isEmpty ? '<top>' : enclosing.join('>')}';
}

class _Scan {
  final writes = <_Site>[];
  final applies = <_Site>[];
  final defs = <String, int>{for (final h in _helpers) h: 0};

  void add(DartSource src) {
    final declared = {for (final f in src.functions) f.nameOffset};
    for (final f in src.functions) {
      if (_helpers.contains(f.name)) defs[f.name] = defs[f.name]! + 1;
    }
    for (final m in _reference.allMatches(src.code)) {
      if (declared.contains(m.start)) continue;
      final site = _Site(src.path, src.lineOf(m.start) + 1, [
        for (final f in src.enclosingFunctions(m.start)) f.name,
      ]);
      (m[1] == 'writeSlotClockPair' ? writes : applies).add(site);
    }
  }

  List<_Site> get writeOffenders =>
      writes.where((s) => !s.allowedBy(_writeAllowed)).toList();

  List<_Site> get applyOffenders =>
      applies.where((s) => !s.allowedBy(_applyAllowed)).toList();

  List<_Site> get day1Applies =>
      applies.where((s) => s.innermost == '_applyDay1Clock').toList();

  List<_Site> get rewindApplies =>
      applies.where((s) => s.innermost == '_rewindLiveToSlotBefore').toList();
}

_Scan _scanInline(String src) => _Scan()..add(DartSource('inline.dart', src));

_Scan _scanLib() {
  final scan = _Scan();
  for (final path in dartFiles('lib')) {
    if (!path.endsWith('.g.dart')) scan.add(DartSource.read(path));
  }
  return scan;
}

void main() {
  test('scanner self-test: one allowed write, one disallowed write', () {
    final scan = _scanInline('''
void _writeSlotClock(DateTime? Function()? tick) {
  writeSlotClockPair(slot, before: a, after: b);
}
void _stampOpeningClockPair() {
  // writeSlotClockPair(commented, before: a, after: b);
  writeSlotClockPair(slot, before: a, after: b);
}
''');
    expect(scan.writes, hasLength(2));
    expect(scan.writes[0].innermost, '_writeSlotClock');
    expect(scan.writes[1].innermost, '_stampOpeningClockPair');
    expect(scan.writeOffenders, hasLength(1));
    expect(scan.writeOffenders.single.innermost, '_stampOpeningClockPair');
    expect(scan.writeOffenders.single.file, 'inline.dart');
    expect(
      scan.writeOffenders.single.line,
      greaterThan(scan.writes.first.line),
    );
    expect(scan.defs['_writeSlotClock'], 1);
  });

  test('scanner self-test: tear-off assignment in a disallowed function', () {
    final scan = _scanInline('''
void _abortSlotClockIfThisTurnTicked() {
  final w = writeSlotClockPair;
  final a = _timeService.applySlotClock;
}
''');
    expect(scan.writeOffenders, hasLength(1));
    expect(
      scan.writeOffenders.single.innermost,
      '_abortSlotClockIfThisTurnTicked',
    );
    expect(scan.applyOffenders, hasLength(1));
    expect(
      scan.applyOffenders.single.innermost,
      '_abortSlotClockIfThisTurnTicked',
    );
  });

  test('scanner self-test: tear-off passed as an argument is flagged', () {
    final scan = _scanInline('''
void _bad() {
  foo(writeSlotClockPair);
  bar(_timeService.applySlotClock);
}
''');
    expect(scan.writeOffenders.single.innermost, '_bad');
    expect(scan.applyOffenders.single.innermost, '_bad');
  });

  test('scanner self-test: allowed direct call is not flagged', () {
    final scan = _scanInline('''
void _writeSlotClock() {
  writeSlotClockPair(slot, before: a, after: b);
}
void _applyTipClock() {
  applySlotClock(resolved: x);
}
''');
    expect(scan.writes, hasLength(1));
    expect(scan.applies, hasLength(1));
    expect(scan.writeOffenders, isEmpty);
    expect(scan.applyOffenders, isEmpty);
  });

  test('writeSlotClockPair and applySlotClock call sites are gated', () {
    final scan = _scanLib();
    final missing = <String>[
      for (final name in _helpers)
        if (scan.defs[name] != 1)
          '$name definitions=${scan.defs[name]} (want 1)',
      if (scan.day1Applies.length != 1)
        'Day-1 applySlotClock sites=${scan.day1Applies.length} '
            '(want 1 inside _applyDay1Clock); '
            'empty-pre-user and fork must share that helper',
      if (scan.rewindApplies.length != 1)
        'rewind applySlotClock sites=${scan.rewindApplies.length} '
            '(want 1 inside _rewindLiveToSlotBefore)',
    ];
    final writeHits = scan.writeOffenders.map((s) => '$s').toList();
    final applyHits = scan.applyOffenders.map((s) => '$s').toList();
    String listed(List<String> hits) =>
        hits.isEmpty ? '(none)' : hits.join(', ');
    expect(
      {'write': writeHits, 'apply': applyHits, 'helpers': missing},
      {'write': <String>[], 'apply': <String>[], 'helpers': <String>[]},
      reason:
          'writeSlotClockPair only in backfillSlotClocks and '
          '_writeSlotClock; extras: ${listed(writeHits)}. '
          'applySlotClock only in _applyTipClock, one _applyDay1Clock, '
          'and one _rewindLiveToSlotBefore; extras: ${listed(applyHits)}. '
          'Abort must go through _writeSlotClock then _applyTipClock; '
          'extra Day-1 / rewind sites are extras. Helper/count issues: '
          '${missing.isEmpty ? '(none)' : missing.join('; ')}.',
    );
  });
}
