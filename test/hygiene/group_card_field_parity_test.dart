// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// GROUP CARD FIELD PARITY. A group member is the group's own copy of a
// character: its group_members row holds a whole card and its own Front
// Porch extensions. A field the 1:1 editor sets and a 1:1 chat reads has to
// be editable on the member (the member editor, desktop and phone) and read
// per member when a group turn runs, or it ships 1:1-only.
//
// The fields come from the code, never from a list typed here: the fields
// each card model declares and the keys its toJson writes, for
// CharacterCard, FrontPorchExtensions and the objects nested in it
// (RecoveryProfile, GreetingRealismSeed). Any other lib/models class a field
// is typed with must be enumerated here too or named opaque, with a reason,
// in the manifest.
//
// The manifest, docs/design/group-card-field-manifest.json, gives each field
// the places a member's value is edited and read in a group, or one reasoned
// exemption. A new field adds a manifest entry, not a test edit.
//
// WHAT A PLACE PROVES. A place is a pointer to the read or the control: the
// named file, inside the named function, still contains the marker (comments
// stripped, and string contents too unless the marker quotes one; whitespace
// between tokens free). It is not proof of behaviour; the member editor
// tests (group_member_edits_save_test, CharacterEditPage.member.test.tsx) pin
// behaviour. Some editor marker on a member-editor surface (_editorSurfaces)
// and some reader marker outside the models and the relay must name the
// field itself (its name or JSON key), and a place two fields claim, however
// its marker is spaced, must say why it is shared, so an entry copied from
// another field, or pointed at the codec, fails. A read that happens
// in a helper is a chain: the group read first, then each `hop` the place
// before it calls.
//
// MEMBER MODE. A control counts only where a member's editor renders it.
// Hidden, in Dart and TSX: `{notMember && …}`, the member-false branch of a
// ternary on a member test (`member ? A : B`, `memberGroup == null ? A : B`,
// and the inverses), and a Dart collection-if on one (and its else). A
// switch the member editor sets from "not a member" (`showX: member == null`
// on desktop, `showX={!member}` on the phone) must be listed with the fields
// it hides, none of which may claim an editor. Not seen: a control a shared
// sub-widget hides by some other condition, dead code after a return, and a
// 1:1-only branch the place's function takes on its own.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source.dart';

const _manifestPath = 'docs/design/group-card-field-manifest.json';

/// A card model whose fields are enumerated: its declared fields and the
/// keys [toJson] writes. [decode], when set, must read every key [toJson]
/// writes. Field keys are `<prefix>.<field>`.
class _Model {
  const _Model(
    this.prefix,
    this.path,
    this.className, {
    required this.toJson,
    this.toJsonPath,
    this.decode,
    this.containers = const {},
  });

  final String prefix;
  final String path;
  final String className;
  final String toJson;
  final String? toJsonPath;
  final String? decode;

  /// Fields whose content is a model of its own, enumerated as that model.
  final Set<String> containers;
}

const _models = [
  _Model(
    'card',
    'lib/models/character_card.dart',
    'CharacterCard',
    toJson: 'CharacterCard.toJson',
    containers: {'frontPorchExtensions', 'extensions'},
  ),
  _Model(
    'ext',
    'lib/models/character/front_porch_extensions.dart',
    'FrontPorchExtensions',
    toJsonPath: 'lib/models/character/front_porch_extensions_codec.dart',
    toJson: 'encodeFrontPorchExtensions',
    decode: 'decodeFrontPorchExtensions',
  ),
  _Model(
    'ext.recovery',
    'lib/models/character/recovery_profile.dart',
    'RecoveryProfile',
    toJson: 'RecoveryProfile.toJson',
    decode: 'RecoveryProfile.fromJson',
  ),
  _Model(
    'ext.greetingSeeds',
    'lib/models/greeting_realism_seed.dart',
    'GreetingRealismSeed',
    toJson: 'GreetingRealismSeed.toJson',
    decode: 'GreetingRealismSeed.fromJson',
  ),
];

/// The phone's edit reaches a member through the relay: an entry with a
/// web control also names the relay's read of the posted key (set) and its
/// write of the key the page loads (get), in one of these functions.
const _relays = <String, ({Set<String> set, Set<String> get})>{
  'card': (
    set: {'applyCharacterFields', 'GroupMemberEdit.update'},
    get: {'GroupMemberEdit.detail'},
  ),
  'ext': (
    set: {'frontPorchFromFields', 'GroupMemberStart.fromJson'},
    get: {'frontPorchToJson', 'GroupMemberStart.toJson'},
  ),
  'ext.recovery': (
    set: {'RecoveryProfile.fromFields'},
    get: {'RecoveryProfile.toFields'},
  ),
  'ext.greetingSeeds': (
    set: {'GreetingRealismSeed.fromJson'},
    get: {'GreetingRealismSeed.toFields'},
  ),
};

/// The desktop editor's Save: an entry with a control on the Edit Character
/// page also names where Save writes the field back onto the card.
const _desktopEditor = 'lib/ui/pages/edit_character_page';
const _desktopSaves = <String, Set<String>>{
  'card': {
    'EditCharacterCardWriter.writeFields',
    'EditCharacterCardWriter.writeLorebook',
  },
  // A member's start saves to the group's seed for them, from the page.
  'ext': {'EditCharacterCardWriter._writeExtensions', '_saveCharacter'},
};

const _exemptions = [
  'groupWide',
  'notRead',
  'soloOnly',
  'origin',
  'runtimeOnly',
];
const _entryKeys = {
  'editor',
  'reader',
  'noEditor',
  'noPhone',
  'note',
  ..._exemptions,
};

// ── Reading source ───────────────────────────────────────────────────────

final _dart = <String, DartSource>{};
DartSource _source(String path) =>
    _dart.putIfAbsent(path, () => DartSource.read(path));

/// A file as markers see it. [code] has comments and string contents
/// blanked; [withStrings] has only comments blanked; [strings] are the
/// literals' spans (quote to quote). Offsets match the file.
typedef _Read = ({
  String code,
  String withStrings,
  List<({int start, int end})> strings,
});

final _reads = <String, _Read>{};

_Read _read(String path) => _reads.putIfAbsent(path, () {
  if (path.endsWith('.dart')) {
    final s = _source(path);
    final out = s.code.codeUnits.toList();
    for (final str in s.strings) {
      for (var i = str.start; i < str.end; i++) {
        out[i] = s.source.codeUnitAt(i);
      }
    }
    return (
      code: s.code,
      withStrings: String.fromCharCodes(out),
      strings: [for (final str in s.strings) (start: str.start, end: str.end)],
    );
  }
  return _readTs(File(path).readAsStringSync());
});

/// [ts] read like a Dart file: `//` and `/* */` comments, and string and
/// template literal contents, recognised by a quote-aware scan.
_Read _readTs(String ts) {
  final code = ts.codeUnits.toList();
  final kept = ts.codeUnits.toList();
  final strings = <({int start, int end})>[];
  void blank(List<int> out, int from, int to) {
    for (var j = from; j < to; j++) {
      if (out[j] != 10) out[j] = 32;
    }
  }

  var i = 0;
  while (i < ts.length) {
    final c = ts[i];
    if (c == "'" || c == '"' || c == '`') {
      var j = i + 1;
      while (j < ts.length && ts[j] != c) {
        j += ts[j] == r'\' ? 2 : 1;
      }
      final end = j < ts.length ? j + 1 : ts.length;
      blank(code, i + 1, end - 1);
      strings.add((start: i, end: end));
      i = end;
      continue;
    }
    final next = i + 1 < ts.length ? ts[i + 1] : '';
    if (c == '/' && (next == '/' || next == '*')) {
      final end = next == '/'
          ? ts.indexOf('\n', i).let((e) => e < 0 ? ts.length : e)
          : ts.indexOf('*/', i + 2).let((e) => e < 0 ? ts.length : e + 2);
      blank(code, i, end);
      blank(kept, i, end);
      i = end;
      continue;
    }
    i++;
  }
  return (
    code: String.fromCharCodes(code),
    withStrings: String.fromCharCodes(kept),
    strings: strings,
  );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// The matching closer of the bracket at [open] in [code], or -1.
int _close(String code, int open) {
  const pairs = {'(': ')', '[': ']', '{': '}'};
  final stack = <String>[];
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (pairs.containsKey(c)) {
      stack.add(pairs[c]!);
    } else if (stack.isNotEmpty && c == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) return i;
    }
  }
  return -1;
}

/// The `{…}` of `class` / `extension` / `mixin` [name] in [code].
({int start, int end})? _typeBody(String code, String name) {
  final head = RegExp(
    '(?:class|extension|mixin)\\s+$name\\b[^{;]*\\{',
  ).firstMatch(code);
  if (head == null) return null;
  final end = _close(code, head.end - 1);
  return end < 0 ? null : (start: head.end - 1, end: end + 1);
}

/// The body of the function, method, getter or constructor [spec] (`fn`, or
/// `Type.fn` for one declared in that type or as `Type.fn(`) in [path].
({int start, int end}) _bodyOf(String path, String spec) {
  final code = _source(path).code;
  final dot = spec.indexOf('.');
  final type = dot < 0 ? null : spec.substring(0, dot);
  final name = dot < 0 ? spec : spec.substring(dot + 1);
  final within = type == null ? null : _typeBody(code, type);
  final candidates = RegExp(
    '(?:(?<![\\w\$.])(?:get\\s+)?$name|'
    '${type == null ? r'(?!)' : '(?<![\\w\$])$type\\.$name'})\\s*(?=[(=]|\\{)',
  ).allMatches(code);
  final found = <({int start, int end})>[];
  for (final m in candidates) {
    final inType =
        within != null && m.start > within.start && m.start < within.end;
    final qualified = type != null && m[0]!.startsWith('$type.');
    if (type != null && !inType && !qualified) continue;
    var i = m.end;
    if (i < code.length && code[i] == '(') {
      final close = _close(code, i);
      if (close < 0) continue;
      i = close + 1;
    } else if (!m[0]!.startsWith('get')) {
      continue;
    }
    i = _skipSpace(code, i);
    for (final mod in ['async*', 'async', 'sync*']) {
      if (code.startsWith(mod, i)) i = _skipSpace(code, i + mod.length);
    }
    if (i < code.length && code[i] == '{') {
      found.add((start: i, end: _close(code, i) + 1));
    } else if (code.startsWith('=>', i)) {
      var depth = 0, j = i + 2;
      for (; j < code.length; j++) {
        final c = code[j];
        if ('([{'.contains(c)) depth++;
        if (')]}'.contains(c)) depth--;
        if (c == ';' && depth == 0) break;
      }
      found.add((start: i, end: j + 1));
    }
  }
  if (found.length != 1) {
    throw StateError(
      '$path: ${found.isEmpty ? 'no' : '${found.length}'} declarations of '
      '$spec; name one function (Type.fn when the name repeats)',
    );
  }
  return found.single;
}

int _skipSpace(String code, int i) {
  while (i < code.length && code[i].trim().isEmpty) {
    i++;
  }
  return i;
}

// ── Enumerating the fields ───────────────────────────────────────────────

/// A declared field: its name and its type as written.
typedef _Decl = ({String name, String type});

/// The public instance fields [className] declares, in [code] (comments and
/// strings blanked). Handles `T a, b;`, initializers, annotations and
/// record types; skips methods, getters, setters, constructors and statics.
List<_Decl> _declaredFields(String code, String className) {
  final body = _typeBody(code, className);
  if (body == null) throw StateError('no class $className');
  final fields = <_Decl>[];
  var depth = 0, start = body.start + 1;
  for (var i = body.start + 1; i < body.end - 1; i++) {
    final c = code[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) {
      depth--;
      if (c == '}' && depth == 0) start = i + 1;
      continue;
    }
    if (c == '{' && depth == 1) continue;
    if (c != ';' || depth != 0) continue;
    final statement = _withoutAnnotations(code.substring(start, i)).trim();
    start = i + 1;
    fields.addAll(_fieldsOf(statement));
  }
  return fields;
}

String _withoutAnnotations(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s[i] == '@') {
      var j = i + 1;
      while (j < s.length && RegExp(r'[\w$.]').hasMatch(s[j])) {
        j++;
      }
      final k = _skipSpace(s, j);
      if (k < s.length && s[k] == '(') j = _close(s, k) + 1;
      i = j;
      continue;
    }
    out.write(s[i]);
    i++;
  }
  return out.toString();
}

List<_Decl> _fieldsOf(String statement) {
  if (statement.isEmpty ||
      statement.startsWith(')') ||
      statement.contains('=>') ||
      RegExp(
        r'\b(?:static|get|set|factory|operator|typedef)\b',
      ).hasMatch(statement)) {
    return const [];
  }
  final parts = _splitTopLevel(statement, ',');
  final out = <_Decl>[];
  String? type;
  for (var p = 0; p < parts.length; p++) {
    final eq = _topLevelIndex(parts[p], '=');
    final decl = (eq < 0 ? parts[p] : parts[p].substring(0, eq)).trim();
    // A constructor (`Name(…)`), initializer list (`) : a = b`) or method.
    if (decl.endsWith(')') || decl.contains(':')) return const [];
    final name = RegExp(r'([A-Za-z_$][\w$]*)$').firstMatch(decl)?[1];
    if (name == null) return const [];
    if (p == 0) {
      type = decl
          .substring(0, decl.length - name.length)
          .replaceFirst(RegExp(r'^\s*(?:late\s+)?(?:final\s+|var\s+)?'), '')
          .trim();
      if (type.isEmpty) return const [];
    } else if (decl != name) {
      return const [];
    }
    if (!name.startsWith('_')) out.add((name: name, type: type!));
  }
  return out;
}

List<String> _splitTopLevel(String s, String sep) {
  final parts = <String>[];
  var depth = 0, start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if ('([{<'.contains(c)) depth++;
    if (')]}>'.contains(c)) depth--;
    if (c == sep && depth == 0) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(s.substring(start));
  return parts;
}

int _topLevelIndex(String s, String c) {
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if ('([{<'.contains(ch)) depth++;
    if (')]}>'.contains(ch)) depth--;
    if (ch == c && depth == 0) {
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (next != '=' && next != '>') return i;
    }
  }
  return -1;
}

/// A `'key': value` entry of a map literal, with the `if (…)` guarding it.
typedef _MapEntry = ({String key, String value, String guard});

List<_MapEntry> _mapEntries(String path, String function) {
  final source = _source(path);
  final body = _bodyOf(path, function);
  final code = source.code;
  final entries = <_MapEntry>[];
  for (final s in source.strings) {
    if (s.start <= body.start || s.end >= body.end) continue;
    final i = _skipSpace(code, s.end);
    if (i >= body.end || code[i] != ':') continue;
    var depth = 0, j = i + 1;
    for (; j < body.end; j++) {
      final c = code[j];
      if ('([{'.contains(c)) {
        depth++;
      } else if (')]}'.contains(c)) {
        if (depth-- == 0) break;
      } else if (c == ',' && depth == 0) {
        break;
      }
    }
    entries.add((
      key: s.body,
      value: code.substring(i + 1, j).trim(),
      guard: _guardBefore(code, s.start),
    ));
  }
  return entries;
}

String _guardBefore(String code, int offset) {
  var i = offset - 1;
  while (i >= 0 && code[i].trim().isEmpty) {
    i--;
  }
  if (i < 0 || code[i] != ')') return '';
  final close = i;
  var depth = 0;
  for (; i >= 0; i--) {
    if (code[i] == ')') depth++;
    if (code[i] == '(' && --depth == 0) break;
  }
  if (i < 0 || !code.substring(0, i).trimRight().endsWith('if')) return '';
  return code.substring(i + 1, close);
}

/// The field a toJson entry writes: the first declared field its value (or
/// its guard) names; else the first `e.x` or name, so a getter shows up.
String? _accessorOf(_MapEntry e, Set<String> declared) {
  if (e.value.startsWith('{')) return null; // a nested map: its keys follow
  for (final text in [e.value, e.guard]) {
    final names = [
      for (final m in RegExp(r'[A-Za-z_$][\w$]*').allMatches(text)) m[0]!,
    ];
    for (final n in names) {
      if (declared.contains(n)) return n;
    }
  }
  return _codecRead.firstMatch(e.value)?[1] ??
      _firstName.firstMatch(e.value)?[0];
}

final _codecRead = RegExp(r'(?<![\w$.])e\.(\w+)');
final _firstName = RegExp(r'(?<![\w$.])[A-Za-z_$][\w$]*');

/// [model]'s fields: declared ∪ written by toJson, with their JSON keys.
({List<_Decl> declared, Map<String, String> keys}) _fieldsOfModel(_Model m) {
  final declared = _declaredFields(_source(m.path).code, m.className);
  final names = {for (final d in declared) d.name};
  final keys = <String, String>{};
  for (final e in _mapEntries(m.toJsonPath ?? m.path, m.toJson)) {
    final accessor = _accessorOf(e, names);
    if (accessor != null && accessor != 'e') keys[accessor] = e.key;
  }
  return (declared: declared, keys: keys);
}

// ── Places ───────────────────────────────────────────────────────────────

/// Where a field is edited or read: [marker] inside function [inFn] of
/// [path]. [shared] says why other fields claim the same place; [hop] marks
/// a helper the place before it calls (the read happens there, not here).
class _Place {
  _Place(Map<String, dynamic> json)
    : path = json['path'] as String,
      inFn = json['in'] as String?,
      marker = json['marker'] as String,
      shared = json['shared'] as String?,
      hop = json['hop'] as String?,
      unknown = json.keys.toSet().difference(_placeKeys);
  final String path;
  final String? inFn;
  final String marker;
  final String? shared;
  final String? hop;
  final Set<String> unknown;

  /// The same place however the marker is spaced.
  String get identity =>
      '$path|${inFn ?? ''}|${marker.replaceAll(RegExp(r'\s+'), '')}';

  @override
  String toString() => '$path${inFn == null ? '' : ' in $inFn'} "$marker"';
}

const _placeKeys = {'path', 'in', 'marker', 'shared', 'hop', 'why'};

/// Where a member's value is edited: the member editors (desktop and
/// phone), the form widgets they share, UI Settings, and the group's own
/// promote and demote. The editor that names a field must be one of these,
/// never a codec, a decoder, the relay or a model.
const _editorSurfaces = [
  'lib/ui/pages/edit_character_page',
  'lib/ui/widgets/',
  'lib/ui/dialogs/ui_settings',
  'lib/services/chat/group_lite.dart',
  'web_ui/src/',
];

/// Never where a group reads a field: the models and codecs, the relay.
/// A model helper counts only as a hop from a read outside these.
const _notReaders = [
  'lib/models/',
  'lib/services/web/util/realism_extensions_json.dart',
  'lib/services/web/facade/character/character_card_edits.dart',
  'lib/services/group_member_start.dart',
];

bool _under(String path, List<String> prefixes) =>
    prefixes.any((p) => path.startsWith(p));

/// Whether [marker] names [name] as a whole token.
bool _names(String marker, String name) =>
    RegExp('(?<![\\w\$])${RegExp.escape(name)}(?![\\w\$])').hasMatch(marker);

List<_Place> _places(Object? json) => [
  for (final p in (json as List?) ?? const [])
    _Place(p as Map<String, dynamic>),
];

/// [marker] as a pattern: free whitespace between tokens, a word token never
/// matched inside a longer name.
RegExp _markerPattern(String marker) {
  final tokens = RegExp(r'[\w$]+|\S').allMatches(marker).toList();
  final b = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i][0]!;
    if (i > 0) {
      final gap = marker.substring(tokens[i - 1].end, tokens[i].start);
      final words =
          RegExp(r'[\w$]$').hasMatch(tokens[i - 1][0]!) &&
          RegExp(r'^[\w$]').hasMatch(t);
      b.write(words && gap.isNotEmpty ? r'\s+' : r'\s*');
    }
    b.write(RegExp.escape(t));
  }
  final head = RegExp(r'^[\w$]').hasMatch(marker) ? r'(?<![\w$])' : '';
  final tail = RegExp(r'[\w$]$').hasMatch(marker) ? r'(?![\w$])' : '';
  return RegExp('$head$b$tail');
}

// ── Member-mode hiding ───────────────────────────────────────────────────

/// How the member editors name "this is a member's editor".
const _memberName =
    r'(?:widget\.)?(?:member|memberName|memberGroup|memberOfGroup)';

/// A condition true only in a member's editor, and one true only outside it.
const _isMember =
    '(?<![\\w\$.!])$_memberName(?:\\s*(?:!==\\s*undefined|!=\\s*null))?';
const _notMember =
    '(?:(?<![\\w\$.])!\\s*$_memberName|(?<![\\w\$.!])$_memberName\\s*'
    '(?:===\\s*undefined|==\\s*null))';

/// The end (exclusive) of the expression starting at [i]: the first `,`,
/// `;` or `:` (when [stopAtColon]) at depth 0, or the closer of the bracket
/// it sits in.
int _expressionEnd(String code, int i, {required bool stopAtColon}) {
  var depth = 0;
  for (; i < code.length; i++) {
    final c = code[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) {
      if (depth == 0) return i;
      depth--;
    }
    if (depth == 0 && (c == ',' || c == ';' || (stopAtColon && c == ':'))) {
      // `a ? b : c` inside the branch is nested, never the branch's own colon
      // (the scan treats `?:` pairs lazily; good enough for JSX and Dart args).
      return i;
    }
  }
  return code.length;
}

/// Spans of [path] (Dart or TSX, string contents blanked) that render only
/// outside a member's editor: `{notMember && X}`; the member-false branch
/// of `isMember ? A : B` / `notMember ? A : B`; the body of a Dart
/// collection-if on a member test, and its else.
List<({int start, int end})> _memberHiddenRegions(String path) {
  final code = _read(path).code;
  final regions = <({int start, int end})>[];
  for (final m in RegExp('\\{\\s*$_notMember\\s*&&').allMatches(code)) {
    regions.add((start: m.start, end: _close(code, m.start)));
  }
  final ternary = RegExp('(?:($_notMember)|$_isMember)\\s*\\?(?![.?\\[])');
  for (final m in ternary.allMatches(code)) {
    final thenStart = m.end;
    final colon = _expressionEnd(code, thenStart, stopAtColon: true);
    if (colon >= code.length || code[colon] != ':') continue;
    final elseEnd = _expressionEnd(code, colon + 1, stopAtColon: false);
    regions.add(
      m[1] != null
          ? (start: thenStart, end: colon)
          : (start: colon + 1, end: elseEnd),
    );
  }
  if (path.endsWith('.dart')) {
    final collectionIf = RegExp(
      '\\bif\\s*\\(\\s*(?:($_notMember)|$_isMember)\\s*\\)',
    );
    // The branch after `if (…)` or `else`: a `{…}` block, or an element
    // up to the next `,`, `;`, `else` or closer.
    int branchEnd(int from) {
      final i = _skipSpace(code, from);
      if (i < code.length && code[i] == '{') return _close(code, i) + 1;
      final end = _expressionEnd(code, i, stopAtColon: false);
      final elseAt = RegExp(r'\belse\b').firstMatch(code.substring(i, end));
      return elseAt == null ? end : i + elseAt.start;
    }

    for (final m in collectionIf.allMatches(code)) {
      final thenEnd = branchEnd(m.end);
      if (m[1] != null) {
        regions.add((start: m.end, end: thenEnd));
        continue;
      }
      final elseAt = RegExp(r'^\s*else\b').firstMatch(code.substring(thenEnd));
      if (elseAt != null) {
        final from = thenEnd + elseAt.end;
        regions.add((start: from, end: branchEnd(from)));
      }
    }
  }
  return regions;
}

/// Why [p] does not hold, or null. An [editor] place must also show for a
/// member. A marker without a quote is matched against code alone; one with
/// a quote is matched with strings kept, but may not start inside a string.
String? _placeProblem(_Place p, {required bool editor}) {
  if (!File(p.path).existsSync()) return '${p.path} does not exist';
  if (RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(p.marker)) {
    return '$p: a bare name proves nothing; name the read or the control';
  }
  if (p.inFn != null && !p.path.endsWith('.dart')) {
    return '$p: "in" is for Dart files';
  }
  final read = _read(p.path);
  final quoted = RegExp('[\'"`]').hasMatch(p.marker);
  final text = quoted ? read.withStrings : read.code;
  final scope = _scopeOf(p);
  if (scope == null) return '$p: no single function named ${p.inFn}';
  final hits = [
    for (final m in _markerPattern(
      p.marker,
    ).allMatches(text.substring(scope.start, scope.end)))
      if (!read.strings.any(
        (s) => scope.start + m.start > s.start && scope.start + m.start < s.end,
      ))
        scope.start + m.start,
  ];
  if (hits.isEmpty) return '$p is not there any more';
  if (!editor) return null;
  final hidden = _memberHiddenRegions(p.path);
  final shown = hits.where(
    (h) => !hidden.any((r) => h >= r.start && h < r.end),
  );
  return shown.isEmpty ? '$p only renders outside a member\'s editor' : null;
}

/// The span [p] is checked in: its function's body, or the whole file.
({int start, int end})? _scopeOf(_Place p) {
  if (p.inFn == null) return (start: 0, end: _read(p.path).code.length);
  try {
    return _bodyOf(p.path, p.inFn!);
  } on StateError {
    return null;
  }
}

/// A member-hiding switch: `showX: member == null` (desktop) or
/// `showX={!member}` (phone).
final _hidingFlag = RegExp(
  r'(\w+)\s*:\s*member\s*==\s*null\s*(?=[,)])|(\w+)=\{\s*!\s*member\s*\}',
);

// ── The test ─────────────────────────────────────────────────────────────

void main() {
  final manifest =
      jsonDecode(File(_manifestPath).readAsStringSync())
          as Map<String, dynamic>;
  final entries = (manifest['fields'] as Map<String, dynamic>).map(
    (k, v) => MapEntry(k, v as Map<String, dynamic>),
  );

  final fields = <String, String>{}; // field key → where it comes from
  final declaredTypes = <String, String>{}; // field key → declared type
  final jsonKeys = <String, String>{}; // field key → the key toJson writes
  for (final m in _models) {
    final f = _fieldsOfModel(m);
    for (final d in f.declared) {
      if (m.containers.contains(d.name)) continue;
      fields['${m.prefix}.${d.name}'] = '${m.className}.${d.name}';
      declaredTypes['${m.prefix}.${d.name}'] = d.type;
    }
    for (final MapEntry(key: name, value: key) in f.keys.entries) {
      if (m.containers.contains(name)) continue;
      fields['${m.prefix}.$name'] = '${m.className}.$name (key "$key")';
      jsonKeys['${m.prefix}.$name'] = key;
    }
  }

  test('the card models are found and read', () {
    for (final m in _models) {
      final f = _fieldsOfModel(m);
      expect(f.declared, isNotEmpty, reason: 'no fields in ${m.className}');
      expect(f.keys, isNotEmpty, reason: 'no keys in ${m.toJson}');
      final names = {...f.declared.map((d) => d.name), ...f.keys.keys};
      expect(
        m.containers.difference(names),
        isEmpty,
        reason: '${m.className} no longer has these containers; drop them',
      );
    }
  });

  test('every card field says how a group member gets it', () {
    final unlisted = [
      for (final MapEntry(:key, :value) in fields.entries)
        if (!entries.containsKey(key)) '$key  ($value)',
    ];
    expect(
      unlisted,
      isEmpty,
      reason:
          'These card fields have no entry in $_manifestPath. A group member '
          "is the group's own copy of a character: give the field a group "
          'editor (the member editor, desktop and phone) and a group reader '
          '(where a group turn reads it per member) and list them; or say '
          'with a reason why the group owns it (groupWide), why nothing '
          'reads it at chat time (notRead), why only a 1:1-only feature '
          'does (soloOnly), why it lives on the library card (origin) or why '
          'it never leaves memory (runtimeOnly).\n${unlisted.join('\n')}',
    );
  });

  test('every entry names a card field that still exists', () {
    final stale = [
      for (final k in entries.keys)
        if (!fields.containsKey(k)) k,
    ];
    expect(stale, isEmpty, reason: 'no such field any more; drop the entry');
  });

  test('every field a type names is enumerated or named opaque', () {
    final modelClasses = <String>{
      for (final f in Directory('lib/models').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          for (final m in RegExp(
            r'^(?:(?:abstract|base|final|interface|mixin|sealed)\s+)*'
            r'class\s+(\w+)',
            multiLine: true,
          ).allMatches(f.readAsStringSync()))
            m[1]!,
    };
    final enumerated = {for (final m in _models) m.className};
    final opaque = (manifest['opaqueTypes'] as Map<String, dynamic>).keys
        .toSet();
    final problems = <String>[];
    final used = <String>{};
    for (final MapEntry(:key, value: type) in declaredTypes.entries) {
      for (final m in RegExp(r'[A-Z]\w*').allMatches(type)) {
        final t = m[0]!;
        if (!modelClasses.contains(t) || enumerated.contains(t)) continue;
        used.add(t);
        if (!opaque.contains(t)) problems.add('$key is a $type');
      }
    }
    for (final t in opaque.difference(used)) {
      problems.add('opaqueTypes.$t: no card field has that type; drop it');
    }
    expect(
      problems,
      isEmpty,
      reason:
          'A field typed with a lib/models class has fields of its own. '
          'Enumerate the class in _models, or name it in opaqueTypes with '
          'why its fields are edited and read only as a whole.\n'
          '${problems.join('\n')}',
    );
  });

  test('the card JSON a member row stores round-trips', () {
    final problems = <String>[];
    for (final m in _models) {
      final f = _fieldsOfModel(m);
      final written = f.keys.keys.toSet();
      if (m.prefix == 'ext') {
        for (final d in f.declared) {
          if (!written.contains(d.name)) {
            problems.add(
              '${m.className}.${d.name} is not in ${m.toJson}: a member row '
              "stores the codec's output, so it never reaches a member",
            );
          }
        }
      }
      final decode = m.decode;
      if (decode == null) continue;
      final path = m.toJsonPath ?? m.path;
      final text = _read(path).withStrings;
      final body = _bodyOf(path, decode);
      final read = StringBuffer(text.substring(body.start, body.end));
      // Top-level helpers the decoder calls (`_workDays(realism)`).
      for (final call in RegExp(
        r'(?<![\w$.])(_\w+)\s*\(',
      ).allMatches(read.toString())) {
        try {
          final h = _bodyOf(path, call[1]!);
          read.write(text.substring(h.start, h.end));
        } on StateError {
          continue;
        }
      }
      for (final MapEntry(key: name, value: key) in f.keys.entries) {
        if (!read.toString().contains("'$key'")) {
          problems.add('${m.className}.$name: $decode never reads "$key"');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every entry gives readers or one reasoned exemption', () {
    final problems = <String>[];
    for (final MapEntry(:key, value: e) in entries.entries) {
      final unknown = e.keys.toSet().difference(_entryKeys);
      if (unknown.isNotEmpty) problems.add('$key: unknown keys $unknown');
      String? reason(String k) => e[k] as String?;
      final exempt = [
        for (final x in _exemptions)
          if (e.containsKey(x)) x,
      ];
      final editor = _places(e['editor']);
      final reader = _places(e['reader']);
      for (final k in [..._exemptions, 'noEditor', 'noPhone']) {
        if (e.containsKey(k) && (reason(k) ?? '').trim().isEmpty) {
          problems.add('$key.$k needs its reason');
        }
      }
      if (exempt.length > 1) problems.add('$key: one exemption, not $exempt');
      if (exempt.isEmpty && reader.isEmpty) {
        problems.add('$key: name where a group reads it, or an exemption');
      }
      if (exempt.isNotEmpty && exempt.single != 'origin' && reader.isNotEmpty) {
        problems.add('$key: ${exempt.single} says no group read; drop reader');
      }
      if (exempt.isEmpty && editor.isEmpty && !e.containsKey('noEditor')) {
        problems.add('$key: a group reads it; name its editor or noEditor');
      }
      if (e.containsKey('noEditor') && editor.isNotEmpty) {
        problems.add('$key: noEditor with editors');
      }
      if (editor.isEmpty) continue;
      final prefix = key.substring(0, key.lastIndexOf('.'));
      final web = editor.any((p) => p.path.startsWith('web_ui/'));
      if (!web && !e.containsKey('noPhone')) {
        problems.add('$key: no phone control; name it, or say why (noPhone)');
      }
      if (web && e.containsKey('noPhone')) {
        problems.add('$key: noPhone with a phone control');
      }
      final relay = _relays[prefix];
      if (web && relay != null) {
        for (final (side, fns) in [('set', relay.set), ('get', relay.get)]) {
          if (!editor.any((p) => fns.contains(p.inFn))) {
            problems.add('$key: name the relay\'s $side side, in one of $fns');
          }
        }
      }
      final save = _desktopSaves[prefix];
      if (save != null &&
          editor.any((p) => p.path.startsWith(_desktopEditor)) &&
          !editor.any((p) => save.contains(p.inFn))) {
        problems.add('$key: name where Save writes it, in one of $save');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every entry names its own field, and a shared place says why', () {
    // A place copied from another field's entry proves nothing about this
    // one: some editor and some reader must name the field itself.
    final problems = <String>[];
    final claims = <String, List<(String, _Place)>>{};
    for (final MapEntry(:key, value: e) in entries.entries) {
      final names = [key.substring(key.lastIndexOf('.') + 1), ?jsonKeys[key]];
      for (final (role, places) in [
        ('editor', _places(e['editor'])),
        ('reader', _places(e['reader'])),
      ]) {
        // The editor that names the field is a member-editor surface; the
        // reader is outside the models, or a hop from a read outside them.
        bool counts(_Place p) => role == 'editor'
            ? _under(p.path, _editorSurfaces)
            : !_under(p.path, _notReaders) ||
                  (p.hop != null && !_under(places.first.path, _notReaders));
        if (places.isNotEmpty &&
            !places.any(
              (p) => counts(p) && names.any((n) => _names(p.marker, n)),
            )) {
          problems.add(
            '$key: no $role marker names ${names.join(' or ')} '
            '${role == 'editor' ? 'on a member editor ($_editorSurfaces)' : 'outside the models and the relay (or as a hop from a read outside them)'}; '
            'point at where this field itself is '
            '${role == 'editor' ? 'set' : 'read'}',
          );
        }
        for (final p in places) {
          (claims[p.identity] ??= []).add((key, p));
          if (p.unknown.isNotEmpty) {
            problems.add('$key $role $p: unknown keys ${p.unknown}');
          }
          for (final r in [p.shared, p.hop]) {
            if (r != null && r.trim().isEmpty) {
              problems.add('$key $role $p: shared and hop need a reason');
            }
          }
          if (p.hop != null && role != 'reader') {
            problems.add('$key $role $p: a hop is a step of a read');
          }
        }
      }
    }
    for (final MapEntry(key: _, value: owners) in claims.entries) {
      final keys = {for (final (k, _) in owners) k};
      final place = owners.first.$2;
      if (keys.length > 1 && owners.any((o) => o.$2.shared == null)) {
        problems.add(
          '$place is claimed by ${keys.join(', ')}; mark it shared with why '
          'one place serves them all, or point each at its own',
        );
      }
      if (keys.length == 1 && owners.every((o) => o.$2.shared != null)) {
        problems.add('$place is marked shared but only ${keys.single} has it');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every named editor and reader still holds', () {
    final problems = <String>[];
    for (final MapEntry(:key, value: e) in entries.entries) {
      for (final p in _places(e['editor'])) {
        if (_placeProblem(p, editor: true) case final why?) {
          problems.add('$key editor: $why');
        }
      }
      final readers = _places(e['reader']);
      for (var i = 0; i < readers.length; i++) {
        final p = readers[i];
        if (_placeProblem(p, editor: false) case final why?) {
          problems.add('$key reader: $why');
        }
        if (p.hop == null) continue;
        // A hop is only a hop if the place before it calls it.
        final fn = p.inFn?.split('.').last;
        final before = i == 0 ? null : readers[i - 1];
        final scope = before == null ? null : _scopeOf(before);
        final calls =
            fn != null &&
            scope != null &&
            RegExp('(?<![\\w\$])${RegExp.escape(fn)}(?![\\w\$])').hasMatch(
              _read(before!.path).code.substring(scope.start, scope.end),
            );
        if (!calls) {
          problems.add(
            '$key reader: hop $p is not called from the place before it',
          );
        }
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'An editor or reader moved, or stopped handling the field. Point '
          "the entry at where a group member's value is edited or read now; "
          'if nothing does, the field went 1:1-only: fix that, not the '
          'entry.\n${problems.join('\n')}',
    );
  });

  test("the member editor's member-mode switches hide only group fields", () {
    final hidden = (manifest['memberHidden'] as Map<String, dynamic>).map(
      (path, flags) => MapEntry(
        path,
        (flags as Map<String, dynamic>).map(
          (f, keys) => MapEntry(f, (keys as List).cast<String>()),
        ),
      ),
    );
    final files = {
      ...hidden.keys,
      for (final e in entries.values)
        for (final p in _places(e['editor'])) p.path,
    };
    final problems = <String>[];
    for (final path in files) {
      if (!File(path).existsSync()) continue;
      final found = {
        for (final m in _hidingFlag.allMatches(_read(path).code)) m[1] ?? m[2]!,
      };
      final listed = hidden[path] ?? const {};
      for (final f in found.difference(listed.keys.toSet())) {
        problems.add(
          '$path: $f hides something from a member; list the fields it '
          'hides under memberHidden',
        );
      }
      for (final f in listed.keys.toSet().difference(found)) {
        problems.add('$path: no member switch $f any more; drop it');
      }
      for (final MapEntry(key: flag, value: keys) in listed.entries) {
        for (final k in keys) {
          final e = entries[k];
          if (e == null) {
            problems.add('$path $flag: no entry $k');
          } else if (_places(e['editor']).isNotEmpty) {
            problems.add(
              '$path $flag hides $k from a member, but $k claims an editor',
            );
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test("the member editors save to the member's row", () {
    final problems = <String>[
      for (final s in manifest['spine'] as List)
        if (_placeProblem(_Place(s as Map<String, dynamic>), editor: false)
            case final why?)
          '${s['why']}: $why',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
