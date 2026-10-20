// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The eight built-in app themes and the custom-accent fitting. Every theme
// must read: body text, accents and chat defaults clear WCAG AA (4.5:1) on
// the grounds they sit on, High Contrast clears AAA (7:1), and a custom
// accent is always nudged until it reads. Same bars as
// /mnt/project-files/theming/pr5/check_contrast.py, used while tuning.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Porch is today's look, kept exactly. These pairs predate themes and
/// sit just under the bar; they are pinned so they can't get worse, and so
/// a new failing pair in Porch is still caught.
const _porchLegacy = {
  'dark faint on surfaceContainer',
  'dark userText on userBubble',
  'light faint on background',
  'light textSecondary on surface',
  'light faint on surface',
  'light textSecondary on surfaceContainer',
  'light faint on surfaceContainer',
  'light honey on surface',
  'light sage on surface',
  'light userText on userBubble',
  'light dialogue on aiBubble',
};

const _sky = Color(0xFF60A5FA);

List<String> _failures(AppThemeId theme) {
  final hc = theme == AppThemeId.highContrast;
  final body = hc ? 7.0 : 4.5;
  final faint = hc ? 4.5 : 3.0;
  final out = <String>[];
  void need(String mode, String fg, Color f, String bg, Color b, double lo) {
    final r = contrastRatio(f, b);
    if (r < lo) out.add('$mode $fg on $bg');
  }

  for (final (mode, p) in [
    ('dark', theme.palettes.dark),
    ('light', theme.palettes.light),
  ]) {
    final grounds = {
      'background': p.background,
      'surface': p.surface,
      'card': p.card,
      'surfaceContainer': p.surfaceContainer,
      'studioCard': p.studioCard,
    };
    for (final g in grounds.entries) {
      need(mode, 'textPrimary', p.textPrimary, g.key, g.value, 7);
      for (final ink in {
        'textSecondary': p.textSecondary,
        'ink': p.ink,
        'muted': p.muted,
        'studioProse': p.studioProse,
        'studioNarration': p.studioNarration,
      }.entries) {
        need(mode, ink.key, ink.value, g.key, g.value, body);
      }
      need(mode, 'textTertiary', p.textTertiary, g.key, g.value, faint);
      need(mode, 'faint', p.faint, g.key, g.value, faint);
      if (g.key == 'surfaceContainer') continue;
      for (final acc in {
        'amber': p.amber,
        'formAccent': p.formAccent,
        'honey': p.honey,
        'terracotta': p.terracotta,
        'sage': p.sage,
        'studioTeal': p.studioTeal,
        'studioBad': p.studioBad,
      }.entries) {
        need(mode, acc.key, acc.value, g.key, g.value, body);
      }
    }
    need(mode, 'onAccent', p.onAccent, 'amber', p.amber, body);
    need(mode, 'onAccent', p.onAccent, 'formAccent', p.formAccent, body);
    need(mode, 'studioAmberInk', p.studioAmberInk, 'amber', p.amber, body);
    final c = p.chat;
    need(mode, 'userText', c.userText, 'userBubble', c.userBubble, body);
    need(mode, 'aiText', c.aiText, 'aiBubble', c.aiBubble, body);
    need(mode, 'dialogue', c.dialogue, 'aiBubble', c.aiBubble, body);
    need(mode, 'action', c.action, 'aiBubble', c.aiBubble, body);
    final page = p.page;
    for (final ink in {
      'inkStrong': page.inkStrong,
      'ink': page.ink,
      'inkWarm': page.inkWarm,
      'inkMuted': page.inkMuted,
    }.entries) {
      need(mode, 'page.${ink.key}', ink.value, 'paper', page.paper, body);
      need(mode, 'page.${ink.key}', ink.value, 'edge', page.paperEdge, body);
    }
    need(mode, 'page.inkFaint', page.inkFaint, 'paper', page.paper, 3);
  }
  return out;
}

void main() {
  for (final theme in AppThemeId.values) {
    test('${theme.label} reads in both modes', () {
      final fails = _failures(theme).toSet();
      if (theme == AppThemeId.porch) {
        expect(fails.difference(_porchLegacy), isEmpty);
      } else {
        expect(fails, isEmpty);
      }
    });
  }

  test('every theme has its own palettes and a stable key', () {
    final palettes = {for (final t in AppThemeId.values) t.palettes};
    expect(palettes, hasLength(AppThemeId.values.length));
    for (final t in AppThemeId.values) {
      expect(AppThemeId.fromKey(t.key), t);
    }
    expect(AppThemeId.fromKey('no-such-theme'), AppThemeId.porch);
    expect(AppThemeId.fromKey(null), AppThemeId.porch);
  });

  test('Midnight and High Contrast print on a dark reading page', () {
    for (final t in [AppThemeId.midnight, AppThemeId.highContrast]) {
      expect(t.palettes.dark.page.paper.computeLuminance(), lessThan(0.1));
    }
    expect(AppThemeId.porch.palettes.dark.page, BookPageColors.cream);
    expect(AppThemeId.porch.palettes.light.page, BookPageColors.cream);
  });

  test('a custom accent is always fitted until it reads', () {
    final rnd = Random(7);
    for (var i = 0; i < 300; i++) {
      final pick = Color(0xFF000000 | rnd.nextInt(0x1000000));
      for (final theme in AppThemeId.values) {
        final min = theme == AppThemeId.highContrast ? 7.0 : 4.5;
        final fitted = withCustomAccent(theme.palettes, pick, minRatio: min);
        for (final p in [fitted.dark, fitted.light]) {
          for (final g in [p.background, p.surface, p.card, p.studioCard]) {
            expect(
              contrastRatio(p.amber, g),
              greaterThanOrEqualTo(min),
              reason: '${theme.label} ${accentHex(pick)}',
            );
          }
          expect(p.formAccent, p.amber);
          expect(contrastRatio(p.onAccent, p.amber), greaterThanOrEqualTo(4.5));
        }
      }
    }
  });

  test('a readable pick is kept as is and only a faint one is adjusted', () {
    const porch = AppThemePalettes.porch;
    final dark = fitAccent(_sky, porch.dark, dark: true);
    expect(dark.accent, _sky);
    expect(dark.adjusted, isFalse);
    final light = fitAccent(_sky, porch.light, dark: false);
    expect(light.adjusted, isTrue);
    expect(light.accent.computeLuminance(), lessThan(_sky.computeLuminance()));
    expect(customAccentAdjusted(porch, _sky), isTrue);
  });

  test('accent hex round-trips and rejects junk', () {
    const c = Color(0xFF12ABEF);
    expect(accentHex(c), '#12ABEF');
    expect(parseAccentHex('#12ABEF'), c);
    expect(parseAccentHex('12abef'), c);
    for (final junk in [null, '', '#12AB', 'zzzzzz', '#12ABEF00']) {
      expect(parseAccentHex(junk), isNull, reason: '$junk');
    }
  });

  test(
    'palettes have value equality so runtime builds share a cache entry',
    () {
      const pick = Color(0xFFA78BFA);
      final a = withCustomAccent(AppThemePalettes.porch, pick);
      final b = withCustomAccent(AppThemePalettes.porch, pick);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      final themeA = AppTheme.build(palettes: a, brightness: Brightness.dark);
      final themeB = AppTheme.build(palettes: b, brightness: Brightness.dark);
      expect(identical(themeA, themeB), isTrue);
      expect(a == withCustomAccent(AppThemePalettes.porch, _sky), isFalse);
    },
  );
}
