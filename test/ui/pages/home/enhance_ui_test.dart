// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// AI Enhance desktop surfaces: the context-menu entry exists (the menu list
// was extracted to home_card_menu.dart — widget identity moved, so this is
// the interaction guard) and the review body's render/toggle path.
//
// REWORKED 2026-08-13 (maintainer-directed wizard rework): the standalone
// EnhanceReviewPage and showEnhanceOptionsDialog were absorbed into
// EnhanceWizardPage (About → Model → Chat → Interview → Review → Chats).
// The old review-page assertions were not weakened — they moved onto
// EnhanceReviewBody, the same widget the wizard's Review step mounts; the
// options checklist's defaults + short-chat warning are now pinned by
// enhance_wizard_test.dart at the Interview step, and "Discard writes
// nothing" is inherent (the body has no save button of its own — only the
// wizard nav can trigger save()).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chat_grounding.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_review_body.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('characterCardMenuItems', () {
    testWidgets('contains AI Enhance between Edit and Avatar Gallery', (
      tester,
    ) async {
      late List<PopupMenuItem<String>> items;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              items = characterCardMenuItems(context, inFolder: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final values = items.map((i) => i.value).toList();
      expect(values, contains('ai_enhance'));
      expect(
        values.indexOf('ai_enhance'),
        values.indexOf('edit') + 1,
        reason: 'AI Enhance sits directly after Edit Character',
      );
      expect(values, isNot(contains('remove_folder')));

      // Full parity with the pre-extraction menu (plus the new entries).
      expect(values, [
        'new_chat', 'chat_history', 'edit', 'ai_enhance', 'avatar_gallery',
        'duplicate', 'use_as_persona', 'export', 'export_json', //
        'move_folder', 'delete',
      ]);
    });

    testWidgets('inFolder adds remove_folder', (tester) async {
      late List<PopupMenuItem<String>> items;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              items = characterCardMenuItems(context, inFolder: true);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(items.map((i) => i.value), contains('remove_folder'));
    });

    testWidgets('group menu puts Chat History after Start New Chat', (
      tester,
    ) async {
      late List<PopupMenuItem<String>> items;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              items = groupCardMenuItems(context, inFolder: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final values = items.map((i) => i.value).toList();
      expect(values.indexOf('chat_history'), values.indexOf('new_chat') + 1);
      expect(values, isNot(contains('remove_folder')));
    });
  });

  group('EnhanceReviewBody', () {
    final original = CharacterCard(
      name: 'Nina',
      description: 'Old description',
      personality: 'Old personality',
      mesExample: 'Old example',
    );
    final enhanced = CharacterCard(
      name: 'Nina',
      description: 'New shiny description',
      personality: 'New shiny personality',
      mesExample: 'New shiny example',
    );

    testWidgets('shows old vs new for SELECTED fields only; unticking '
        'disables the editor', (tester) async {
      await tester.pumpWidget(
        _app(
          EnhanceReviewBody(
            original: original,
            enhanced: enhanced,
            selection: const EnhanceSelection(
              description: true,
              personality: false,
              exampleDialogue: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Old description'), findsOneWidget);
      expect(find.text('New shiny description'), findsOneWidget);
      expect(find.text('Old example'), findsOneWidget);
      // Personality was NOT selected → no section at all.
      expect(find.text('Old personality'), findsNothing);
      expect(find.text('New shiny personality'), findsNothing);

      // Unticking a field disables its editor.
      final firstSwitch = find.byType(Switch).first;
      await tester.tap(firstSwitch);
      await tester.pumpAndSettle();
      final descField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'New shiny description'),
      );
      expect(descField.enabled, isFalse);
    });
  });
}
