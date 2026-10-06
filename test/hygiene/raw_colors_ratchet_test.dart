// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Colours go through AppColors. lib/ui/theme/ owns the palette; anywhere else
// in UI code a raw colour ignores light mode and the warm-porch palette. CI's
// theme-lint stops only new Colors.blueAccent lines; this counts every raw
// form: Colors.<name>, Color(0x…) (split across lines or not),
// Color.fromARGB / fromRGBO / from, CupertinoColors, HSLColor / HSVColor.
//
// UI code is lib/ui/** and the startup screens in lib/main*.dart. Colours in
// lib/models, lib/utils and lib/services are data (saved theme presets,
// persona palettes), not chrome.
//
// Allowed without a marker:
//   * Colors.transparent. It paints nothing, so it cannot clash with the
//     palette or vanish in light mode, and AppColors has no token for it.
//   * Colors.black / blackNN, alpha or not, as a shadow or a modal barrier:
//     inside BoxShadow( or Shadow(, or as shadowColor, barrierColor and the
//     scrim colours. A shadow darkens in both themes, AppColors has no shadow
//     token, and the latest approved UI (#384, the lore export dialogs) uses
//     exactly this.
// Not allowed: Colors.white / black with an alpha anywhere else.
// AppColors.hairlineOf(context, alpha) replaced those in the approved preset
// editor (#359), because white-on-dark vanishes on light paper.
//
// A deliberate status or data hue carries `// theme-keep: <reason>`, the
// marker theme-lint already honours; the comment must open with it. It covers
// the colour on its own line (a colour split across lines counts as on each),
// or, alone on a line, the single line directly below it. Never a statement,
// never a body: a palette is marked line by line, or moves into
// lib/ui/theme/. When dart format moves a long trailing marker onto a closing
// `),` line, put the marker alone on the line above the colour instead.
//
// When this guard landed UI code had well over a thousand raw colours, so it
// is a ratchet over test/baselines/raw_colors.json (file -> count). A file may
// never go above its count; a file not listed must have none. Converting a
// colour fails nothing. To lock the progress in, run this test with
// FPAI_TIGHTEN_BASELINES=1: it lowers the counts and can never raise them.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _baselinePath = 'test/baselines/raw_colors.json';
const _palettePath = 'lib/ui/theme/app_colors.dart';

final _rawColour = RegExp(
  r'\bColors\s*\.\s*([A-Za-z_]\w*)'
  r'|\bCupertinoColors\s*\.\s*\w+'
  r'|\bColor\s*(?:\.\s*new\s*)?\(\s*(?:0[xX][0-9A-Fa-f]+|\d+)'
  r'|\bColor\s*\.\s*(?:fromARGB|fromRGBO|from)\s*\('
  r'|\b(?:HSLColor\s*\.\s*fromAHSL|HSVColor\s*\.\s*fromAHSV)\s*\(',
);
final _shade = RegExp(r'^black\d*$');
const _shadowCalls = {'BoxShadow', 'Shadow'};
const _barrierArguments = {
  'shadowColor',
  'barrierColor',
  'modalBarrierColor',
  'scrimColor',
  'drawerScrimColor',
};

bool _isUiCode(String path) =>
    !path.endsWith('.g.dart') &&
    ((path.startsWith('lib/ui/') && !path.startsWith('lib/ui/theme/')) ||
        RegExp(r'^lib/main(\.\w+)?\.dart$').hasMatch(path));

List<RatchetHit> _rawColours(DartSource source) {
  final kept = source.markedLines('theme-keep:');
  return source.hits(
    _rawColour,
    allow: (m) {
      final name = m.group(1);
      if (name == 'transparent') return true;
      if (name != null &&
          _shade.hasMatch(name) &&
          (_shadowCalls.contains(source.enclosingCall(m.start)) ||
              _barrierArguments.contains(source.argumentLabel(m.start)))) {
        return true;
      }
      final last = source.lineOf(m.end - 1) + 1;
      for (var line = source.lineOf(m.start) + 1; line <= last; line++) {
        if (kept.contains(line)) return true;
      }
      return false;
    },
  );
}

Map<String, List<RatchetHit>> _census() => {
  for (final path in dartFiles('lib').where(_isUiCode))
    path: _rawColours(DartSource.read(path)),
}..removeWhere((_, hits) => hits.isEmpty);

/// AppColors' hex constants by name, and the names with an `*Of(context)`
/// pair, read from the palette so the advice never goes stale.
final ({Map<String, int> hex, Set<String> pairs}) _palette = () {
  final code = DartSource.read(_palettePath).code;
  return (
    hex: {
      for (final m in RegExp(
        r'static\s+const\s+Color\s+(\w+)\s*=\s*Color\(\s*0[xX]([0-9A-Fa-f]{8})',
      ).allMatches(code))
        m[1]!: int.parse(m[2]!, radix: 16),
    },
    pairs: {
      for (final m in RegExp(r'static\s+Color\s+(\w+)Of\(').allMatches(code))
        m[1]!,
    },
  );
}();

String _token(String name) {
  final base = name.endsWith('Light')
      ? name.substring(0, name.length - 5)
      : name;
  return _palette.pairs.contains(base)
      ? 'AppColors.${base}Of(context)'
      : 'AppColors.$name';
}

/// The AppColors entry nearest to a `Color(0x…)` literal, by channel.
String _closest(int value) {
  int gap(int other) => [0, 8, 16, 24]
      .map((s) => ((value >> s) & 0xFF) - ((other >> s) & 0xFF))
      .fold(0, (sum, d) => sum + d * d);
  final best = _palette.hex.entries.reduce(
    (a, b) => gap(a.value) <= gap(b.value) ? a : b,
  );
  return gap(best.value) == 0
      ? 'this is ${_token(best.key)}'
      : 'closest palette entry: ${_token(best.key)}';
}

String _advice(RatchetHit hit) {
  final hex = RegExp(r'0[xX]([0-9A-Fa-f]{8})$').firstMatch(hit.match);
  if (hex != null && _palette.hex.isNotEmpty) {
    return _closest(int.parse(hex[1]!, radix: 16));
  }
  if (RegExp(r'^Colors\.(white|black)\d*$').hasMatch(hit.match)) {
    return 'AppColors.textPrimary / textSecondary / textTertiary(context) for '
        'text and icons, AppColors.hairlineOf(context, alpha) for a faint '
        'line or fill';
  }
  return 'the AppColors token for what it means: AppColors.porchAmberOf'
      '(context) or formMasterAccent for an accent, negativeAccentOf(context) '
      'for an error';
}

void main() {
  test('no new raw colours in UI code: a file stays within its baseline, a '
      'new one has none', () {
    final baseline = readBaseline(_baselinePath);
    final census = _census();
    tightenBaselineIfAsked(_baselinePath, baseline, census);
    final problems = ratchetProblems(
      baseline: baseline,
      census: census,
      baselinePath: _baselinePath,
      noun: 'raw colours',
      advice: _advice,
      fix:
          'Use AppColors.<closest> (its *Of(context) pair where it has one, '
          'so light mode works). If the colour is a deliberate status or data '
          'hue and not chrome, end its line with // theme-keep: <reason>, or '
          'put that comment alone on the line directly above it.',
    );
    if (problems.isNotEmpty) fail(problems.join('\n\n'));
  });

  test('the pattern sees every literal in the palette, split or not', () {
    // AppColors is exempt from the census, which makes it a fixed sample: a
    // pattern that missed a form would miss it here too.
    final palette = DartSource.read(_palettePath);
    final hits = palette.hits(_rawColour);
    final missed = [
      for (final m in RegExp(r'0[xX][0-9A-Fa-f]{8}').allMatches(palette.code))
        if (!hits.any(
          (h) =>
              h.line <= palette.lineOf(m.start) + 1 &&
              palette.lineOf(m.start) + 1 <= h.lastLine,
        ))
          '$_palettePath:${palette.lineOf(m.start) + 1}',
    ];
    expect(missed, isEmpty);
    expect(_palette.hex, isNotEmpty);
  });

  test('a marker covers its own line or the one below it, nothing wider; '
      'the allowances stay narrow', () {
    final source = DartSource('layouts.dart', _layouts);
    final counted = _rawColours(source).map((h) => h.line).toList();
    // Each fixture line marked `// counted` holds exactly one raw colour the
    // guard must count; no other line may be counted.
    final expected = [
      for (final (i, line) in _layouts.split('\n').indexed)
        if (line.contains('// counted')) i + 1,
    ];
    expect(counted, expected);
  });
}

const _layouts = r'''
// Kept: a marker on the colour's own line.
final ready = Icon(Icons.check, color: Colors.green); // theme-keep: ready dot

// Kept: a marker on the line where a split colour ends.
final engine = Icon(
  Icons.check,
  color: Colors
      .green, // theme-keep: engine-ready status
);

// Kept: a marker alone on a line covers the single line below it.
// theme-keep: rating star
const star = Color(0xFFFFC107);

// Kept: an inline block marker covers its whole line.
Color flag(bool on) => on ? Colors.green /* theme-keep: on status */ : Colors.grey;

// Counted: a marker on a return's `);` covers that line, not the statement.
Widget badge() {
  return Column(
    children: [
      Container(color: Colors.purple), // counted
      Icon(Icons.star, color: Colors.yellow), // counted
    ],
  ); // theme-keep: badge colours
}

// Counted: a marker above a palette covers its first line only.
// theme-keep: legend hues
const palette = <String, Color>{
  'System Prompt': Color(0xFF3B82F6), // counted
  'Lorebook': Color(0xFF8B5CF6), // counted
};

// Counted: a marker above an arrow function covers its first line only.
// theme-keep: mood ring
Color mood(String emotion) => emotion == 'joy'
    ? Colors.amber // counted
    : Colors.blueGrey; // counted

// Counted: a marker above a closure argument covers its first line only.
final sheet = Builder(
  // theme-keep: sheet colours
  builder: (context) {
    return ColoredBox(color: Colors.teal); // counted
  },
);

// Counted: the line below a marker is the rest of its own comment.
// theme-keep: voice-gender dot, a fixed
// pink/cyan pairing
const female = Colors.pinkAccent; // counted

// Counted: a blank line between the marker and the colour.
// theme-keep: too far away

const far = Color(0xFF111111); // counted

// Counted: prose that names the marker (theme-keep: legend) is not one.
const prose = Colors.teal; // counted

final misc = [
  Text('https://example.com // Colors.red', style: TextStyle(color: Colors.amber)), // counted
  const ColoredBox(color: Colors.transparent),
  DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5), // counted
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
    ),
  ),
  Container(color: Colors.white.withValues(alpha: 0.1)), // counted
  Container(color: Color.fromARGB(255, 1, 2, 3)), // counted
  Container(color: CupertinoColors.systemBlue), // counted
  Container(color: const Color.fromRGBO(1, 2, 3, 1)), // counted
  Container(color: Colors.black26), // counted
  Icon(
    Icons.check,
    color: Colors // counted
        .green,
  ),
  Container(
    color: const Color( // counted
      0xFF000000,
    ),
  ),
];

Future<void> dim(BuildContext context) => showDialog(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => const SizedBox(),
);
''';
