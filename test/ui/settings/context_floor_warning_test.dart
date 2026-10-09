// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app never suggests a context below 16,384 tokens (maintainer ruling):
// the Advanced tab's Context Window chips offered 512, 2K, 4K and 8K, and a
// typed 2,048 or 4,096 was taken with nothing said. The number stays the
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
  // The row of context chips: the one 32K sits in, before and after.
  Finder contextCard() =>
      find.ancestor(of: find.text('32K'), matching: find.byType(Wrap)).first;
  Finder contextBox() => find.descendant(
    of: find
        .ancestor(of: find.text('Context Window'), matching: find.byType(Row))
        .first,
    matching: find.byType(TextField),
  );
  List<String> chipLabels(WidgetTester tester) => [
    for (final chip in tester.widgetList<ChoiceChip>(
      find.descendant(of: contextCard(), matching: find.byType(ChoiceChip)),
    ))
      (chip.label as Text).data!,
  ];
  Finder floorWarning() => find.byKey(const ValueKey('context-floor-warning'));
  Finder replyWarning() => find.byKey(const ValueKey('context-reply-warning'));

  testWidgets('the Advanced chips start at 16K, and a typed 4,096 is warned '
      'about but kept', (tester) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) => rig.store.backendSettings.setContextSize(16384),
    );
    await openTab(tester, 'Advanced');

    expect(chipLabels(tester), ['16K', '32K', '64K', '128K']);
    expect(floorWarning(), findsNothing);

    await tester.ensureVisible(contextBox());
    await tester.enterText(contextBox(), '4096');
    await settle(tester);

    expect(rig.store.backendSettings.contextSize, 4096, reason: 'the user’s');
    expect(floorWarning(), findsOneWidget);
    expect(
      find.descendant(
        of: floorWarning(),
        matching: find.text(kKoboldContextFloorWords),
      ),
      findsOneWidget,
    );

    await tester.enterText(contextBox(), '16384');
    await settle(tester);
    expect(floorWarning(), findsNothing);
  });

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

  testWidgets('a saved 8,192 is not replaced by a touch on the slider; '
      'picking a chip replaces it', (tester) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) => rig.store.backendSettings.setContextSize(8192),
    );
    await openTab(tester, 'Advanced');
    final slider = find.byWidgetPredicate(
      (w) =>
          w is Slider &&
          w.divisions == kKoboldContextChoices.length - 1 &&
          w.max == kKoboldContextChoices.length - 1,
    );
    expect(slider, findsOneWidget);
    expect(
      tester
          .widgetList<ChoiceChip>(
            find.descendant(
              of: contextCard(),
              matching: find.byType(ChoiceChip),
            ),
          )
          .where((c) => c.selected),
      isEmpty,
      reason: 'no chip says 8,192',
    );

    await tester.ensureVisible(slider);
    await tester.tap(slider, warnIfMissed: false);
    await tester.drag(slider, const Offset(200, 0), warnIfMissed: false);
    await settle(tester);

    expect(rig.store.backendSettings.contextSize, 8192);
    expect(tester.widget<TextField>(contextBox()).controller!.text, '8192');

    await tapVisible(
      tester,
      find.descendant(of: contextCard(), matching: find.text('32K')),
    );
    await settle(tester);
    expect(rig.store.backendSettings.contextSize, 32768);
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
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
