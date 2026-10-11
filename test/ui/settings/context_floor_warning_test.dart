// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app never suggests a context below 16,384 tokens (maintainer ruling):
// a typed 2,048 or 4,096 used to be taken with nothing said. The number stays the
// user's, so a smaller one can still be typed, but it is warned about in the
// preset editor's words, and so is a max output that takes up the whole
// context. The real Settings page (see settings_page_harness.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_generation_section.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/settings_page_harness.dart';

void main() {
  Finder floorWarning() => find.byKey(const ValueKey('context-floor-warning'));
  Finder replyWarning() => find.byKey(const ValueKey('context-reply-warning'));

  testWidgets('the Generation tab warns about a 2,048 context, and about a '
      'max output as big as the context', (tester) async {
    await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        await rig.store.backendSettings.setContextSize(2048);
        await rig.store.generationSettings.setMaxLength(2048);
      },
    );
    await openTab(tester, 'Generation');

    await tester.ensureVisible(floorWarning());
    expect(floorWarning(), findsOneWidget);
    expect(replyWarning(), findsOneWidget);
    expect(
      find.descendant(
        of: replyWarning(),
        matching: find.text(
          'Max output tokens (2,048) takes up the whole context (2,048 '
          'tokens), leaving no room for the character or the chat. Lower '
          'it, or raise the context.',
        ),
      ),
      findsOneWidget,
    );
  });

  group('chat settings', () {
    Future<void> show(WidgetTester tester, {required bool hideOutput}) async {
      final storage = FakeStorageService();
      addTearDown(storage.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatSettingsGenerationSection(
                gen: ChatGenerationSettings()
                  ..contextSize = 16384
                  ..maxLength = 16384,
                storage: storage,
                llmProvider: FakeLLMProvider(),
                isRemote: true,
                hideOutputTokenLimits: hideOutput,
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a max output as big as the context is warned about where '
        'Max Output Tokens is shown', (tester) async {
      await show(tester, hideOutput: false);
      expect(replyWarning(), findsOneWidget);
    });

    testWidgets('and not where it is hidden (Waifu Coder)', (tester) async {
      await show(tester, hideOutput: true);
      expect(find.text('Max Output Tokens'), findsNothing);
      expect(replyWarning(), findsNothing);
    });
  });

  test('the reply warning stays quiet while the reply leaves room', () {
    expect(
      koboldReplyFillsContextWarning(context: 16384, maxOutput: 2048),
      isNull,
    );
    expect(
      koboldReplyFillsContextWarning(context: 16384, maxOutput: 16383),
      isNull,
    );
    expect(
      koboldReplyFillsContextWarning(context: 16384, maxOutput: 16384),
      isNotNull,
    );
  });
}
