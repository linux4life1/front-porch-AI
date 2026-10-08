// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A Dart file read the way the compiler sees it, for the hygiene guards that
// count a banned form (test/hygiene/raw_*_ratchet_test.dart).
//
// Comments and string literals are blanked (same offsets, newlines kept), so
// a pattern never matches a comment or a message, and a `//` inside a URL
// cannot hide the rest of its line. Patterns put `\s*` between tokens, so the
// forms dart format splits across lines (`Colors` / `.green`, `Color(` /
// `0xFF…`) still match.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One counted occurrence of a banned form.
class RatchetHit {
  const RatchetHit(
    this.path,
    this.line,
    this.lastLine,
    this.offset,
    this.match,
    this.text,
  );

  final String path;
  final int line;
  final int lastLine;
  final int offset;

  /// What the pattern matched, whitespace collapsed (`Colors.green` for a
  /// match dart format split across two lines). Failures print it first, so
  /// two hits on one line stay apart.
  final String match;

  /// The trimmed source line the hit starts on.
  final String text;

  @override
  String toString() => '$path:$line  [$match]  $text';
}

/// A Dart file with comments and strings blanked.
class DartSource {
  DartSource(this.path, this.source) {
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == _nl) _lineStarts.add(i + 1);
    }
    code = _blank();
  }

  factory DartSource.read(String path) =>
      DartSource(path, File(path).readAsStringSync());

  final String path;
  final String source;

  /// [source] with every comment and string literal turned into spaces.
  late final String code;

  final _lineStarts = <int>[0];
  final _comments = <int, List<String>>{};

  /// Every match of [pattern] in the code, minus the ones [allow] excuses.
  List<RatchetHit> hits(RegExp pattern, {bool Function(Match m)? allow}) => [
    for (final m in pattern.allMatches(code))
      if (allow == null || !allow(m))
        RatchetHit(
          path,
          lineOf(m.start) + 1,
          lineOf(m.end - 1) + 1,
          m.start,
          m[0]!.replaceAll(RegExp(r'\s+'), ''),
          _lineText(lineOf(m.start)),
        ),
  ];

  /// 0-based line of [offset].
  int lineOf(int offset) {
    var lo = 0, hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The 1-based lines vouched for by a comment that opens with [marker]
  /// (`// theme-keep: <reason>`; prose that mentions it vouches for nothing):
  /// the marker's own line, or, when the marker is alone on its line, the
  /// single line directly below it. Never a statement, never a body.
  Set<int> markedLines(String marker) {
    final opens = RegExp(
      '^\\s*(?:/{2,}|/\\*+|\\*+)\\s*${RegExp.escape(marker)}\\s*\\S',
    );
    return {
      for (final MapEntry(key: line, value: comments) in _comments.entries)
        if (comments.any(opens.hasMatch))
          (_hasCode(line) ? line : line + 1) + 1,
    };
  }

  /// The identifier right before the innermost bracket around [offset]
  /// (`BoxShadow` inside `BoxShadow(color: …)`), or ''.
  String enclosingCall(int offset) {
    final open = _scanBack(offset, toSeparator: false);
    if (open < 0 || code.codeUnitAt(open) != _lparen) return '';
    final before = code.substring(max(0, open - 80), open);
    return RegExp(r'(\w+)\s*$').firstMatch(before)?.group(1) ?? '';
  }

  /// The named argument whose value [offset] sits in (`barrierColor` for
  /// `barrierColor: Colors.black54`), or ''.
  String argumentLabel(int offset) {
    final head = code.substring(
      _scanBack(offset, toSeparator: true) + 1,
      offset,
    );
    return RegExp(r'^\s*(\w+)\s*:').firstMatch(head)?.group(1) ?? '';
  }

  /// Walking back from [offset]: the innermost bracket still open there or,
  /// with [toSeparator], a nearer `,` or `;` at the same depth; -1 if none.
  int _scanBack(int offset, {required bool toSeparator}) {
    var depth = 0;
    for (var i = offset - 1; i >= 0; i--) {
      final c = code.codeUnitAt(i);
      if (c == _rparen || c == _rbracket || c == _rbrace) {
        depth++;
      } else if (c == _lparen || c == _lbracket || c == _lbrace) {
        if (depth-- == 0) return i;
      } else if (toSeparator &&
          depth == 0 &&
          (c == _comma || c == _semicolon)) {
        return i;
      }
    }
    return -1;
  }

  String _lineText(int line) {
    final end = line + 1 < _lineStarts.length
        ? _lineStarts[line + 1] - 1
        : source.length;
    final text = source.substring(_lineStarts[line], end).trim();
    return text.length > 110 ? '${text.substring(0, 107)}...' : text;
  }

  /// Whether 0-based [line] holds any code once comments are blanked.
  bool _hasCode(int line) {
    final end = line + 1 < _lineStarts.length
        ? _lineStarts[line + 1] - 1
        : code.length;
    for (var i = _lineStarts[line]; i < end; i++) {
      if (!_isSpace(code.codeUnitAt(i))) return true;
    }
    return false;
  }

  String _blank() {
    final out = Uint16List.fromList(source.codeUnits);
    final n = source.length;
    int at(int i) => i >= 0 && i < n ? source.codeUnitAt(i) : -1;
    void blank(int from, int to) {
      for (var i = from; i < to && i < n; i++) {
        if (out[i] != _nl) out[i] = _space;
      }
    }

    void comment(int from, int to) {
      var line = lineOf(from), start = from;
      for (var i = from; i <= to; i++) {
        if (i == to || source.codeUnitAt(i) == _nl) {
          _comments
              .putIfAbsent(line++, () => <String>[])
              .add(source.substring(start, i));
          start = i + 1;
        }
      }
      blank(from, to);
    }

    // Open string literals and `${…}` interpolations, innermost last.
    final frames = <_Frame>[];
    var i = 0;
    while (i < n) {
      final c = source.codeUnitAt(i);
      final top = frames.isEmpty ? null : frames.last;
      if (top is _StringFrame) {
        if (!top.raw && c == _backslash) {
          blank(i, i + 2);
          i += 2;
        } else if (!top.raw && c == _dollar && at(i + 1) == _lbrace) {
          blank(i, i + 2);
          frames.add(_Interpolation());
          i += 2;
        } else if (c == top.quote &&
            (!top.triple || (at(i + 1) == c && at(i + 2) == c))) {
          final len = top.triple ? 3 : 1;
          blank(i, i + len);
          frames.removeLast();
          i += len;
        } else {
          blank(i, i + 1);
          i++;
        }
        continue;
      }
      if (c == _slash && at(i + 1) == _slash) {
        var end = source.indexOf('\n', i);
        if (end < 0) end = n;
        comment(i, end);
        i = end;
        continue;
      }
      if (c == _slash && at(i + 1) == _star) {
        var depth = 1, j = i + 2;
        while (j < n && depth > 0) {
          if (at(j) == _slash && at(j + 1) == _star) {
            depth++;
            j += 2;
          } else if (at(j) == _star && at(j + 1) == _slash) {
            depth--;
            j += 2;
          } else {
            j++;
          }
        }
        comment(i, j);
        i = j;
        continue;
      }
      if (c == _quote || c == _dquote) {
        final raw = at(i - 1) == _r && (i < 2 || !_isIdent(at(i - 2)));
        final triple = at(i + 1) == c && at(i + 2) == c;
        if (raw) blank(i - 1, i);
        blank(i, i + (triple ? 3 : 1));
        frames.add(_StringFrame(c, triple: triple, raw: raw));
        i += triple ? 3 : 1;
        continue;
      }
      if (top is _Interpolation) {
        if (c == _lbrace) top.depth++;
        if (c == _rbrace && top.depth-- == 0) frames.removeLast();
        blank(i, i + 1);
      }
      i++;
    }
    return String.fromCharCodes(out);
  }
}

abstract class _Frame {}

class _StringFrame extends _Frame {
  _StringFrame(this.quote, {required this.triple, required this.raw});

  final int quote;
  final bool triple;
  final bool raw;
}

class _Interpolation extends _Frame {
  int depth = 0;
}

bool _isSpace(int c) => c == _space || c == _nl || c == 9 || c == 13;
bool _isIdentStart(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == _dollar;
bool _isIdent(int c) => _isIdentStart(c) || (c >= 48 && c <= 57);

const _nl = 10, _space = 32, _dquote = 34, _dollar = 36, _quote = 39;
const _lparen = 40, _rparen = 41, _star = 42, _comma = 44;
const _slash = 47, _semicolon = 59;
const _lbracket = 91, _backslash = 92, _rbracket = 93, _r = 114;
const _lbrace = 123, _rbrace = 125;
