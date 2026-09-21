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

// The visual-source cleaner, and the fact that all three visual surfaces use
// it.
//
// The prompt builder, the chat scene dialogs and the Image Studio source pills
// each carried their own byte-identical copy of this. One copy getting a fix
// and the other two not is how "<think>" fragments and "Auto-imported from
// character card: …" reached a picture in the first place.
//
// It is deliberately NOT utils/think_tags.dart's stripThinkTags — the cases
// below pin the two differences (cut from the LAST open tag, and remove stray
// tags of any shape), so a later de-duplication pass cannot quietly swap in
// the shared helper and change what gets drawn.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

void main() {
  group('stripThinkForVisual', () {
    test('a closed block goes, the prose stays', () {
      expect(
        stripThinkForVisual(
          'She waits.<think>What should I say?</think> Rain.',
        ),
        'She waits. Rain.',
      );
    });

    test('an unclosed tail goes, and the cut is from the LAST open tag', () {
      expect(
        stripThinkForVisual('Porch light.<think>one<think>two, still going'),
        'Porch light.one',
        reason:
            'the visual path cuts at the LAST open tag, so "one" survives and '
            'only its marker is stripped; the shared stripThinkTags would cut '
            'at the first one and lose it',
      );
    });

    test('a stray closer of any shape goes', () {
      expect(stripThinkForVisual('</think>Wet steps.'), 'Wet steps.');
      expect(stripThinkForVisual('<think id="2">Wet steps.'), 'Wet steps.');
    });

    test('runs of whitespace collapse to one space', () {
      expect(stripThinkForVisual('Rain.\n\n\nPorch.'), 'Rain. Porch.');
    });

    test('empty in, empty out', () {
      expect(stripThinkForVisual(''), '');
    });
  });

  group('cleanVisualSourceText', () {
    test('drops the card-import line as well as the reasoning', () {
      expect(
        cleanVisualSourceText(
          'Auto-imported from character card: Flora\n'
          '<think>Describe the porch.</think>A porch at dusk.',
        ),
        'A porch at dusk.',
      );
    });

    test('leaves ordinary prose alone', () {
      expect(
        cleanVisualSourceText('A porch at dusk, one lamp lit.'),
        'A porch at dusk, one lamp lit.',
      );
    });
  });

  test('every visual surface calls the shared cleaner', () {
    // A local copy is the failure mode this whole change removes, so the
    // call sites are part of the contract, not just the helper.
    const callers = {
      'lib/services/image_prompt/image_prompt_builder.dart':
          'stripThinkForVisual',
      'lib/ui/pages/chat_page.scene_dialogs.dart': 'cleanVisualSourceText',
      'lib/ui/image_studio/prompt_workspace.dart': 'cleanVisualSourceText',
    };
    callers.forEach((path, fn) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains(fn),
        isTrue,
        reason: '$path must clean visual source text through $fn',
      );
      expect(
        source.contains("lastIndexOf('<think>')"),
        isFalse,
        reason: '$path grew its own think-strip again',
      );
    });
  });
}
