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
// marker theme-lint already honours; the comment must open with it. At the
// end of a line it covers the argument, list item or statement that line
// finishes, so it still works after dart format wraps the line; on a line of
// its own it covers the one that starts below it. It never covers a whole
// function or class: mark the lines inside, or move a palette into
// lib/ui/theme/.
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
  final kept = source.markedRanges('theme-keep:');
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
      return kept.any((r) => r.$1 <= m.start && m.start <= r.$2);
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
          'hue and not chrome, end the line with // theme-keep: <reason>.',
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

  test('a marker survives dart format; the allowances stay narrow', () {
    final source = DartSource('layouts.dart', _layouts);
    final counted = _rawColours(source).map((h) => h.line).toList();
    expect(counted, [15, 32, 46, 51, 60, 61, 62, 66, 79, 83, 87, 91, 103, 106]);
  });
}

// Lines 1-80 are dart format's own output for marked lines. The rest are
// split forms the tree has, and colours the allowances must not swallow.
const _layouts = r'''
Widget build(BuildContext context) {
  final shadows = [
    [
      [
        f(
          f(f(f(Colors.black, null, null), null, null)),
        ), // theme-keep: drop shadow under the dragged cards
        f(
          Colors.green,
          f(Colors.green, f(Colors.green)),
        ), // theme-keep: a reason that is long enough
        f(
          f(f(const Color(0xFF9FD49F), const Color(0xFF3F7A46))),
        ), // theme-keep: legend
        Colors.red,
      ],
    ],
  ];
  final independent = AppColors.resolve(
    context,
    const Color(0xFF9FD49F),
    const Color(0xFF3F7A46),
  ); // theme-keep: dependency legend
  // theme-keep: data-viz legend hues
  // (one per section, shared with the web modal)
  const palette = <String, Color>{
    'System Prompt': Color(0xFF3B82F6),
    'Lorebook': Color(0xFF8B5CF6),
  };
  // theme-keep: a blank line ends the comment block's reach

  const unmarked = [Color(0xFF111111)];
  return Column(
    children: [
      Icon(
        Icons.check_circle,
        color: Colors.green,
        size: 16,
      ), // theme-keep: engine-ready status, not chrome
      Icon(
        Icons.circle,
        color: on ? Colors.green /* theme-keep: on status */ : Colors.grey,
      ),
      Text(
        'see https://example.com // Colors.red',
        style: TextStyle(color: Colors.amber),
      ),
      Container(color: Colors.transparent),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      Container(color: Colors.white.withValues(alpha: 0.1)),
      Container(color: Color.fromARGB(255, 1, 2, 3)),
      Container(color: CupertinoColors.systemBlue),
      Container(
        color: const Color(0xFF1D9BF0),
      ), // theme-keep: hub verification blue, a long reason that wraps
      Container(color: const Color.fromRGBO(1, 2, 3, 1)),
    ],
  );
}

Widget flag(bool on) {
  return Column(
    children: [
      Icon(
        Icons.circle,
        color: on
            ? Colors
                  .green // theme-keep: on status
            : Colors.grey,
      ),
      Icon(
        Icons.check,
        color: Colors
            .green,
      ),
      Container(
        color: const Color(
          0xFF000000,
        ),
      ),
      Container(color: Colors.black26),
    ],
  );
}

Future<void> dim(BuildContext context) => showDialog(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => const SizedBox(),
);

// Prose that names the marker (theme-keep: legend) vouches for nothing.
Color legend(String emotion) => Colors.teal;
// theme-keep: a whole function is more than one marker can vouch for
Color mood(String emotion) {
  return Colors.indigo;
}
''';
