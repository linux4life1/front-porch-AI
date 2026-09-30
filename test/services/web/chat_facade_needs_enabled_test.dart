// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web facade chips follow the same resolver as desktop
// (/workspace/sow/rn-spec.md item 6): needsReprocessable = resolver != null,
// plus enabledNeeds (List<String>; renamed from enabledNeeds in AMENDMENT 2
// item 3) and needsSpeaker (String). Real ChatFacade
// over a real ChatService; reads the JSON the phone/web client receives.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../helpers/reprocess_needs_harness.dart';

Map<String, dynamic> _chips(ChatFacade f, int index) {
  final msgs = (f.state()['messages'] as List).cast<Map<String, dynamic>>();
  final m = msgs.firstWhere((m) => m['index'] == index);
  return Map<String, dynamic>.from((m['chips'] as Map?) ?? const {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late ChatFacade facade;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    facade = ChatFacade(h.chat, h.repo, null, null, null);
  });
  tearDown(() => h.dispose());

  test('E1 1:1 with Hygiene+Fun off: chips carry enabledNeeds (5, canonical) '
      'and needsSpeaker', () async {
    final i = await h.oneToOneWithStampedReply(
      needsCard('Mara', needsOff: ['hygiene', 'fun']),
    );
    final c = _chips(facade, i);
    expect(c['needsReprocessable'], isTrue);
    expect(c['enabledNeeds'], [
      'hunger',
      'bladder',
      'energy',
      'social',
      'comfort',
    ]);
    expect(c['needsSpeaker'], 'Mara');
  });

  test(
    'E2 group: enabledNeeds/needsSpeaker follow each message\'s sender',
    () async {
      final (a, b) = await h.groupWithTwoReplies();
      final ca = _chips(facade, a);
      final cb = _chips(facade, b);
      expect(ca['needsSpeaker'], 'Ayla');
      expect(ca['enabledNeeds'], [
        'hunger',
        'bladder',
        'energy',
        'fun',
        'hygiene',
        'comfort',
      ]);
      expect(cb['needsSpeaker'], 'Bram');
      expect(cb['enabledNeeds'], kAllNeeds);
    },
  );

  test('E3 every need off on the card: no needsReprocessable, no '
      'enabledNeeds', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    h.chat.activeCharacter!.frontPorchExtensions!.needsOff = List<String>.of(
      kAllNeeds,
    );
    final c = _chips(facade, i);
    expect(c['needsReprocessable'], isNot(true));
    expect(c['enabledNeeds'], isNull);
  });

  test('E4 Needs switched off for the chat: no needsReprocessable', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    await h.chat.setNeedsSimEnabled(false);
    expect(_chips(facade, i)['needsReprocessable'], isNot(true));
  });
}
