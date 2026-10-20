// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web paints the token maps the desktop resolves. Three things keep the
// two sides honest: every token is a variable the web stylesheets define,
// every colour variable the web defines comes from the desktop (or it would
// stay dark in light mode), and the dark map is the web's own defaults, so
// nothing moves before the desktop speaks. Where the light value copies a
// desktop helper, it is pinned to that helper.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/web/facade/settings/settings.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colour variables that stay put in every theme on purpose.
const _fixed = {
  // The reader's paper book is a prop, as on the desktop. Its per-theme
  // page arrives with the theme picker.
  'story-paper', 'story-paper-edge', 'story-ink', 'story-ink-soft',
  'story-wood',
  // Porch Stories' diff panel is one tone in both modes on the desktop too.
  'studio-diff-del-bg', 'studio-diff-del-fg', 'studio-diff-ins-bg',
  'studio-diff-ins-fg',
};

final _literal = RegExp(
  r'^(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\))$',
  caseSensitive: false,
);

/// `--name: value` colour definitions in the `:root {}` blocks of every web
/// stylesheet.
Map<String, String> _webRootColours() {
  final out = <String, String>{};
  final files = Directory('web_ui/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.css'));
  final block = RegExp(r':root\s*\{([^}]*)\}');
  final decl = RegExp(r'--([a-z0-9-]+)\s*:\s*([^;]+);');
  for (final f in files) {
    final css = f.readAsStringSync().replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    for (final b in block.allMatches(css)) {
      for (final d in decl.allMatches(b.group(1)!)) {
        final value = d.group(2)!.trim();
        if (_literal.hasMatch(value)) out[d.group(1)!] = value;
      }
    }
  }
  return out;
}

/// A CSS colour string as (r, g, b, alpha 0-255).
(int, int, int, int) _rgba(String css) {
  final v = css.trim().toLowerCase();
  if (v.startsWith('#')) {
    var h = v.substring(1);
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    final n = int.parse(h.substring(0, 6), radix: 16);
    final a = h.length == 8 ? int.parse(h.substring(6), radix: 16) : 255;
    return ((n >> 16) & 255, (n >> 8) & 255, n & 255, a);
  }
  final parts = v
      .substring(v.indexOf('(') + 1, v.indexOf(')'))
      .split(',')
      .map((s) => s.trim())
      .toList();
  final a = parts.length > 3 ? (double.parse(parts[3]) * 255).round() : 255;
  return (int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), a);
}

Matcher _sameColour(String expected) => predicate<String>((actual) {
  final (r1, g1, b1, a1) = _rgba(actual);
  final (r2, g2, b2, a2) = _rgba(expected);
  // Fully transparent is transparent whatever its channels say.
  if (a1 == 0 && a2 == 0) return true;
  return r1 == r2 && g1 == g2 && b1 == b2 && (a1 - a2).abs() <= 1;
}, 'the colour $expected');

Future<BuildContext> _context(WidgetTester t, Brightness b) async {
  late BuildContext ctx;
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness: b),
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );
  // A theme change animates; read it once it has landed.
  await t.pumpAndSettle();
  return ctx;
}

/// Tokens that copy a desktop context helper, in both modes.
Map<String, Color> _helpers(BuildContext c) => {
  'on-accent': Theme.of(c).colorScheme.onPrimary,
  'porch-amber': AppColors.porchAmberOf(c),
  'surface-2': AppColors.surfaceContainerOf(c),
  'ok': StatusColors.successOf(c),
  'quote-ink': ChatColors.quoteInkOf(c),
  'narration-ink': ChatColors.narrationInkOf(c),
  'info': ChatColors.bufferingOf(c),
  'need-hunger': RealismColors.hungerOf(c),
  'need-bladder': RealismColors.bladderOf(c),
  'need-energy': RealismColors.energyOf(c),
  'need-social': RealismColors.socialOf(c),
  'need-fun': RealismColors.funOf(c),
  'need-hygiene': RealismColors.hygieneOf(c),
  'need-comfort': RealismColors.comfortOf(c),
  'need-other': RealismColors.otherNeedOf(c),
  'bond-up': RealismColors.bondUpOf(c),
  'bond-down': RealismColors.bondDownOf(c),
  'trust-up': RealismColors.trustUpOf(c),
  'trust-down': RealismColors.trustDownOf(c),
  'lust-up': RealismColors.lustUpOf(c),
  'lust-down': RealismColors.lustDownOf(c),
  'alert': AppColors.alertRedOf(c),
  'bond-high': AppColors.bondHighOf(c),
  'bond-neg': AppColors.bondNegOf(c),
};

/// Light-only twins: the dark web value predates the desktop token.
Map<String, Color> _lightHelpers(BuildContext c) => {
  'danger': StatusColors.dangerOf(c),
  'chip-well': InkColors.chipWellOf(c),
  'sparkle': ChatColors.quoteInkOf(c),
};

void main() {
  final dark = WebThemeTokens.resolve(AppPalette.porchDark, Brightness.dark);
  final light = WebThemeTokens.resolve(AppPalette.porchLight, Brightness.light);
  final web = _webRootColours();

  test('every token is a variable the web stylesheets define', () {
    final unknown = dark.keys.where((k) => !web.containsKey(k)).toList();
    expect(unknown, isEmpty, reason: 'no :root default in web_ui/src');
    expect(light.keys.toSet(), dark.keys.toSet());
  });

  test('every web colour variable comes from the desktop', () {
    final missing = web.keys
        .where((k) => !dark.containsKey(k) && !_fixed.contains(k))
        .toList();
    expect(
      missing,
      isEmpty,
      reason:
          'add these to WebThemeTokens, or derive them in CSS from a token '
          '(color-mix, var())',
    );
  });

  test('the dark map is the web\'s own defaults', () {
    for (final e in dark.entries) {
      expect(e.value, _sameColour(web[e.key]!), reason: '--${e.key}');
    }
  });

  testWidgets('tokens that copy a desktop helper match it', (t) async {
    for (final (b, map) in [
      (Brightness.dark, dark),
      (Brightness.light, light),
    ]) {
      final c = await _context(t, b);
      final pairs = {
        ..._helpers(c),
        if (b == Brightness.light) ..._lightHelpers(c),
      };
      for (final e in pairs.entries) {
        expect(
          map[e.key],
          _sameColour(WebThemeTokens.css(e.value)),
          reason: '--${e.key} in ${b.name}',
        );
      }
    }
  });

  test('the wire carries the mode and both maps', () {
    final w = WebThemeTokens.wire(AppThemePalettes.porch, isDark: false);
    expect(w['mode'], 'light');
    expect(w['dark'], dark);
    expect(w['light'], light);
    expect(light['bg'], '#f8f4ed');
  });

  test('every app theme reaches the web with its own colours', () {
    for (final id in AppThemeId.values) {
      for (final (b, p) in [
        (Brightness.dark, id.palettes.dark),
        (Brightness.light, id.palettes.light),
      ]) {
        final map = WebThemeTokens.resolve(p, b);
        final why = '${id.key} ${b.name}';
        expect(map.keys.toSet(), dark.keys.toSet(), reason: why);
        expect(map['bg'], WebThemeTokens.css(p.background), reason: why);
        expect(map['porch-amber'], WebThemeTokens.css(p.amber), reason: why);
        expect(
          map['user-bubble'],
          WebThemeTokens.css(p.chat.userBubble),
          reason: why,
        );
        expect(
          map['dialogue'],
          WebThemeTokens.css(p.chat.dialogue),
          reason: why,
        );
      }
    }
  });

  test('the wire follows the desktop theme, mode and accent', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final appearance = AppearanceSettings()..initializeBase(prefs, () {});
    appearance.load();
    expect(webThemeWire(appearance)['dark'], dark);

    await appearance.setTheme(AppThemeId.harbor);
    await appearance.setMode(AppThemeMode.light);
    var w = webThemeWire(appearance);
    expect(w['mode'], 'light');
    expect(
      (w['light']! as Map)['bg'],
      WebThemeTokens.css(AppThemeId.harbor.palettes.light.background),
    );

    await appearance.setAccentOverride(const Color(0xFF2E7D32));
    w = webThemeWire(appearance);
    expect(
      (w['light']! as Map)['porch-amber'],
      WebThemeTokens.css(appearance.resolvedPalettes().light.amber),
    );
    expect(
      (w['light']! as Map)['porch-amber'],
      isNot(WebThemeTokens.css(AppThemeId.harbor.palettes.light.amber)),
    );
  });
}
