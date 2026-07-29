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

// Guards the shared reasoning-tag stripper used by TTS sanitize and the
// ONNX emotion classifier input. The orphan-closing-tag case is the one
// that shipped broken (Kokoro spoke the tag); policy per review: strip only
// the tag, never the prose before it.
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

void main() {
  test('paired block is removed, prose kept', () {
    expect(stripThinkTags('<think>reasoning</think>Hello there.'),
        'Hello there.');
  });

  test('unclosed opening tag strips to end (mid-stream text)', () {
    expect(stripThinkTags('<think>unclosed reasoning to end'), '');
    expect(stripThinkTags('Prose first. <think>then reasoning'),
        'Prose first.');
  });

  test('orphan closing tag: only the tag is removed, prose survives', () {
    expect(
      stripThinkTags('</think> The glass of the stern window is cool.'),
      'The glass of the stern window is cool.',
    );
    expect(
      stripThinkTags('Real prose stays.</think>And this too.'),
      'Real prose stays.And this too.',
    );
  });

  test('case-insensitive', () {
    expect(stripThinkTags('<THINK>upper</THINK>Kept.'), 'Kept.');
  });

  test('plain text untouched (modulo trim)', () {
    expect(stripThinkTags('No tags at all.'), 'No tags at all.');
  });

  test('multiple pairs and stray tags in one message', () {
    expect(
      stripThinkTags('<think>a</think>One. <think>b</think>Two.</think>'),
      'One. Two.',
    );
  });

  group('splitMessageForEdit / joinMessageEdit', () {
    test('splits paired think from body without tags in either field', () {
      final parts = splitMessageForEdit(
        '<think>Let me analyze this.</think>\n"Hello," she said.',
      );
      expect(parts.thinking, 'Let me analyze this.');
      expect(parts.body, '"Hello," she said.');
    });

    test('plain message has empty thinking', () {
      final parts = splitMessageForEdit('Just a reply.');
      expect(parts.thinking, isEmpty);
      expect(parts.body, 'Just a reply.');
    });

    test('unclosed think treats rest as thinking', () {
      final parts = splitMessageForEdit('<think>still going');
      expect(parts.thinking, 'still going');
      expect(parts.body, isEmpty);
    });

    test('join with thinking wraps tags; empty thinking is body only', () {
      expect(
        joinMessageEdit(thinking: 'reason', body: 'Body text'),
        '<think>\nreason\n</think>\nBody text',
      );
      expect(joinMessageEdit(thinking: '  ', body: 'Body only'), 'Body only');
      expect(joinMessageEdit(thinking: '', body: ''), '');
    });

    test('round-trip preserves thinking + body', () {
      const raw =
          '<think>\nCareful analysis.\n</think>\n*She waves.* "Hi."';
      final parts = splitMessageForEdit(raw);
      final joined = joinMessageEdit(
        thinking: parts.thinking,
        body: parts.body,
      );
      final again = splitMessageForEdit(joined);
      expect(again.thinking, 'Careful analysis.');
      expect(again.body, '*She waves.* "Hi."');
    });
  });
}
