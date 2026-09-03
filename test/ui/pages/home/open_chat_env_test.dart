// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/pages/home/open_chat_env.dart';

void main() {
  CharacterCard card(String name) => CharacterCard(name: name);

  test('OPEN_CHAT omit/default is a no-op', () {
    expect(OpenChatEnv.name, isEmpty);
    expect(OpenChatEnv.enabled, isFalse);
    expect(
      OpenChatEnv.findOneToOneCard([card('Flora')], name: OpenChatEnv.name),
      isNull,
    );
  });

  test('exact 1:1 name match is case-sensitive and not a substring', () {
    final flora = card('Flora');
    final misty = card('Misty Flora');
    final cards = [misty, flora, card('flora')];
    expect(OpenChatEnv.findOneToOneCard(cards, name: 'Flora'), same(flora));
    expect(
      OpenChatEnv.findOneToOneCard(cards, name: 'Misty Flora'),
      same(misty),
    );
    expect(
      OpenChatEnv.findOneToOneCard(cards, name: 'flora'),
      isNot(same(flora)),
    );
    expect(OpenChatEnv.findOneToOneCard(cards, name: 'Flo'), isNull);
  });

  test('most recent session is first id, never __new__', () {
    expect(OpenChatEnv.mostRecentSessionId(const []), isNull);
    expect(
      OpenChatEnv.mostRecentSessionId([
        {'id': 'newer'},
        {'id': 'older'},
      ]),
      'newer',
    );
    expect(
      OpenChatEnv.mostRecentSessionId([
        {'id': '__new__'},
        {'id': 'older'},
      ]),
      isNull,
    );
  });
}
