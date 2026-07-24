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

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/dream_service.dart';

void main() {
  DreamService svc({
    bool enabled = true,
    Future<String?> Function(String prompt)? fire,
  }) => DreamService(
    fireEval: fire ?? (_) async => null,
    isEnabled: () => enabled,
  );

  group('DreamService.checkRollover (session-scoped bookkeeping)', () {
    test('first sight of a session only anchors — never fires', () {
      final s = svc();
      s.checkRollover(sessionId: 'a', dayCount: 7);
      expect(s.pending, isFalse);
    });

    test('a day passing within the same session fires', () {
      final s = svc();
      s.checkRollover(sessionId: 'a', dayCount: 1);
      s.checkRollover(sessionId: 'a', dayCount: 2);
      expect(s.pending, isTrue);
    });

    test('same day never fires; session switch re-anchors silently', () {
      final s = svc();
      s.checkRollover(sessionId: 'a', dayCount: 1);
      s.checkRollover(sessionId: 'a', dayCount: 1);
      expect(s.pending, isFalse);
      // Switching to a session already on day 9 must not fire for days that
      // "passed" while the app was elsewhere.
      s.checkRollover(sessionId: 'b', dayCount: 9);
      expect(s.pending, isFalse);
    });

    test('disabled → never pending, but the marker still advances', () {
      final s = svc(enabled: false);
      s.checkRollover(sessionId: 'a', dayCount: 1);
      s.checkRollover(sessionId: 'a', dayCount: 2);
      expect(s.pending, isFalse);
    });

    test('null session is a no-op', () {
      final s = svc();
      s.checkRollover(sessionId: null, dayCount: 5);
      expect(s.pending, isFalse);
    });

    test('clear() consumes pending', () {
      final s = svc();
      s.checkRollover(sessionId: 'a', dayCount: 1);
      s.checkRollover(sessionId: 'a', dayCount: 2);
      s.clear();
      expect(s.pending, isFalse);
    });
  });

  group('DreamService.generateDream (skip-on-garbage floor)', () {
    const goodDream =
        'I was back on the lighthouse stairs, but they spiraled upward '
        'forever. Someone kept calling my name from the water.';

    test('valid output passes through trimmed', () async {
      final s = svc(fire: (_) async => '  $goodDream  ');
      final out = await s.generateDream(
        characterName: 'Alice',
        memoryFragments: const ['the lighthouse trip'],
        emotion: 'wistful',
        recap: '',
      );
      expect(out, goodDream);
    });

    test('wrapping quotes, code fences, and a leading label are stripped',
        () async {
      for (final raw in [
        '"$goodDream"',
        '```\n$goodDream\n```',
        'Dream: $goodDream',
      ]) {
        final s = svc(fire: (_) async => raw);
        final out = await s.generateDream(
          characterName: 'Alice',
          memoryFragments: const [],
          emotion: '',
          recap: '',
        );
        expect(out, goodDream, reason: 'raw: $raw');
      }
    });

    test('garbage is skipped: null, too short, runaway-long', () async {
      for (final raw in [null, 'ok', 'x' * 800]) {
        final s = svc(fire: (_) async => raw);
        expect(
          await s.generateDream(
            characterName: 'Alice',
            memoryFragments: const [],
            emotion: '',
            recap: '',
          ),
          isNull,
          reason: 'raw: ${raw == null ? 'null' : '${raw.length} chars'}',
        );
      }
    });

    test('prompt contains only the given fragments and forbids invention',
        () async {
      String? captured;
      final s = svc(
        fire: (p) async {
          captured = p;
          return goodDream;
        },
      );
      await s.generateDream(
        characterName: 'Alice',
        memoryFragments: const ['fragment-one', 'fragment-two'],
        fixation: 'the storm',
        emotion: 'anxious',
        recap: 'They argued about the boat.',
        weatherLine: 'A cold, steady rain is falling.',
      );
      expect(captured, contains('fragment-one'));
      expect(captured, contains('fragment-two'));
      expect(captured, contains('the storm'));
      expect(captured, contains('invent no'));
      expect(captured, contains('first person as Alice'));
    });
  });
}
