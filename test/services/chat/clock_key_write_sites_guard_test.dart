// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Direct writes of story_clock_before / story_clock_after: index
// assignment, putIfAbsent, remove, or a key-constant equivalent.
// Allowlist: writeSlotClockPair, persistStoryClockBefore, and
// clock_shift.dart (calendar re-anchor). Reads, comments, and
// strings that are not writes are ignored.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _keys = {'story_clock_before', 'story_clock_after'};
const _writerFns = {'writeSlotClockPair', 'persistStoryClockBefore'};

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

class _Hit {
  const _Hit({
    required this.file,
    required this.line,
    required this.enclosing,
    required this.key,
    required this.op,
  });

  final String file;
  final int line;
  final String enclosing;
  final String key;
  final String op;

  @override
  String toString() => '$file:$line $enclosing $op $key';
}

bool _isIdentStart(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;

bool _isIdent(int c) => _isIdentStart(c) || (c >= 48 && c <= 57);

String _rel(String path) {
  final n = path.replaceAll(r'\', '/');
  final i = n.indexOf('/lib/');
  if (i >= 0) return n.substring(i + 1);
  if (n.startsWith('lib/')) return n;
  return n;
}

bool _fileAllowed(String file) {
  final n = file.replaceAll(r'\', '/');
  return n.endsWith('clock_shift.dart');
}

bool _fnAllowed(String enclosing) =>
    enclosing.split('>').any(_writerFns.contains);

class _KeyScan {
  _KeyScan({required this.writes, required this.constants});

  final List<_Hit> writes;
  final Map<String, String> constants;

  List<_Hit> get offenders => writes
      .where((h) => !_fileAllowed(h.file) && !_fnAllowed(h.enclosing))
      .toList();
}

_KeyScan _scanClockKeyWrites(String source, {required String file}) {
  final writes = <_Hit>[];
  final constants = <String, String>{};
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

  bool isWs(int j) =>
      j >= 0 &&
      j < source.length &&
      (source[j] == ' ' || source[j] == '\t' || source[j] == '\n');

  int skipWsForward(int j) {
    while (j < source.length && isWs(j)) {
      j++;
    }
    return j;
  }

  int skipWsBack(int j) {
    while (j >= 0 && isWs(j)) {
      j--;
    }
    return j;
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

  String? prevIdent(int from) {
    final j = skipWsBack(from - 1);
    if (j < 0 || !_isIdent(source.codeUnitAt(j))) return null;
    var s = j;
    while (s > 0 && _isIdent(source.codeUnitAt(s - 1))) {
      s--;
    }
    return identAt(s);
  }

  String? prevToken(int from) {
    var j = skipWsBack(from - 1);
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

  void recordWrite(String key, String op, int atLine) {
    writes.add(
      _Hit(file: file, line: atLine, enclosing: enclosing(), key: key, op: op),
    );
  }

  String? extractString(int start, String quote, {required bool triple}) {
    final buf = StringBuffer();
    var j = start;
    while (j < source.length) {
      final c = source[j];
      if (triple) {
        if (j + 2 < source.length &&
            source[j] == quote &&
            source[j + 1] == quote &&
            source[j + 2] == quote) {
          return buf.toString();
        }
        if (c == '\n') {
          // content only; line is updated by the caller after skip
        }
        buf.write(c);
        j++;
        continue;
      }
      if (c == r'\') {
        if (j + 1 < source.length) {
          buf.write(source[j + 1]);
          j += 2;
          continue;
        }
      }
      if (c == quote) return buf.toString();
      if (c == '\n') return null;
      buf.write(c);
      j++;
    }
    return null;
  }

  int endOfString(int contentStart, String quote, {required bool triple}) {
    var j = contentStart;
    while (j < source.length) {
      if (source[j] == '\n') line++;
      if (triple) {
        if (j + 2 < source.length &&
            source[j] == quote &&
            source[j + 1] == quote &&
            source[j + 2] == quote) {
          return j + 3;
        }
        j++;
        continue;
      }
      if (source[j] == r'\') {
        j += 2;
        continue;
      }
      if (source[j] == quote) return j + 1;
      j++;
    }
    return source.length;
  }

  void classifyKeyString(String key, int litStart, int afterLit) {
    final before = skipWsBack(litStart - 1);
    if (before >= 0 && source[before] == '(') {
      final call = prevIdent(before);
      if (call == 'remove' || call == 'putIfAbsent') {
        recordWrite(key, call!, line);
        return;
      }
    }
    if (before >= 0 && source[before] == '[') {
      var k = skipWsForward(afterLit);
      if (k < source.length && source[k] == ']') {
        k = skipWsForward(k + 1);
        if (k < source.length &&
            source[k] == '=' &&
            (k + 1 >= source.length || source[k + 1] != '=')) {
          recordWrite(key, 'assign', line);
          return;
        }
      }
    }
    // const/final/var name = 'story_clock_*'
    final eq = skipWsBack(litStart - 1);
    if (eq >= 0 && source[eq] == '=') {
      final name = prevIdent(eq);
      if (name != null) constants[name] = key;
    }
  }

  void classifyConstIdent(String name, String key, int nameStart, int after) {
    final before = skipWsBack(nameStart - 1);
    if (before >= 0 && source[before] == '(') {
      final call = prevIdent(before);
      if (call == 'remove' || call == 'putIfAbsent') {
        recordWrite(key, call!, line);
        return;
      }
    }
    if (before >= 0 && source[before] == '[') {
      var k = skipWsForward(after);
      if (k < source.length && source[k] == ']') {
        k = skipWsForward(k + 1);
        if (k < source.length &&
            source[k] == '=' &&
            (k + 1 >= source.length || source[k + 1] != '=')) {
          recordWrite(key, 'assign', line);
        }
      }
    }
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
      final contentStart = qAt + (triple ? 3 : 1);
      final content = extractString(contentStart, q, triple: triple);
      final after = endOfString(contentStart, q, triple: triple);
      if (content != null && _keys.contains(content)) {
        classifyKeyString(content, raw ? i : qAt, after);
      }
      i = after;
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
        pendingFn = name;
        pendingParen = 0;
        i = k;
        continue;
      }
      final bound = constants[name];
      if (bound != null) {
        classifyConstIdent(name, bound, nameStart, i + name.length);
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

  return _KeyScan(writes: writes, constants: constants);
}

_KeyScan _scanLibClockKeyWrites() {
  final writes = <_Hit>[];
  final constants = <String, String>{};
  final lib = Directory('lib');
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    if (file.path.endsWith('.g.dart')) continue;
    final part = _scanClockKeyWrites(
      file.readAsStringSync(),
      file: _rel(file.path),
    );
    writes.addAll(part.writes);
    constants.addAll(part.constants);
  }
  return _KeyScan(writes: writes, constants: constants);
}

void main() {
  test('scanner self-test: flagged write in a random file is caught', () {
    const src = '''
void _stampOpeningClockPair() {
  // slot['story_clock_before'] = iso;
  final read = slot['story_clock_before'] as String?;
  slot['story_clock_after'] = iso;
  copy.remove('story_clock_before');
}
''';
    final scan = _scanClockKeyWrites(
      src,
      file: 'lib/services/chat/random.dart',
    );
    expect(scan.writes, hasLength(2), reason: 'comment + read ignored');
    expect(scan.offenders, hasLength(2));
    expect(
      scan.offenders.map((h) => '${h.enclosing} ${h.op} ${h.key}').toList(),
      [
        '_stampOpeningClockPair assign story_clock_after',
        '_stampOpeningClockPair remove story_clock_before',
      ],
    );
  });

  test('scanner self-test: clock_shift writes are allowed', () {
    const src = '''
void shiftClockFields() {
  map['story_clock_before'] = shift(map['story_clock_before']);
  map['story_clock_after'] = shift(map['story_clock_after']);
}
''';
    final scan = _scanClockKeyWrites(
      src,
      file: 'lib/services/chat/clock_shift.dart',
    );
    expect(scan.writes, hasLength(2));
    expect(scan.offenders, isEmpty);
  });

  test('direct story_clock_before/after writes are gated', () {
    final scan = _scanLibClockKeyWrites();
    final extras = scan.offenders.map((h) => h.toString()).toList();
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
