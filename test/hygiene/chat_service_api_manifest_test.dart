// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The public surface of ChatService, pinned by name. The ChatService
// decomposition (docs/design/chat-service-decomposition.md) moves state out
// of the shell into doors and keeps every name a consumer calls today
// reachable through bridges. This test is how a package proves it moved code
// and not the surface: any public name that appears or disappears fails.
//
// "Reachable on a ChatService value" means, read from source:
//   * members of the `ChatService` class body,
//   * members of every mixin in its `with` clause,
//   * members of every public (named, not `_`) `extension … on ChatService`
//     in the shell library (lib/services/chat_service.dart and its parts) and
//     in every library the shell exports, through `show` / `hide`, and on
//     through those libraries' own exports.
// A name is recorded once, bare: a getter and its setter are one name.
// Private names, statics, constructors, operators and what ChangeNotifier
// already provides (notifyListeners, dispose, …) are not recorded.
//
// The baseline test/baselines/chat_service_api.json is the sorted list. A
// package that must change it names the change and why in its PR body, and
// the edit needs the maintainer's approved-test-change label.
//
// The source is read with the blanked-comment scanner in
// test/helpers/dart_source.dart (package:analyzer is not a direct
// dependency). The member scanner below is shared with
// chat_service_field_bag_ratchet_test.dart; its fixture tests are here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/source_ratchet.dart';

/// The ChatService shell library.
const kChatServiceShell = 'lib/services/chat_service.dart';

const _baselinePath = 'test/baselines/chat_service_api.json';

/// Members a ChatService value gets from ChangeNotifier or Object. The class
/// overrides some of them; they are still not ChatService's API.
const _inherited = {
  'addListener',
  'dispose',
  'hasListeners',
  'hashCode',
  'noSuchMethod',
  'notifyListeners',
  'removeListener',
  'runtimeType',
  'toString',
};

/// What a class, mixin or extension body declares.
enum MemberKind { field, getter, setter, method, constructor, operator }

/// One name declared directly in a class, mixin or extension body.
class DartMember {
  const DartMember(this.kind, this.name, this.line, {required this.isStatic});

  final MemberKind kind;
  final String name;

  /// 1-based line of the declaration's first token.
  final int line;
  final bool isStatic;

  bool get isPublic => !name.startsWith('_');

  @override
  String toString() => '${kind.name} $name (line $line)';
}

/// A top-level `class`, `mixin` or `extension` with a `{…}` body.
class DartDeclaration {
  DartDeclaration._(
    this.source,
    this.keyword,
    this.name,
    this.header,
    this.bodyStart,
    this.bodyEnd,
  );

  final DartSource source;

  /// `class`, `mixin` or `extension`.
  final String keyword;

  /// '' for an unnamed extension.
  final String name;

  /// The code between the name and the body's `{`, whitespace collapsed.
  final String header;

  /// Offsets of the body's `{` and its matching `}`.
  final int bodyStart;
  final int bodyEnd;

  /// The type after `on` (an extension's target, a mixin's constraint).
  String get onType =>
      RegExp(
        r'(?:^|\s)on\s+(.+?)(?:\s+(?:implements|with)\s|$)',
      ).firstMatch(header)?.group(1)?.replaceAll(' ', '') ??
      '';

  /// The mixins in a class's `with` clause, type arguments dropped.
  List<String> get mixins {
    final clause = RegExp(
      r'(?:^|\s)with\s+(.+?)(?:\s+implements\s|$)',
    ).firstMatch(header)?.group(1);
    if (clause == null) return const [];
    return [
      for (final part in _splitTopLevel(clause))
        part.replaceAll(RegExp(r'<.*$'), '').trim(),
    ];
  }

  late final List<DartMember> members = memberDeclarations(
    source,
    bodyStart + 1,
    bodyEnd,
    typeName: name,
  );
}

final _declarationKeyword = RegExp(r'(?<![\w$.])(class|mixin|extension)(?=\s)');
final _identifier = RegExp(r'[A-Za-z_$][\w$]*');

/// Every top-level class, mixin and extension in [source] that has a body.
/// Extension types and `class X = Y with Z;` aliases are skipped.
List<DartDeclaration> declarationsIn(DartSource source) {
  final code = source.code;
  final found = <DartDeclaration>[];
  var after = 0;
  for (final m in _declarationKeyword.allMatches(code)) {
    if (m.start < after) continue;
    final keyword = m[1]!;
    var name = '';
    var i = _skipSpace(code, m.end);
    final ident = _identifier.matchAsPrefix(code, i);
    if (ident == null) continue;
    final word = ident[0]!;
    if (keyword == 'extension' && word == 'type') continue;
    if (keyword == 'mixin' && word == 'class') continue;
    if (!(keyword == 'extension' && word == 'on')) {
      name = word;
      i = ident.end;
    }
    final brace = code.indexOf('{', i);
    final semicolon = code.indexOf(';', i);
    if (brace < 0 || (semicolon >= 0 && semicolon < brace)) continue;
    final close = _matchingBrace(code, brace);
    found.add(
      DartDeclaration._(
        source,
        keyword,
        name,
        code.substring(i, brace).replaceAll(RegExp(r'\s+'), ' ').trim(),
        brace,
        close,
      ),
    );
    after = close + 1;
  }
  return found;
}

/// Every member declared directly in the body between [from] and [to] (the
/// offsets just inside its braces). [typeName] names the constructors.
List<DartMember> memberDeclarations(
  DartSource source,
  int from,
  int to, {
  required String typeName,
}) {
  final code = source.code;
  final members = <DartMember>[];
  var start = from, depth = 0;
  var assigned = false, initializerList = false;
  void emit(int end) {
    members.addAll(_classify(source, start, end, typeName));
    start = end;
    depth = 0;
    assigned = false;
    initializerList = false;
  }

  for (var i = from; i < to; i++) {
    switch (code[i]) {
      case '(' || '[':
        depth++;
      case ')' || ']' || '}':
        depth--;
      case '{':
        // A `{` at member level before any `=` / `=>` opens a body.
        if (depth == 0 && !assigned) {
          i = _matchingBrace(code, i);
          emit(i + 1);
        } else {
          depth++;
        }
      case ';' when depth == 0:
        emit(i + 1);
      case '=' when depth == 0 && !initializerList && _assigns(code, i):
        assigned = true;
      case ':' when depth == 0 && !assigned:
        initializerList = true;
    }
  }
  return members;
}

final _annotation = RegExp(
  r'\s*@[A-Za-z_$][\w$]*(?:\s*\.\s*[A-Za-z_$][\w$]*)*\s*',
);
final _trailingAsync = RegExp(r'\s+(?:async\*?|sync\*)$');
final _getter = RegExp(r'(?<![\w$])get\s+([A-Za-z_$][\w$]*)$');
final _staticHead = RegExp(r'^(?:external\s+)?static\s');
final _trailingName = RegExp(r'[A-Za-z_$][\w$]*$');

List<DartMember> _classify(DartSource source, int from, int to, String type) {
  final code = source.code;
  var s = from;
  while (true) {
    final a = _annotation.matchAsPrefix(code, s);
    if (a == null) break;
    s = a.end;
    if (s < to && code[s] == '(') {
      s = _skipSpace(code, _matchingParen(code, s) + 1);
    }
  }
  s = _skipSpace(code, s);
  if (s >= to) return const [];
  final text = code.substring(s, to);
  final line = source.lineOf(s) + 1;

  var headerEnd = text.length, depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '(' || c == '[') depth++;
    if (c == ')' || c == ']') depth--;
    if (depth == 0 &&
        ((c == '=' && _assigns(text, i)) || c == '{' || c == ';' || c == ':')) {
      headerEnd = i;
      break;
    }
  }
  final header = text
      .substring(0, headerEnd)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(_trailingAsync, '');
  final isStatic = _staticHead.hasMatch(header);
  DartMember member(MemberKind kind, String name) =>
      DartMember(kind, name, line, isStatic: isStatic);

  if (_getter.firstMatch(header) case final g?) {
    return [member(MemberKind.getter, g[1]!)];
  }
  if (header.endsWith(')')) {
    final open = _openBefore(header, '(', ')');
    if (open < 0) throw StateError('unbalanced ) at ${source.path}:$line');
    var before = header.substring(0, open).trimRight();
    final typeParameters = before.endsWith('>')
        ? _openBefore(before, '<', '>')
        : -1;
    if (typeParameters > 0) {
      before = before.substring(0, typeParameters).trimRight();
    }
    final name = _trailingName.firstMatch(before);
    if (name == null) return [member(MemberKind.operator, 'operator')];
    final prefix = before.substring(0, name.start).trimRight();
    if (RegExp(r'(?<![\w$])set$').hasMatch(prefix)) {
      return [member(MemberKind.setter, name[0]!)];
    }
    if (RegExp(r'(?<![\w$])operator$').hasMatch(prefix)) {
      return [member(MemberKind.operator, 'operator')];
    }
    final isConstructor =
        name[0] == type ||
        prefix.endsWith('.') ||
        RegExp(r'(?<![\w$])factory(?![\w$])').hasMatch(prefix);
    return [
      member(
        isConstructor ? MemberKind.constructor : MemberKind.method,
        name[0]!,
      ),
    ];
  }
  final body = text.endsWith(';') ? text.substring(0, text.length - 1) : text;
  final parts = _declarators(body);
  final first = parts.first.split('=').first.trimRight();
  final names = [
    if (_trailingName.firstMatch(first) case final n?) n[0]!,
    for (final part in parts.skip(1))
      if (RegExp(r'\s*([A-Za-z_$][\w$]*)\s*(?:=|$)').matchAsPrefix(part)
          case final n?)
        n[1]!,
  ];
  return [for (final n in names) member(MemberKind.field, n)];
}

/// A field declaration split at its top-level commas. Angle brackets count
/// only in the type, so `<String, int>{}` in an initializer can only yield a
/// part the caller's name pattern rejects.
List<String> _declarators(String text) {
  final parts = <String>[];
  var depth = 0, angle = 0, start = 0;
  var inInitializer = false;
  for (var i = 0; i < text.length; i++) {
    switch (text[i]) {
      case '(' || '[' || '{':
        depth++;
      case ')' || ']' || '}':
        depth--;
      case '<' when !inInitializer:
        angle++;
      case '>' when !inInitializer && angle > 0:
        angle--;
      case '=' when depth == 0 && angle == 0:
        inInitializer = true;
      case ',' when depth == 0 && angle == 0:
        parts.add(text.substring(start, i));
        start = i + 1;
        inInitializer = false;
    }
  }
  return parts..add(text.substring(start));
}

List<String> _splitTopLevel(String text) {
  final parts = <String>[];
  var depth = 0, start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '<' || c == '(') depth++;
    if (c == '>' || c == ')') depth--;
    if (c == ',' && depth == 0) {
      parts.add(text.substring(start, i));
      start = i + 1;
    }
  }
  return parts..add(text.substring(start));
}

int _skipSpace(String code, int i) {
  while (i < code.length && code.codeUnitAt(i) <= 32) {
    i++;
  }
  return i;
}

int _matchingBrace(String code, int open) => _matching(code, open, '{', '}');
int _matchingParen(String code, int open) => _matching(code, open, '(', ')');

int _matching(String code, int open, String opener, String closer) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == opener) depth++;
    if (code[i] == closer && --depth == 0) return i;
  }
  throw StateError('unbalanced $opener at offset $open');
}

/// The [opener] matching the [closer] that ends [text], or -1.
int _openBefore(String text, String opener, String closer) {
  var depth = 0;
  for (var i = text.length - 1; i >= 0; i--) {
    if (text[i] == closer) depth++;
    if (text[i] == opener && --depth == 0) return i;
  }
  return -1;
}

/// Whether the `=` at [i] is an assignment or `=>`, not part of `==`,
/// `!=`, `<=`, `>=` or `operator []=`.
bool _assigns(String code, int i) {
  final next = i + 1 < code.length ? code[i + 1] : '';
  final prev = i > 0 ? code[i - 1] : '';
  return next != '=' && !'=!<>]'.contains(prev);
}

/// A library: its file plus every `part` it names.
class DartLibrary {
  DartLibrary._(this.path, this.files);

  factory DartLibrary.read(String path) {
    final lib = DartSource.read(path);
    return DartLibrary._(path, [
      lib,
      for (final d in _directives(lib, 'part'))
        if (_resolve(path, d.uri) case final part?) DartSource.read(part),
    ]);
  }

  final String path;
  final List<DartSource> files;

  late final List<DartDeclaration> declarations = [
    for (final f in files) ...declarationsIn(f),
  ];

  /// `export` directives of the library file, URIs resolved to lib/ paths.
  /// A `dart:` or other package's export cannot extend ChatService and is
  /// left out.
  List<({String path, bool Function(String) visible})> get exports => [
    for (final d in _directives(files.first, 'export'))
      if (_resolve(path, d.uri) case final target?)
        (path: target, visible: d.visible),
  ];

  DartDeclaration? find(String keyword, String name) => declarations
      .where((d) => d.keyword == keyword && d.name == name)
      .firstOrNull;
}

/// `part` / `export` directives: the URI and what its combinators let out.
List<({String uri, bool Function(String) visible})> _directives(
  DartSource source,
  String keyword,
) {
  final code = source.code;
  final literals = {for (final s in source.strings) s.start: s};
  final out = <({String uri, bool Function(String) visible})>[];
  for (final m in RegExp('(?<![\\w\$.])$keyword(?=\\s)').allMatches(code)) {
    // Strings are blanked in [DartSource.code], so stop at a literal's start.
    var j = m.end;
    while (j < code.length &&
        !literals.containsKey(j) &&
        code.codeUnitAt(j) <= 32) {
      j++;
    }
    final literal = literals[j];
    if (literal == null) continue;
    final end = code.indexOf(';', literal.end);
    final tail = code.substring(literal.end, end < 0 ? code.length : end);
    final filters = <bool Function(String)>[
      for (final c in RegExp(
        r'\b(show|hide)\s+([\w$\s,]+?)(?=\s*(?:\bshow\b|\bhide\b|$))',
      ).allMatches(tail))
        if (c[2]!.split(',').map((n) => n.trim()).toSet() case final names)
          c[1] == 'show' ? names.contains : (n) => !names.contains(n),
    ];
    out.add((uri: literal.body, visible: (n) => filters.every((f) => f(n))));
  }
  return out;
}

const _selfPackage = 'package:front_porch_ai/';

String? _resolve(String from, String uri) {
  if (uri.startsWith(_selfPackage)) {
    return 'lib/${uri.substring(_selfPackage.length)}';
  }
  if (uri.contains(':')) return null;
  return p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
}

/// The ChatService library, failing loudly when the shell's shape moved so
/// far that the scanners can no longer see it.
DartLibrary chatServiceLibrary() => DartLibrary.read(kChatServiceShell);

DartDeclaration chatServiceClass(DartLibrary shell) =>
    shell.find('class', 'ChatService') ??
    (throw StateError('class ChatService not found in $kChatServiceShell'));

bool _onChatService(DartDeclaration d) =>
    d.keyword == 'extension' &&
    (d.onType == 'ChatService' || d.onType == 'ChatService?');

/// Every public extension on ChatService an importer of the shell sees:
/// the shell library's own, and those of each library it exports.
List<DartDeclaration> reachableExtensions(DartLibrary shell) {
  final found = <DartDeclaration>[];
  final seen = <String>{};
  void walk(DartLibrary lib, bool Function(String) visible) {
    if (!seen.add(lib.path)) return;
    found.addAll(
      lib.declarations.where(
        (d) =>
            _onChatService(d) &&
            d.name.isNotEmpty &&
            !d.name.startsWith('_') &&
            visible(d.name),
      ),
    );
    for (final e in lib.exports) {
      if (!File(e.path).existsSync()) {
        throw StateError('${lib.path} exports ${e.path}, which is missing');
      }
      walk(DartLibrary.read(e.path), (n) => visible(n) && e.visible(n));
    }
  }

  walk(shell, (_) => true);
  return found;
}

/// The public API of ChatService as bare, sorted, unique names.
List<String> chatServiceApi() {
  final shell = chatServiceLibrary();
  final cls = chatServiceClass(shell);
  final mixins = [
    for (final name in cls.mixins)
      shell.find('mixin', name) ??
          (throw StateError(
            'mixin $name (ChatService `with` clause) is not declared in the '
            'shell library, so its members cannot be listed. Teach '
            'chatServiceApi() in this test which library declares it.',
          )),
  ];
  final names = {
    for (final d in [cls, ...mixins, ...reachableExtensions(shell)])
      for (final m in d.members)
        if (m.isPublic &&
            !m.isStatic &&
            m.kind != MemberKind.constructor &&
            m.kind != MemberKind.operator &&
            !_inherited.contains(m.name))
          m.name,
  };
  return names.toList()..sort();
}

List<String> _readBaseline() {
  final file = File(_baselinePath);
  if (!file.existsSync()) {
    throw StateError(
      '$_baselinePath is missing. It must never be deleted: it is the '
      'ChatService public API the decomposition keeps.',
    );
  }
  final names = (jsonDecode(file.readAsStringSync()) as List).cast<String>();
  for (var i = 1; i < names.length; i++) {
    if (names[i - 1].compareTo(names[i]) >= 0) {
      throw StateError(
        '$_baselinePath must be sorted with no duplicates: "${names[i]}" '
        'comes after "${names[i - 1]}".',
      );
    }
  }
  return names;
}

void main() {
  test('the public names reachable on ChatService match the baseline', () {
    final baseline = _readBaseline().toSet();
    final tree = chatServiceApi().toSet();
    final added = tree.difference(baseline).toList()..sort();
    final removed = baseline.difference(tree).toList()..sort();
    if (added.isEmpty && removed.isEmpty) return;
    fail(
      [
        'The public API of ChatService changed '
            '(${baseline.length} names in $_baselinePath, ${tree.length} in '
            'the tree).',
        if (added.isNotEmpty) ...[
          'Added (${added.length}), not in the baseline:',
          for (final n in added) '  + $n',
        ],
        if (removed.isNotEmpty) ...[
          'Removed (${removed.length}), in the baseline but no longer '
              'reachable on a ChatService value:',
          for (final n in removed) '  - $n',
        ],
        'A decomposition package keeps every name: a moved member stays '
            'reachable through a bridge extension the shell exports '
            '(docs/design/chat-service-decomposition.md). If the change is '
            'intended, edit $_baselinePath in the same change, name each '
            'name and why in the PR body, and ask for approved-test-change.',
      ].join('\n'),
    );
  });

  test('the scanner sees the declarations it reads', () {
    final shell = chatServiceLibrary();
    final cls = chatServiceClass(shell);
    expect(cls.mixins, isNotEmpty, reason: 'ChatService has a with clause');
    expect(
      reachableExtensions(shell),
      isNotEmpty,
      reason: 'the shell library declares extensions on ChatService',
    );
    // Every `extension … on ChatService` written in the library is either
    // counted or is unnamed / private, so a header the scanner misreads
    // cannot drop a whole extension silently.
    final written = RegExp(
      r'(?<![\w$.])extension\s+(?!type\b)[^{;]*?\bon\s+ChatService\b',
    );
    final headers = [
      for (final f in shell.files) ...written.allMatches(f.code),
    ].length;
    final scanned = shell.declarations.where(_onChatService).length;
    expect(scanned, headers);
  });

  test('member scanner: names, kinds and what is not API', () {
    final source = DartSource('fixture.dart', _fixture);
    final decls = declarationsIn(source);
    expect(decls.map((d) => '${d.keyword} ${d.name}'), [
      'class Fixture',
      'mixin Bag',
      'extension FixtureApi',
      'extension ',
      'extension _Hidden',
    ]);
    final cls = decls.first;
    expect(cls.mixins, ['Bag', 'Other']);
    expect(decls[2].onType, 'Fixture');
    String show(DartMember m) =>
        '${m.kind.name}${m.isStatic ? '+static' : ''} ${m.name}';
    expect(cls.members.map(show), [
      'field _a',
      'field b',
      'field _c',
      'field late1',
      'field _rec',
      'field _fn',
      'field m1',
      'field m2',
      'field+static k',
      'constructor Fixture',
      'constructor named',
      'constructor make',
      'getter g',
      'setter g',
      'getter block',
      'method run',
      'method gen',
      'method stream',
      'method _private',
      'operator operator',
      'method notifyListeners',
    ]);
    expect(decls[1].members.map(show), [
      'field _x',
      'getter _y',
      'setter _y',
      'method opened',
    ]);
    expect(decls[2].members.map(show), [
      'method send',
      'getter label',
      'field+static z',
    ]);
  });

  test('directives: parts, exports and their combinators', () {
    final source = DartSource('lib/a/shell.dart', '''
export 'chat/one.dart' show Keep, Also;
export "package:front_porch_ai/two.dart" hide Drop;
export 'package:other/three.dart';
part 'chat/body.dart';
''');
    final exports = _directives(source, 'export');
    expect(exports.map((e) => _resolve(source.path, e.uri)), [
      'lib/a/chat/one.dart',
      'lib/two.dart',
      null,
    ]);
    expect(exports[0].visible('Keep'), isTrue);
    expect(exports[0].visible('Also'), isTrue);
    expect(exports[0].visible('Other'), isFalse);
    expect(exports[1].visible('Drop'), isFalse);
    expect(exports[1].visible('Keep'), isTrue);
    expect(_directives(source, 'part').map((d) => d.uri), ['chat/body.dart']);
  });
}

const _fixture = r'''
class Fixture extends ChangeNotifier with Bag, Other<int> {
  final int _a;
  String? b, _c;
  late final late1 = build(() => {'x': 1});
  ({String key, int n})? _rec;
  void Function(String? s)? _fn = (s) { print(s); };
  Map<String, int> m1 = <String, int>{}, m2 = {};
  static const k = 'class Nope { int notAField = 1; }';
  Fixture(this._a) : b = 'x' { init(); }
  Fixture.named() : this(1);
  factory Fixture.make() => Fixture(2);
  int get g => _a; // set g(int v) is a comment
  set g(int v) {}
  List<int> get block {
    return [1];
  }
  @visibleForTesting
  Future<void> run({int n = 3}) async {
    final local = 1;
  }
  T gen<T>(T v) => v;
  Stream<int> stream() async* {}
  void _private() {}
  bool operator ==(Object o) => true;
  @override
  void notifyListeners() {}
}

mixin Bag on ChangeNotifier {
  int _x = 0;
  int get _y => _x;
  set _y(int v) => _x = v;
  void opened() {
    if (_x++ == 0) notifyListeners();
  }
}

extension FixtureApi on Fixture {
  Future<void> send(String text) async => text;
  String get label => '{';
  static int z = 0;
}

extension on Fixture {
  int get hidden => 0;
}

extension _Hidden on Fixture? {
  int get alsoHidden => 0;
}

extension type Wrapped(int v) {}
''';
