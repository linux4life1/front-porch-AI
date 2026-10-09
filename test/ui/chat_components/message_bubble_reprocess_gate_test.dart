// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Desktop "Manual Reprocess" pill shows only when the resolver is non-null
// (/workspace/sow/rn-spec.md item 5). Real MessageBubble over a REAL
// ChatService (FakeChatService implements ChatService and would never run the
// real resolver). TTS/persona/storage providers are the stock support fakes;
// nothing asserted comes from them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/reprocess_needs_harness.dart';

const _pill = 'Manual Reprocess';

Future<void> _withHarness(
  WidgetTester tester,
  Future<void> Function(ReprocessHarness h) body,
) async {
  final h = ReprocessHarness();
  await tester.runAsync(() => h.boot());
  try {
    await body(h);
  } finally {
    await tester.runAsync(() => h.dispose());
  }
}

Future<void> _pumpLastBubble(WidgetTester tester, ReprocessHarness h) async {
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  final index = h.chat.messages.length - 1;
  final message = h.chat.messages[index];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: h.storage),
            ChangeNotifierProvider<TtsService>.value(value: tts),
            ChangeNotifierProvider<ChatService>.value(value: h.chat),
            ChangeNotifierProvider<UserPersonaService>.value(
              value: FakeUserPersonaService(),
            ),
          ],
          child: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: MessageBubble(
                message: message,
                index: index,
                character: h.chat.activeCharacter!,
                chatService: h.chat,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  testWidgets(
    'D1 control (guard, green on Rawhide by design): 5 of 7 enabled -> pill shown',
    (tester) async {
      await _withHarness(tester, (h) async {
        await tester.runAsync(
          () => h.oneToOneWithStampedReply(
            needsCard('Mara', needsOff: ['hygiene', 'fun']),
          ),
        );
        await _pumpLastBubble(tester, h);
        expect(find.text(_pill), findsOneWidget);
      });
    },
  );

  testWidgets(
    'D2 control (guard, green on Rawhide by design): exactly 1 enabled -> pill shown',
    (tester) async {
      await _withHarness(tester, (h) async {
        await tester.runAsync(
          () => h.oneToOneWithStampedReply(
            needsCard(
              'Mara',
              needsOff: kAllNeeds.where((n) => n != 'hunger').toList(),
            ),
          ),
        );
        await _pumpLastBubble(tester, h);
        expect(find.text(_pill), findsOneWidget);
      });
    },
  );

  // D3/D4 used to expect the pill hidden. Manual Reprocess now also offers
  // Feelings, which Realism (still on in both) keeps on offer, so the pill
  // stays and what these pin is that Needs is no longer offered. D5 pins the
  // hidden pill: Realism off, neither choice.
  testWidgets('D3 zero needs enabled on the card -> Needs not offered, pill '
      'stays for Feelings', (tester) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      );
      h.chat.activeCharacter!.frontPorchExtensions!.needsOff = List<String>.of(
        kAllNeeds,
      );
      await _pumpLastBubble(tester, h);
      expect(h.chat.reprocessNeedsTargetFor(i!), isNull);
      expect(h.chat.reprocessFeelingsTargetFor(i), 'Mara');
      expect(find.text(_pill), findsOneWidget);
    });
  });

  testWidgets('D4 Needs switched off after the reply was stamped -> Needs '
      'not offered, pill stays for Feelings', (tester) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      );
      await tester.runAsync(() => h.chat.setNeedsSimEnabled(false));
      await _pumpLastBubble(tester, h);
      expect(h.chat.reprocessNeedsTargetFor(i!), isNull);
      expect(h.chat.reprocessFeelingsTargetFor(i), 'Mara');
      expect(find.text(_pill), findsOneWidget);
    });
  });

  testWidgets('D5 Realism switched off -> pill hidden', (tester) async {
    await _withHarness(tester, (h) async {
      await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      );
      await tester.runAsync(() => h.chat.setRealismEnabled(false));
      await _pumpLastBubble(tester, h);
      expect(find.text(_pill), findsNothing);
    });
  });
}
