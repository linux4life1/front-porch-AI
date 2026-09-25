// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// C1: writeSlotClockPair only inside backfillSlotClocks and
// _writeSlotClock. applySlotClock only inside _applyTipClock,
// exactly one _applyDay1Clock, and exactly one
// _rewindLiveToSlotBefore. Empty-pre-user Day 1 and the fork share
// that Day-1 helper. Abort goes through _writeSlotClock then
// _applyTipClock. Any identifier reference counts — calls,
// tear-offs, assignments, arguments — not only name(. Comments,
// strings, and the two definitions are excluded.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _writeAllowed = {'_writeSlotClock', 'backfillSlotClocks'};
const _applyAllowed = {
  '_applyTipClock',
  '_applyDay1Clock',
  '_rewindLiveToSlotBefore',
};
const _helpers = {
  '_writeSlotClock',
  'backfillSlotClocks',
  '_applyTipClock',
  '_applyDay1Clock',
  '_rewindLiveToSlotBefore',
};

const _declLead = {
  'await',
  'return',
  'yield',
  'throw',
  'if',
  'while',
  'for',
  'switch',
  'catch',
  'assert',
  'else',
  'case',
  'new',
  'const',
  'final',
  'var',
  'late',
};

class _Site {
  const _Site({
    required this.file,
    required this.line,
    required this.enclosing,
    required this.kind,
  });

  final String file;
  final int line;
  final String enclosing;
  final String kind;

  @override
  String toString() => '$file:$line $enclosing';
}

class _Scan {
  _Scan({required this.writes, required this.applies, required this.defs});

  final List<_Site> writes;
  final List<_Site> applies;
  final Map<String, int> defs;

  List<_Site> get writeOffenders =>
      writes.where((s) => !_stackAllows(s.enclosing, _writeAllowed)).toList();

  List<_Site> get applyOffenders =>
      applies.where((s) => !_stackAllows(s.enclosing, _applyAllowed)).toList();

  List<_Site> get day1Applies => applies
      .where((s) => s.enclosing.split('>').last == '_applyDay1Clock')
      .toList();

  List<_Site> get rewindApplies => applies
      .where((s) => s.enclosing.split('>').last == '_rewindLiveToSlotBefore')
      .toList();
}

bool _stackAllows(String enclosing, Set<String> allowed) {
  return enclosing.split('>').any(allowed.contains);
}

String _rel(String path) {
  final n = path.replaceAll(r'\', '/');
  final i = n.indexOf('/lib/');
  if (i >= 0) return n.substring(i + 1);
  if (n.startsWith('lib/')) return n;
  return n;
}

bool _isIdentStart(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;

bool _isIdent(int c) => _isIdentStart(c) || (c >= 48 && c <= 57);

/// Brace-depth / comment-aware scan. Definitions and comments are skipped.
_Scan _scanClockSites(String source, {required String file}) {
  final writes = <_Site>[];
  final applies = <_Site>[];
  final defs = <String, int>{for (final h in _helpers) h: 0};

  var i = 0;
  var line = 1;
  var brace = 0;
  String? pendingFn;
  var pendingParen = 0;
  final stack = <({String name, int bodyDepth})>[];

  String enclosing() =>
      stack.isEmpty ? '<top>' : stack.map((f) => f.name).join('>');

  void skipLineComment() {
    while (i < source.length && source[i] != '\n') {
      i++;
    }
  }

  void skipBlockComment() {
    while (i < source.length - 1 &&
        !(source[i] == '*' && source[i + 1] == '/')) {
      if (source[i] == '\n') line++;
      i++;
    }
    if (i < source.length - 1) i += 2;
  }

  void skipString(String quote, {required bool raw, required bool triple}) {
    while (i < source.length) {
      final c = source[i];
      if (c == '\n') line++;
      if (!raw && c == r'\' && !triple) {
        i += 2;
        continue;
      }
      if (triple) {
        if (i + 2 < source.length &&
            source[i] == quote &&
            source[i + 1] == quote &&
            source[i + 2] == quote) {
          i += 3;
          return;
        }
        i++;
        continue;
      }
      if (c == quote) {
        i++;
        return;
      }
      i++;
    }
  }

  String? identAt(int start) {
    if (start < 0 ||
        start >= source.length ||
        !_isIdentStart(source.codeUnitAt(start))) {
      return null;
    }
    var j = start + 1;
    while (j < source.length && _isIdent(source.codeUnitAt(j))) {
      j++;
    }
    return source.substring(start, j);
  }

  String? prevToken(int from) {
    var j = from - 1;
    while (j >= 0 &&
        (source[j] == ' ' || source[j] == '\t' || source[j] == '\n')) {
      j--;
    }
    if (j < 0) return null;
    if (source[j] == '.') return '.';
    if (source[j] == '?' || source[j] == '>') return 'TYPE';
    if (!_isIdent(source.codeUnitAt(j))) return source[j];
    while (j > 0 && _isIdent(source.codeUnitAt(j - 1))) {
      j--;
    }
    return identAt(j);
  }

  bool isDecl(String name, int nameStart) {
    if (_declLead.contains(name)) return false;
    final prev = prevToken(nameStart);
    if (prev == null || prev == '.') return false;
    if (_declLead.contains(prev)) return false;
    if (prev == 'TYPE') return true;
    if (RegExp(r'^[\w]+$').hasMatch(prev)) return true;
    return false;
  }

  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      i += 2;
      skipLineComment();
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      i += 2;
      skipBlockComment();
      continue;
    }
    final raw =
        c == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    final qAt = raw ? i + 1 : i;
    if (qAt < source.length && (source[qAt] == "'" || source[qAt] == '"')) {
      final q = source[qAt];
      final triple =
          qAt + 2 < source.length &&
          source[qAt + 1] == q &&
          source[qAt + 2] == q;
      i = qAt + (triple ? 3 : 1);
      skipString(q, raw: raw, triple: triple);
      continue;
    }

    if (_isIdentStart(c.codeUnitAt(0))) {
      final name = identAt(i)!;
      final nameStart = i;
      var k = i + name.length;
      while (k < source.length &&
          (source[k] == ' ' || source[k] == '\t' || source[k] == '\n')) {
        if (source[k] == '\n') line++;
        k++;
      }
      final followedByParen = k < source.length && source[k] == '(';
      final decl =
          followedByParen &&
          name != 'Function' &&
          (pendingFn == null || pendingParen <= 0) &&
          isDecl(name, nameStart);
      if (decl) {
        if (_helpers.contains(name)) {
          defs[name] = (defs[name] ?? 0) + 1;
        }
        pendingFn = name;
        pendingParen = 0;
        i = k;
        continue;
      }
      if (name == 'writeSlotClockPair' || name == 'applySlotClock') {
        final site = _Site(
          file: file,
          line: line,
          enclosing: enclosing(),
          kind: name == 'writeSlotClockPair' ? 'write' : 'apply',
        );
        if (site.kind == 'write') {
          writes.add(site);
        } else {
          applies.add(site);
        }
      }
      if (followedByParen) {
        i = k;
        continue;
      }
      i += name.length;
      continue;
    }

    if (c == '(') {
      if (pendingFn != null) pendingParen++;
      i++;
      continue;
    }
    if (c == ')') {
      if (pendingFn != null) pendingParen--;
      i++;
      continue;
    }
    if (c == '{') {
      brace++;
      final opened = pendingFn;
      if (opened != null && pendingParen <= 0) {
        stack.add((name: opened, bodyDepth: brace));
        pendingFn = null;
      }
      i++;
      continue;
    }
    if (c == '}') {
      brace--;
      while (stack.isNotEmpty && stack.last.bodyDepth > brace) {
        stack.removeLast();
      }
      i++;
      continue;
    }
    if (c == '=' &&
        i + 1 < source.length &&
        source[i + 1] == '>' &&
        pendingFn != null &&
        pendingParen <= 0) {
      pendingFn = null;
    }
    if (c == ';' && pendingFn != null && pendingParen <= 0) {
      pendingFn = null;
    }
    i++;
  }

  return _Scan(writes: writes, applies: applies, defs: defs);
}

_Scan _scanLibClockSites() {
  final writes = <_Site>[];
  final applies = <_Site>[];
  final defs = <String, int>{for (final h in _helpers) h: 0};
  final lib = Directory('lib');
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    if (file.path.endsWith('.g.dart')) continue;
    final part = _scanClockSites(
      file.readAsStringSync(),
      file: _rel(file.path),
    );
    writes.addAll(part.writes);
    applies.addAll(part.applies);
    for (final e in part.defs.entries) {
      defs[e.key] = (defs[e.key] ?? 0) + e.value;
    }
  }
  return _Scan(writes: writes, applies: applies, defs: defs);
}

void main() {
  test('scanner self-test: one allowed write, one disallowed write', () {
    const src = '''
void _writeSlotClock(DateTime? Function()? tick) {
  writeSlotClockPair(slot, before: a, after: b);
}
void _stampOpeningClockPair() {
  // writeSlotClockPair(commented, before: a, after: b);
  writeSlotClockPair(slot, before: a, after: b);
}
''';
    final scan = _scanClockSites(src, file: 'inline.dart');
    expect(scan.writes, hasLength(2));
    expect(scan.writes[0].enclosing, '_writeSlotClock');
    expect(scan.writes[1].enclosing, '_stampOpeningClockPair');
    expect(scan.writeOffenders, hasLength(1));
    expect(scan.writeOffenders.single.enclosing, '_stampOpeningClockPair');
    expect(scan.writeOffenders.single.file, 'inline.dart');
    expect(
      scan.writeOffenders.single.line,
      greaterThan(scan.writes.first.line),
    );
    expect(scan.defs['_writeSlotClock'], 1);
  });

  test('scanner self-test: tear-off assignment in a disallowed function', () {
    const src = '''
void _abortSlotClockIfThisTurnTicked() {
  final w = writeSlotClockPair;
  final a = _timeService.applySlotClock;
}
''';
    final scan = _scanClockSites(src, file: 'inline.dart');
    expect(scan.writeOffenders, hasLength(1));
    expect(
      scan.writeOffenders.single.enclosing,
      '_abortSlotClockIfThisTurnTicked',
    );
    expect(scan.applyOffenders, hasLength(1));
    expect(
      scan.applyOffenders.single.enclosing,
      '_abortSlotClockIfThisTurnTicked',
    );
  });

  test('scanner self-test: tear-off passed as an argument is flagged', () {
    const src = '''
void _bad() {
  foo(writeSlotClockPair);
  bar(_timeService.applySlotClock);
}
''';
    final scan = _scanClockSites(src, file: 'inline.dart');
    expect(scan.writeOffenders.single.enclosing, '_bad');
    expect(scan.applyOffenders.single.enclosing, '_bad');
  });

  test('scanner self-test: allowed direct call is not flagged', () {
    const src = '''
void _writeSlotClock() {
  writeSlotClockPair(slot, before: a, after: b);
}
void _applyTipClock() {
  applySlotClock(resolved: x);
}
''';
    final scan = _scanClockSites(src, file: 'inline.dart');
    expect(scan.writes, hasLength(1));
    expect(scan.applies, hasLength(1));
    expect(scan.writeOffenders, isEmpty);
    expect(scan.applyOffenders, isEmpty);
  });

  test('writeSlotClockPair and applySlotClock call sites are gated', () {
    final scan = _scanLibClockSites();
    final missing = <String>[];
    for (final name in _helpers) {
      final n = scan.defs[name] ?? 0;
      if (n != 1) {
        missing.add('$name definitions=$n (want 1)');
      }
    }
    if (scan.day1Applies.length != 1) {
      missing.add(
        'Day-1 applySlotClock sites=${scan.day1Applies.length} '
        '(want 1 inside _applyDay1Clock); '
        'empty-pre-user and fork must share that helper',
      );
    }
    if (scan.rewindApplies.length != 1) {
      missing.add(
        'rewind applySlotClock sites=${scan.rewindApplies.length} '
        '(want 1 inside _rewindLiveToSlotBefore)',
      );
    }

    final writeHits = scan.writeOffenders.map((s) => s.toString()).toList();
    final applyHits = scan.applyOffenders.map((s) => s.toString()).toList();
    expect(
      {'write': writeHits, 'apply': applyHits, 'helpers': missing},
      {'write': <String>[], 'apply': <String>[], 'helpers': <String>[]},
      reason:
          'writeSlotClockPair( only in backfillSlotClocks and '
          '_writeSlotClock; extras: '
          '${writeHits.isEmpty ? '(none)' : writeHits.join(', ')}. '
          'applySlotClock( only in _applyTipClock, one _applyDay1Clock, '
          'and one _rewindLiveToSlotBefore; extras: '
          '${applyHits.isEmpty ? '(none)' : applyHits.join(', ')}. '
          'Named while red: abort must go through _writeSlotClock then '
          '_applyTipClock; _stampOpeningClockPair and '
          '_writeResolvedTipAfter must be deleted; extra Day-1 / rewind '
          'sites are extras. Helper/count issues: '
          '${missing.isEmpty ? '(none)' : missing.join('; ')}.',
    );
  });
}
