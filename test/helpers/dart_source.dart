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

/// A Dart file with comments and strings blanked, and its bracket structure.
class DartSource {
  DartSource(this.path, this.source) {
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == _nl) _lineStarts.add(i + 1);
    }
    code = _blank();
    _parent = Int32List(code.length);
    _mapBrackets();
  }

  factory DartSource.read(String path) =>
      DartSource(path, File(path).readAsStringSync());

  final String path;
  final String source;

  /// [source] with every comment and string literal turned into spaces.
  late final String code;

  final _lineStarts = <int>[0];
  final _comments = <int, List<String>>{};
  late final Int32List _parent;
  final _closer = <int, int>{};
  final _separators = <int, List<int>>{};
  final _blockEnds = <int>{};

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

  /// Offset ranges vouched for by a comment that opens with [marker]
  /// (`// theme-keep: <reason>`; prose that mentions it vouches for nothing).
  ///
  /// A marker at the end of a line covers that line and the whole argument,
  /// list item or statement the line finishes: dart format wraps a long marked
  /// line and leaves the comment after the closing `),`. A marker on a line of
  /// its own covers the argument, item or statement that starts right below
  /// its comment block. Neither reaches over a function, class or block body;
  /// there a marker covers its own line only.
  List<(int, int)> markedRanges(String marker) {
    final opens = RegExp(
      '^\\s*(?:/{2,}|/\\*+|\\*+)\\s*${RegExp.escape(marker)}\\s*\\S',
    );
    final ranges = <(int, int)>[];
    _comments.forEach((line, comments) {
      if (!comments.any(opens.hasMatch)) return;
      final last = _lastCode(line);
      if (last >= 0) {
        ranges.add((_lineStarts[line], last));
        if (!_blockEnds.contains(last)) ranges.add((_segmentStart(last), last));
        return;
      }
      var below = line + 1;
      while (below < _lineStarts.length &&
          _firstCode(below) < 0 &&
          _comments.containsKey(below)) {
        below++;
      }
      if (below >= _lineStarts.length) return;
      final first = _firstCode(below);
      if (first < 0) return;
      final end = _segmentEnd(first);
      ranges.add((first, _blockEnds.contains(end) ? _lastCode(below) : end));
    });
    return ranges;
  }

  /// The identifier right before the innermost bracket around [offset]
  /// (`BoxShadow` inside `BoxShadow(color: …)`), or ''.
  String enclosingCall(int offset) {
    final open = _parent[offset];
    if (open < 0 || code.codeUnitAt(open) != _lparen) return '';
    final before = code.substring(max(0, open - 80), open);
    return RegExp(r'(\w+)\s*$').firstMatch(before)?.group(1) ?? '';
  }

  /// The named argument whose value [offset] sits in (`barrierColor` for
  /// `barrierColor: Colors.black54`), or ''.
  String argumentLabel(int offset) {
    final head = code.substring(_segmentStart(offset), offset);
    return RegExp(r'^\s*(\w+)\s*:').firstMatch(head)?.group(1) ?? '';
  }

  String _lineText(int line) {
    final end = line + 1 < _lineStarts.length
        ? _lineStarts[line + 1] - 1
        : source.length;
    final text = source.substring(_lineStarts[line], end).trim();
    return text.length > 110 ? '${text.substring(0, 107)}...' : text;
  }

  int _lineEnd(int line) =>
      line + 1 < _lineStarts.length ? _lineStarts[line + 1] - 1 : code.length;

  int _firstCode(int line) {
    for (var i = _lineStarts[line]; i < _lineEnd(line); i++) {
      if (!_isSpace(code.codeUnitAt(i))) return i;
    }
    return -1;
  }

  int _lastCode(int line) {
    for (var i = _lineEnd(line) - 1; i >= _lineStarts[line]; i--) {
      if (!_isSpace(code.codeUnitAt(i))) return i;
    }
    return -1;
  }

  /// First offset of the argument, item or statement holding [offset].
  int _segmentStart(int offset) {
    final open = _parent[offset];
    var start = open + 1;
    for (final sep in _separators[open] ?? const <int>[]) {
      if (sep >= offset) break;
      start = sep + 1;
    }
    return start;
  }

  /// Last offset of the argument, item or statement holding [offset].
  int _segmentEnd(int offset) {
    final open = _parent[offset];
    for (final sep in _separators[open] ?? const <int>[]) {
      if (sep >= offset) return sep;
    }
    return open < 0 ? code.length - 1 : _closer[open] ?? code.length - 1;
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

  void _mapBrackets() {
    int at(int i) => i >= 0 && i < code.length ? code.codeUnitAt(i) : -1;
    List<int> seps(int open) => _separators.putIfAbsent(open, () => <int>[]);
    final stack = <int>[];
    int top() => stack.isEmpty ? -1 : stack.last;
    for (var i = 0; i < code.length; i++) {
      final c = code.codeUnitAt(i);
      if (c == _rparen || c == _rbracket || c == _rbrace) {
        // A `<` still open here was a comparison, not type arguments.
        while (stack.isNotEmpty && at(stack.last) == _lt) {
          stack.removeLast();
        }
        if (stack.isNotEmpty) _closer[stack.removeLast()] = i;
        _parent[i] = top();
        if (c == _rbrace && (top() < 0 || at(top()) == _lbrace)) {
          var j = i + 1;
          while (_isSpace(at(j))) {
            j++;
          }
          // A closed block ends a statement; a closed literal or closure
          // (`};`, `},`, `})`) is still part of its expression.
          if (!';,)].?:'.codeUnits.contains(at(j))) {
            seps(top()).add(i);
            _blockEnds.add(i);
          }
        }
        continue;
      }
      // dart format spaces a comparison (`a < b`); type arguments hug their
      // first type (`List<Color>`, `<String, Color>{`, `showDialog<bool>(`).
      // So an open `<` is type arguments, and the next `>` that is not part
      // of `=>` or `>=` closes it, even on a line of its own.
      if (c == _gt &&
          at(top()) == _lt &&
          at(i - 1) != _eq &&
          at(i + 1) != _eq) {
        _closer[stack.removeLast()] = i;
        _parent[i] = top();
        continue;
      }
      _parent[i] = top();
      final typeArgs =
          c == _lt && (_isIdentStart(at(i + 1)) || at(i + 1) == _lparen);
      if (c == _lparen || c == _lbracket || c == _lbrace || typeArgs) {
        stack.add(i);
      } else if (c == _comma || c == _semicolon) {
        seps(top()).add(i);
      }
    }
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
const _slash = 47, _semicolon = 59, _lt = 60, _eq = 61, _gt = 62;
const _lbracket = 91, _backslash = 92, _rbracket = 93, _r = 114;
const _lbrace = 123, _rbrace = 125;
