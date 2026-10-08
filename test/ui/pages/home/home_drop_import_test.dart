// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/home_drop_import.dart';

void main() {
  group('planHomeDrop', () {
    test('routes a PNG card into the character import list', () {
      final plan = planHomeDrop([r'C:\cards\Ada.PNG']);
      expect(plan.pngPaths, [r'C:\cards\Ada.PNG']);
      expect(plan.byafPaths, isEmpty);
      expect(plan.rejectedNames, isEmpty);
      expect(plan.hasImportable, isTrue);
      expect(plan.rejectMessage, isNull);
    });

    test('routes a BYAF archive into the backyard import list', () {
      final plan = planHomeDrop(['/tmp/packs/flora.byaf']);
      expect(plan.byafPaths, ['/tmp/packs/flora.byaf']);
      expect(plan.pngPaths, isEmpty);
      expect(plan.hasImportable, isTrue);
    });

    test('routes .porch and .porchpack files into the .porch import list', () {
      final plan = planHomeDrop([
        '/exports/Aria Vale.porch',
        r'C:\exports\Front Porch characters (3).PORCHPACK',
        '/exports/hero.png',
      ]);
      expect(plan.porchPaths, [
        '/exports/Aria Vale.porch',
        r'C:\exports\Front Porch characters (3).PORCHPACK',
      ]);
      expect(plan.pngPaths, ['/exports/hero.png']);
      expect(plan.rejectedNames, isEmpty);
      expect(plan.hasImportable, isTrue);
      expect(plan.rejectMessage, isNull);
    });

    test('a lone .porch drop is importable on its own', () {
      final plan = planHomeDrop(['/exports/Bram Elder.porch']);
      expect(plan.porchPaths, ['/exports/Bram Elder.porch']);
      expect(plan.hasImportable, isTrue);
      expect(plan.isMixed, isFalse);
    });

    test('batches mixed PNG and BYAF drops', () {
      final plan = planHomeDrop([
        '/lib/one.png',
        '/lib/two.BYAF',
        '/lib/three.png',
      ]);
      expect(plan.pngPaths, ['/lib/one.png', '/lib/three.png']);
      expect(plan.byafPaths, ['/lib/two.BYAF']);
      expect(plan.isMixed, isTrue);
    });

    test('rejects JSON and other types with a snackbar line', () {
      final plan = planHomeDrop(['/lib/card.json', '/notes.txt']);
      expect(plan.hasImportable, isFalse);
      expect(plan.rejectedNames, ['card.json', 'notes.txt']);
      expect(
        plan.rejectMessage,
        "Can't import those files — drop PNG character cards, .byaf or "
        '.porch files.',
      );
    });

    test('names a single unsupported file in the snackbar', () {
      final plan = planHomeDrop(['photo.jpg']);
      expect(
        plan.rejectMessage,
        'Can\'t import "photo.jpg" — drop PNG character cards, .byaf or '
        '.porch files.',
      );
    });

    test('imports valid files and still reports skipped junk', () {
      final plan = planHomeDrop(['hero.png', 'readme.md']);
      expect(plan.pngPaths, ['hero.png']);
      expect(plan.rejectedNames, ['readme.md']);
      expect(
        plan.rejectMessage,
        'Skipped readme.md (not a PNG card, .byaf or .porch file).',
      );
    });

    test('empty drop is a no-op', () {
      final plan = planHomeDrop(const []);
      expect(plan.hasImportable, isFalse);
      expect(plan.rejectMessage, isNull);
    });
  });

  group('planHomeDropSources', () {
    test('rejects folders instead of walking them', () {
      final plan = planHomeDropSources(const [
        HomeDropSource(
          label: 'cards',
          path: '/Users/me/cards',
          isDirectory: true,
        ),
        HomeDropSource(label: 'Ada.png', path: '/Users/me/Ada.png'),
      ]);
      expect(plan.pngPaths, ['/Users/me/Ada.png']);
      expect(plan.rejectedNames, ['cards']);
      expect(
        plan.rejectMessage,
        'Skipped cards (not a PNG card, .byaf or .porch file).',
      );
    });

    test('rejects an item with no path', () {
      final plan = planHomeDropSources(const [
        HomeDropSource(label: 'mystery', path: ''),
      ]);
      expect(plan.hasImportable, isFalse);
      expect(plan.rejectedNames, ['mystery']);
    });
  });
}
