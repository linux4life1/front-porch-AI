// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pins the public resolver the fix adds (/workspace/sow/rn-spec.md item 2):
//   ChatService.reprocessNeedsTargetFor(int index)
//       -> ({String speaker, List<String> enabled})?
// Real ChatService + drift DB. On Rawhide this file does not compile (the
// method does not exist yet); that compile error is its red.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/reprocess_needs_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
  });
  tearDown(() => h.dispose());

  test('1:1 with Hygiene+Fun off: speaker is the active card, 5 enabled in '
      'canonical order', () async {
    final i = await h.oneToOneWithStampedReply(
      needsCard('Mara', needsOff: ['hygiene', 'fun']),
    );
    final t = h.chat.reprocessNeedsTargetFor(i);
    expect(t, isNotNull);
    expect(t!.speaker, 'Mara');
    expect(t.enabled, ['hunger', 'bladder', 'energy', 'social', 'comfort']);
  });

  test('1:1 with all 7 on: all 7 in canonical order', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    expect(h.chat.reprocessNeedsTargetFor(i)?.enabled, kAllNeeds);
  });

  test(
    'zero enabled -> null (and reprocess returns false, no LLM call)',
    () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      h.chat.activeCharacter!.frontPorchExtensions!.needsOff = List<String>.of(
        kAllNeeds,
      );
      expect(h.chat.reprocessNeedsTargetFor(i), isNull);
      expect(await h.chat.manualReprocessNeeds(i, 'crit'), isFalse);
      expect(h.llm.reprocessPrompts, isEmpty);
    },
  );

  test('Needs switched off for the chat -> null', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    await h.chat.setNeedsSimEnabled(false);
    expect(h.chat.reprocessNeedsTargetFor(i), isNull);
  });

  test(
    'not reprocessable today (user message, out of range) -> null',
    () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      final userIdx = h.chat.messages.lastIndexWhere((m) => m.isUser);
      expect(h.chat.reprocessNeedsTargetFor(userIdx), isNull);
      expect(h.chat.reprocessNeedsTargetFor(i + 1), isNull);
      expect(h.chat.reprocessNeedsTargetFor(-1), isNull);
    },
  );

  test('group: each reply resolves to its own sender\'s card', () async {
    final (a, b) = await h.groupWithTwoReplies();
    final ta = h.chat.reprocessNeedsTargetFor(a);
    final tb = h.chat.reprocessNeedsTargetFor(b);
    expect(ta?.speaker, 'Ayla');
    expect(ta?.enabled, [
      'hunger',
      'bladder',
      'energy',
      'fun',
      'hygiene',
      'comfort',
    ]);
    expect(tb?.speaker, 'Bram');
    expect(tb?.enabled, kAllNeeds);
  });
}
