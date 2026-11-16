// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character card's own chat font and colours reach the web chat the way the
// desktop bubble resolves them (UiSettings.getChatFontFamily and the colour
// getters): each message carries the card's half as `look`; a chat theme
// wins over the card; in a group a reply wears its speaker's card and the
// user's lines wear nobody's (bubbleHost). A real ChatService.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../helpers/reprocess_needs_harness.dart';

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

  List<Map> rows() => (facade.state()['messages'] as List).cast<Map>();

  test('1:1: every bubble carries the card font and colours', () async {
    final card = needsCard('Mara');
    card.frontPorchExtensions!
      ..chatFontFamily = 'Lora'
      ..aiBubbleColor = const Color(0xFF224466)
      ..userTextColor = const Color(0xFFFFEEDD);
    final i = await h.oneToOneWithStampedReply(card);
    final reply = rows()[i];
    expect(reply['look'], {
      'font': 'Lora',
      'userText': '#FFEEDD',
      'aiBubble': '#224466',
    });
    final user = rows().lastWhere((r) => r['isUser'] == true);
    expect(user['look'], reply['look']);
  });

  test('a chat theme wins over the card, as on the desktop', () async {
    final card = needsCard('Mara');
    card.frontPorchExtensions!.chatFontFamily = 'Lora';
    final i = await h.oneToOneWithStampedReply(card);
    expect(rows()[i]['look'], isNotNull);
    h.chat.sessionThemeOverrides = ChatThemeOverrides(
      themeId: ChatThemePreset.presets.first.id,
    );
    expect(rows()[i].containsKey('look'), isFalse);
  });

  test('a card with none of the seven sends no look', () async {
    final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
    expect(rows()[i].containsKey('look'), isFalse);
  });

  test('group: a reply wears its speaker card; user lines wear none', () async {
    final (a, b) = await h.groupWithTwoReplies();
    final ayla = h.chat.groupCharacters.firstWhere((c) => c.name == 'Ayla');
    ayla.frontPorchExtensions!
      ..chatFontFamily = 'Lora'
      ..dialogueColor = const Color(0xFFAA3300);
    expect(rows()[a]['look'], {'font': 'Lora', 'dialogue': '#AA3300'});
    expect(rows()[b].containsKey('look'), isFalse);
    for (final r in rows().where((r) => r['isUser'] == true)) {
      expect(r.containsKey('look'), isFalse);
    }
  });
}
