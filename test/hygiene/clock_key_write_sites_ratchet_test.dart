// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Direct writes of story_clock_before / story_clock_after: index
// assignment, putIfAbsent or remove, by literal or by a constant bound to
// the key earlier in the same file. Allowed only inside writeSlotClockPair,
// persistStoryClockBefore and clock_shift.dart (calendar re-anchor). A
// mutation on a local declared, on one line, from Map.from / Map.of / a map
// literal in the same function is a read-only copy, not a persist; an alias
// of metadata / activeMetadata / a message field still counts. Reads,
// comments and strings that are not writes are ignored.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _keys = {'story_clock_before', 'story_clock_after'};
const _writerFns = {'writeSlotClockPair', 'persistStoryClockBefore'};
const _mutators = {'remove', 'putIfAbsent'};

final _binding = RegExp(r'\b(?:final|var|late|const)\b');
final _mapCopy = RegExp(
  r'\s*(?:\{|Map\s*(?:<[^;\n]*?>)?\s*\.\s*(?:from|of)\b)',
);
final _space = RegExp(r'\s');
final _ident = RegExp(r'[\w$]');

class _Hit {
  const _Hit(this.file, this.line, this.enclosing, this.key, this.op);

  final String file;
  final int line;
  final String enclosing;
  final String key;
  final String op;

  @override
  String toString() => '$file:$line $enclosing $op $key';
}

bool _allowed(_Hit h) =>
    h.file.endsWith('clock_shift.dart') ||
    h.enclosing.split('>').any(_writerFns.contains);

List<_Hit> _offenders(List<_Hit> writes) =>
    writes.where((h) => !_allowed(h)).toList();

/// Direct key writes in [src], read-only copies left out.
List<_Hit> _scanKeyWrites(DartSource src) {
  final code = src.code;
  int back(int j) {
    while (j >= 0 && _space.hasMatch(code[j])) {
      j--;
    }
    return j;
  }

  int forward(int j) {
    while (j < code.length && _space.hasMatch(code[j])) {
      j++;
    }
    return j;
  }

  String? identEndingAt(int j) {
    var s = j;
    while (s >= 0 && _ident.hasMatch(code[s])) {
      s--;
    }
    return s == j ? null : code.substring(s + 1, j + 1);
  }

  int skipBang(int j) => j >= 0 && code[j] == '!' ? back(j - 1) : j;

  // `recv.name(` / `recv!?.name(`: the receiver of the call at [paren].
  String? callReceiver(int paren) {
    var j = back(paren - 1);
    final name = identEndingAt(j);
    if (name == null) return null;
    j = skipBang(back(j - name.length));
    if (j >= 1 && code[j] == '.' && code[j - 1] == '?') {
      j = back(j - 2);
    } else if (j >= 0 && code[j] == '.') {
      j = back(j - 1);
    } else {
      return null;
    }
    return identEndingAt(skipBang(j));
  }

  // `recv[` / `recv![` / `recv?[`: the receiver indexed at [bracket].
  String? indexReceiver(int bracket) {
    var j = skipBang(back(bracket - 1));
    if (j >= 0 && code[j] == '?') j = back(j - 1);
    return identEndingAt(j);
  }

  DartFunction? innermost(int offset) =>
      src.enclosingFunctions(offset).lastOrNull;

  final copies = <DartFunction, Map<String, int>>{};
  for (final m in _binding.allMatches(code)) {
    final fn = innermost(m.start);
    if (fn == null) continue;
    final eq = _bindingEquals(code, m.end);
    if (eq == null) continue;
    final name = _lastIdent(code.substring(m.end, eq));
    if (name != null && _mapCopy.matchAsPrefix(code, eq + 1) != null) {
      copies.putIfAbsent(fn, () => {}).putIfAbsent(name, () => m.start);
    }
  }
  bool isCopy(String? receiver, int offset) {
    if (receiver == null) return false;
    if (receiver == 'metadata' || receiver == 'activeMetadata') return false;
    final fn = innermost(offset);
    final at = fn == null ? null : copies[fn]?[receiver];
    return at != null && at < offset;
  }

  final writes = <_Hit>[];
  // Records a write of [key] at [start, end); false when it is a read.
  bool classify(String key, int start, int end) {
    final before = back(start - 1);
    String? op, receiver;
    if (before >= 0 && code[before] == '(') {
      final call = identEndingAt(back(before - 1));
      if (_mutators.contains(call)) {
        (op, receiver) = (call, callReceiver(before));
      }
    } else if (before >= 0 && code[before] == '[') {
      var k = forward(end);
      if (k < code.length && code[k] == ']') {
        k = forward(k + 1);
        if (k < code.length &&
            code[k] == '=' &&
            (k + 1 >= code.length || code[k + 1] != '=')) {
          (op, receiver) = ('assign', indexReceiver(before));
        }
      }
    }
    if (op == null) return false;
    if (!isCopy(receiver, start)) {
      final names = [for (final f in src.enclosingFunctions(start)) f.name];
      writes.add(
        _Hit(
          src.path,
          src.lineOf(start) + 1,
          names.isEmpty ? '<top>' : names.join('>'),
          key,
          op,
        ),
      );
    }
    return true;
  }

  // A name bound to a key covers its later uses, up to a rebinding.
  final constants = <String, List<({String key, int at})>>{};
  for (final lit in src.strings) {
    if (!_keys.contains(lit.body)) continue;
    if (classify(lit.body, lit.start, lit.end)) continue;
    final eq = back(lit.start - 1);
    final name = eq >= 0 && code[eq] == '='
        ? identEndingAt(back(eq - 1))
        : null;
    if (name != null) {
      constants.putIfAbsent(name, () => []).add((key: lit.body, at: lit.start));
    }
  }
  constants.forEach((name, bindings) {
    final use = RegExp('\\b${RegExp.escape(name)}\\b');
    for (final m in use.allMatches(code, bindings.first.at)) {
      final bound = bindings.lastWhere((b) => b.at < m.start);
      classify(bound.key, m.start, m.end);
    }
  });
  writes.sort((a, b) => a.line.compareTo(b.line));
  return writes;
}

/// After `final` / `var` / `late` / `const` at [from]: the declaration's
/// `=` on the same line, at bracket depth 0, or null.
int? _bindingEquals(String code, int from) {
  var angle = 0, paren = 0;
  for (var j = from; j < code.length; j++) {
    final c = code[j];
    if (c == '\n' || c == ';' || (c == '{' && angle == 0 && paren == 0)) {
      return null;
    }
    if (c == '<') angle++;
    if (c == '>') angle--;
    if (c == '(') paren++;
    if (c == ')') paren--;
    if (angle == 0 &&
        paren == 0 &&
        c == '=' &&
        (j + 1 >= code.length || code[j + 1] != '=')) {
      return j;
    }
  }
  return null;
}

String? _lastIdent(String head) =>
    RegExp(r'[A-Za-z_$][\w$]*').allMatches(head).lastOrNull?[0];

List<_Hit> _scanInline(String src, String file) =>
    _scanKeyWrites(DartSource(file, src));

void main() {
  const random = 'lib/services/chat/random.dart';

  test('scanner self-test: flagged write in a random file is caught', () {
    final writes = _scanInline('''
void _stampOpeningClockPair() {
  // slot['story_clock_before'] = iso;
  final read = slot['story_clock_before'] as String?;
  slot['story_clock_after'] = iso;
  copy.remove('story_clock_before');
}
''', random);
    expect(writes, hasLength(2), reason: 'comment + read ignored');
    expect(_offenders(writes).map((h) => '${h.enclosing} ${h.op} ${h.key}'), [
      '_stampOpeningClockPair assign story_clock_after',
      '_stampOpeningClockPair remove story_clock_before',
    ]);
  });

  test('scanner self-test: local-copy remove is allowed', () {
    final writes = _scanInline('''
void _resolveVisibleAfter() {
  final copy = Map<String, dynamic>.from(slot!);
  copy.remove('story_clock_after');
  copy.remove('story_clock_before');
}
void clockSlotForResolve() {
  final copy = Map.of(active!);
  copy.remove('story_clock_after');
}
void spread() {
  final copy = {...slot};
  copy.remove('story_clock_before');
}
''', random);
    expect(writes, isEmpty);
  });

  test('scanner self-test: remove on msg.metadata is flagged', () {
    final writes = _scanInline('''
void _bad() {
  msg.metadata!.remove('story_clock_after');
}
''', random);
    expect(_offenders(writes), hasLength(1));
    expect(_offenders(writes).single.enclosing, '_bad');
    expect(_offenders(writes).single.op, 'remove');
  });

  test('scanner self-test: alias of metadata is flagged', () {
    final writes = _scanInline('''
void _bad() {
  final m = msg.metadata;
  m.remove('story_clock_after');
}
''', random);
    expect(_offenders(writes), hasLength(1));
    expect(_offenders(writes).single.enclosing, '_bad');
    expect(_offenders(writes).single.key, 'story_clock_after');
  });

  test('scanner self-test: clock_shift writes are allowed', () {
    final writes = _scanInline('''
void shiftClockFields() {
  map['story_clock_before'] = shift(map['story_clock_before']);
  map['story_clock_after'] = shift(map['story_clock_after']);
}
''', 'lib/services/chat/clock_shift.dart');
    expect(writes, hasLength(2));
    expect(_offenders(writes), isEmpty);
  });

  test('direct story_clock_before/after writes are gated', () {
    final extras = <String>[
      for (final path in dartFiles('lib'))
        if (!path.endsWith('.g.dart'))
          for (final h in _offenders(_scanKeyWrites(DartSource.read(path))))
            '$h',
    ];
    expect(
      extras,
      isEmpty,
      reason:
          'direct story_clock_* writes only in writeSlotClockPair, '
          'persistStoryClockBefore, and clock_shift.dart; extras: '
          '${extras.isEmpty ? '(none)' : extras.join(', ')}',
    );
  });
}
