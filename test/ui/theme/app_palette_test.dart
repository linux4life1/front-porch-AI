// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The app's color helpers read the active app theme. Porch (the only theme so
// far) must paint exactly what the hardcoded helpers painted, and any other
// installed palette must reach every helper, including Porch Stories'.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Every helper that follows the app theme, keyed by name.
Map<String, Color> _helpers(BuildContext c) => {
  'backgroundOf': AppColors.backgroundOf(c),
  'surfaceOf': AppColors.surfaceOf(c),
  'cardOf': AppColors.cardOf(c),
  'surfaceContainerOf': AppColors.surfaceContainerOf(c),
  'sunkenSurfaceOf': AppColors.sunkenSurfaceOf(c),
  'deepWellOf': AppColors.deepWellOf(c),
  'insetPanelOf': AppColors.insetPanelOf(c),
  'borderOf': AppColors.borderOf(c),
  'navigationSelectionOf': AppColors.navigationSelectionOf(c),
  'textPrimary': AppColors.textPrimary(c),
  'textSecondary': AppColors.textSecondary(c),
  'textTertiary': AppColors.textTertiary(c),
  'iconPrimary': AppColors.iconPrimary(c),
  'iconSecondary': AppColors.iconSecondary(c),
  'slateInkOf': AppColors.slateInkOf(c),
  'slateMutedOf': AppColors.slateMutedOf(c),
  'slateFaintOf': AppColors.slateFaintOf(c),
  'porchAmberOf': AppColors.porchAmberOf(c),
  'porchHoneyOf': AppColors.porchHoneyOf(c),
  'porchTerracottaOf': AppColors.porchTerracottaOf(c),
  'journalAccentOf': AppColors.journalAccentOf(c),
  'formAccentOf': AppColors.formAccentOf(c),
  'onAccentOf': AppColors.onAccentOf(c),
  'Studio bgOf': StudioColors.bgOf(c),
  'Studio sideOf': StudioColors.sideOf(c),
  'Studio cardOf': StudioColors.cardOf(c),
  'Studio raiseOf': StudioColors.raiseOf(c),
  'Studio lineOf': StudioColors.lineOf(c),
  'Studio lineStrongOf': StudioColors.lineStrongOf(c),
  'Studio inkOf': StudioColors.inkOf(c),
  'Studio mutedOf': StudioColors.mutedOf(c),
  'Studio faintOf': StudioColors.faintOf(c),
  'Studio proseOf': StudioColors.proseOf(c),
  'Studio amberOf': StudioColors.amberOf(c),
  'Studio honeyOf': StudioColors.honeyOf(c),
  'Studio terraOf': StudioColors.terraOf(c),
  'Studio tealOf': StudioColors.tealOf(c),
  'Studio badOf': StudioColors.badOf(c),
  'Studio narrationOf': StudioColors.narrationOf(c),
  'Studio amberInkOf': StudioColors.amberInkOf(c),
};

/// What each helper returned before app themes existed.
Map<String, Color> _porch(Brightness b) {
  final dark = b == Brightness.dark;
  Color pick(Color d, Color l) => dark ? d : l;
  return {
    'backgroundOf': pick(AppColors.background, AppColors.lightBackground),
    'surfaceOf': pick(AppColors.surface, AppColors.lightSurface),
    'cardOf': pick(AppColors.card, AppColors.lightCard),
    'surfaceContainerOf': pick(
      AppColors.surfaceContainer,
      AppColors.surfaceContainerLight,
    ),
    'sunkenSurfaceOf': pick(
      AppColors.sunkenSurface,
      AppColors.sunkenSurfaceLight,
    ),
    'deepWellOf': pick(AppColors.deepWell, AppColors.deepWellLight),
    'insetPanelOf': pick(AppColors.insetPanel, AppColors.insetPanelLight),
    'borderOf': pick(const Color(0xFF3E3328), AppColors.lightBorder),
    'navigationSelectionOf': pick(
      Colors.white.withValues(alpha: 0.08),
      const Color(0xFFF3E0C4),
    ),
    'textPrimary': pick(Colors.white, Colors.black87),
    'textSecondary': pick(Colors.white70, Colors.black54),
    'textTertiary': pick(Colors.white38, Colors.black45),
    'iconPrimary': pick(Colors.white, Colors.black87),
    'iconSecondary': pick(Colors.white70, Colors.black54),
    'slateInkOf': pick(AppColors.slateInk, AppColors.slateInkLight),
    'slateMutedOf': pick(AppColors.slateMuted, AppColors.slateMutedLight),
    'slateFaintOf': pick(AppColors.slateFaint, AppColors.slateFaintLight),
    'porchAmberOf': pick(AppColors.porchAmber, AppColors.porchAmberLight),
    'porchHoneyOf': pick(AppColors.porchHoney, AppColors.porchHoneyLight),
    'porchTerracottaOf': pick(
      AppColors.porchTerracotta,
      AppColors.porchTerracottaLight,
    ),
    'journalAccentOf': pick(
      AppColors.journalAccent,
      AppColors.journalAccentLight,
    ),
    'formAccentOf': AppColors.formMasterAccent,
    'onAccentOf': AppColors.onChaosAccent,
    'Studio bgOf': pick(StudioColors.bg, StudioColors.bgLight),
    'Studio sideOf': pick(StudioColors.side, StudioColors.sideLight),
    'Studio cardOf': pick(StudioColors.card, StudioColors.cardLight),
    'Studio raiseOf': pick(StudioColors.raise, StudioColors.raiseLight),
    'Studio lineOf': pick(StudioColors.line, StudioColors.lineLight),
    'Studio lineStrongOf': pick(
      StudioColors.lineStrong,
      StudioColors.lineStrongLight,
    ),
    'Studio inkOf': pick(StudioColors.ink, StudioColors.inkLight),
    'Studio mutedOf': pick(StudioColors.muted, StudioColors.mutedLight),
    'Studio faintOf': pick(StudioColors.faint, StudioColors.faintLight),
    'Studio proseOf': pick(StudioColors.prose, StudioColors.proseLight),
    'Studio amberOf': pick(StudioColors.amber, StudioColors.amberLight),
    'Studio honeyOf': pick(StudioColors.honey, StudioColors.honeyLight),
    'Studio terraOf': pick(StudioColors.terra, StudioColors.terraLight),
    'Studio tealOf': pick(StudioColors.teal, StudioColors.tealLight),
    'Studio badOf': pick(StudioColors.bad, StudioColors.badLight),
    'Studio narrationOf': pick(StudioColors.narration, StudioColors.mutedLight),
    'Studio amberInkOf': pick(
      StudioColors.amberInk,
      StudioColors.amberInkLight,
    ),
  };
}

/// A palette whose every role is a different, recognisable color.
AppPalette _distinct(int base) {
  var n = base;
  Color next() => Color(0xFF000000 | (n++ * 0x010203));
  return AppPalette(
    background: next(),
    surface: next(),
    card: next(),
    surfaceContainer: next(),
    sunken: next(),
    deepWell: next(),
    insetPanel: next(),
    border: next(),
    navigationSelection: next(),
    textPrimary: next(),
    textSecondary: next(),
    textTertiary: next(),
    ink: next(),
    muted: next(),
    faint: next(),
    amber: next(),
    honey: next(),
    terracotta: next(),
    sage: next(),
    formAccent: next(),
    onAccent: next(),
    studioCard: next(),
    studioRaise: next(),
    studioLineStrong: next(),
    studioProse: next(),
    studioNarration: next(),
    studioAmberInk: next(),
    studioTeal: next(),
    studioBad: next(),
  );
}

Future<Map<String, Color>> _capture(
  WidgetTester tester,
  ThemeData theme, {
  Brightness? localBrightness,
}) async {
  late Map<String, Color> seen;
  final probe = Builder(
    builder: (c) {
      seen = _helpers(c);
      return const SizedBox();
    },
  );
  final home = localBrightness == null
      ? probe
      : Builder(
          builder: (c) => Theme(
            data: Theme.of(c).copyWith(brightness: localBrightness),
            child: probe,
          ),
        );
  await tester.pumpWidget(MaterialApp(theme: theme, home: home));
  return seen;
}

void main() {
  for (final b in Brightness.values) {
    testWidgets('Porch paints exactly the pre-theme colors ($b)', (t) async {
      expect(await _capture(t, AppTheme.build(brightness: b)), _porch(b));
    });

    testWidgets('a theme-less ThemeData falls back to Porch ($b)', (t) async {
      expect(await _capture(t, ThemeData(brightness: b)), _porch(b));
    });
  }

  testWidgets('an installed palette reaches every helper', (t) async {
    final palettes = AppThemePalettes(
      dark: _distinct(1),
      light: _distinct(100),
    );
    final seen = await _capture(
      t,
      AppTheme.build(palettes: palettes, brightness: Brightness.dark),
    );
    final porch = _porch(Brightness.dark);
    final stuck = [
      for (final e in seen.entries)
        if (e.value == porch[e.key]) e.key,
    ];
    expect(stuck, isEmpty, reason: 'helpers still painting Porch');
    // Studio and app helpers that share a role must agree.
    expect(seen['Studio bgOf'], seen['backgroundOf']);
    expect(seen['Studio lineOf'], seen['borderOf']);
    expect(seen['Studio amberOf'], seen['porchAmberOf']);
  });

  testWidgets('a subtree that flips brightness gets the matching palette', (
    t,
  ) async {
    final palettes = AppThemePalettes(
      dark: _distinct(1),
      light: _distinct(100),
    );
    final seen = await _capture(
      t,
      AppTheme.build(palettes: palettes, brightness: Brightness.dark),
      localBrightness: Brightness.light,
    );
    expect(seen['backgroundOf'], palettes.light.background);
    expect(seen['porchAmberOf'], palettes.light.amber);
  });

  test('the built theme is cached per palette and brightness', () {
    final a = AppTheme.build(brightness: Brightness.dark);
    expect(identical(a, AppTheme.build(brightness: Brightness.dark)), isTrue);
    expect(identical(a, AppTheme.build(brightness: Brightness.light)), isFalse);
    expect(a.extension<AppThemePalettes>(), AppThemePalettes.porch);
  });

  test('palettes lerp role by role so a theme switch animates', () {
    final from = AppThemePalettes(dark: _distinct(1), light: _distinct(100));
    final to = AppThemePalettes(dark: _distinct(50), light: _distinct(150));
    final mid = from.lerp(to, 0.5);
    expect(
      mid.dark.surface,
      Color.lerp(from.dark.surface, to.dark.surface, 0.5),
    );
    expect(from.lerp(to, 1).light.studioBad, to.light.studioBad);
  });

  test('UI code reads the form accent and its ink from the theme', () {
    // The bare constants only seed the Porch palette; a screen that reads them
    // directly stays Porch-colored under every other app theme.
    final bare = RegExp(r'AppColors\.(formMasterAccent|onChaosAccent)\b');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.contains(
        '${Platform.pathSeparator}theme${Platform.pathSeparator}',
      )) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final keep =
            lines[i].contains('theme-keep:') ||
            (i > 0 && lines[i - 1].contains('theme-keep:'));
        if (bare.hasMatch(lines[i]) && !keep) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('light-mode status, chip and chat inks clear 4.5:1 on the chip '
      'well', (t) async {
    // Light mode takes deeper tones of the Material accents dark mode uses.
    // They are checked on the chip well over the surface, and on the
    // surface itself, where the status bar and Memory setup draw them.
    late Map<String, Color> inks;
    late Color ground, surface;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light),
        home: Builder(
          builder: (c) {
            surface = AppColors.surfaceOf(c);
            ground = Color.alphaBlend(
              InkColors.chipWellOf(c),
              AppColors.surfaceOf(c),
            );
            inks = {
              'danger': StatusColors.dangerOf(c),
              'warning': StatusColors.warningOf(c),
              'success': StatusColors.successOf(c),
              'info': StatusColors.infoOf(c),
              'hunger': RealismColors.hungerOf(c),
              'bladder': RealismColors.bladderOf(c),
              'energy': RealismColors.energyOf(c),
              'social': RealismColors.socialOf(c),
              'fun': RealismColors.funOf(c),
              'hygiene': RealismColors.hygieneOf(c),
              'comfort': RealismColors.comfortOf(c),
              'other need': RealismColors.otherNeedOf(c),
              'bond down': RealismColors.bondDownOf(c),
              'trust up': RealismColors.trustUpOf(c),
              'lust up': RealismColors.lustUpOf(c),
              'thought': ChatColors.thoughtInkOf(c),
              'director': ChatColors.directorOf(c),
              'memory': ChatColors.memoryOf(c),
              'regen': ChatColors.regenOf(c),
              'continue': ChatColors.continueOf(c),
              'swipe': ChatColors.swipeOf(c),
              'preparing': ChatColors.preparingOf(c),
              'prefilling': ChatColors.prefillingOf(c),
              'thinking': ChatColors.thinkingOf(c),
              'buffering': ChatColors.bufferingOf(c),
              'generating': ChatColors.generatingOf(c),
              'speed': ChatColors.speedOf(c),
              'quote': ChatColors.quoteInkOf(c),
              'narration': ChatColors.narrationInkOf(c),
              'macro': ChatColors.macroInkOf(c),
              'energy bar': RealismColors.energyBarOf(c),
              for (final v in [90, 60, 30, 10, -10, -30, -60, -90])
                'feeling $v': RealismColors.feelingScaleOf(c, v),
              for (final q in ['red', 'orange', 'yellow', 'green', 'blue', 'x'])
                'quant $q': ModelColors.quantOf(c, q),
              'quant purple': ModelColors.purpleOf(c),
              'stoop': NavColors.stoopOf(c),
              'creator': NavColors.creatorOf(c),
              'group chat': NavColors.groupChat,
              'caution': StatusColors.cautionOf(c),
              'progress': StatusColors.progressOf(c),
              'optional': AppColors.optionalAccentOf(c),
            };
            return const SizedBox();
          },
        ),
      ),
    );
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    final faint = [
      for (final g in [ground, surface])
        for (final e in inks.entries)
          if (contrast(e.value, g) < 4.5)
            '${e.key} ${contrast(e.value, g).toStringAsFixed(2)}',
    ];
    expect(faint, isEmpty);
  });
}
