// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/lorebook_analysis.dart';
import 'package:front_porch_ai/models/lorebook_codec.dart';

Map<String, dynamic> _fixture(String name) => jsonDecode(
      File('test/fixtures/lorebooks/$name').readAsStringSync(),
    ) as Map<String, dynamic>;

LorebookImportSummary _analyze(String name) {
  final raw = _fixture(name);
  return LorebookImportSummary.analyze(raw, Lorebook.fromJson(raw));
}

void main() {
  group('LorebookImportSummary', () {
    test('ST fixture: format, counts, and feature chips', () {
      final s = _analyze('st_world_info.json');
      expect(s.format, LorebookFormat.fpaiOrSt);
      expect(s.entryCount, 2);
      expect(s.enabledCount, 1); // one entry is disabled
      expect(s.features['conditional triggers'], 1);
      expect(s.features['chance-based'], 1); // probability 75
      expect(s.features['regex keys'], 1);
      expect(s.features['timed'], 1);
      expect(s.features['variety groups'], 1);
      expect(s.features['custom placement'], 1); // position 4
      expect(s.approxTokens, greaterThan(0));
      expect(
        s.warnings.any((w) => w.contains('disabled')),
        isTrue,
      );
    });

    test('NovelAI fixture detected with the right label', () {
      final s = _analyze('novelai.json');
      expect(s.format, LorebookFormat.novelAi);
      expect(s.formatLabel, 'NovelAI lorebook');
      expect(s.entryCount, 2);
    });

    test('Risu fixture: chance feature counted from activationPercent', () {
      final s = _analyze('risu.json');
      expect(s.format, LorebookFormat.risu);
      expect(s.features['chance-based'], 1);
      expect(s.features['always active'], 1);
    });

    test('V2 book-level overrides produce a warning', () {
      final s = _analyze('v2_character_book.json');
      expect(
        s.warnings.any((w) => w.contains('scan/budget settings')),
        isTrue,
      );
    });

    test('empty book warns instead of crashing', () {
      final s = LorebookImportSummary.analyze(
        const {'entries': []},
        Lorebook(entries: []),
      );
      expect(s.entryCount, 0);
      expect(s.warnings.first, contains('No entries'));
    });
  });
}
