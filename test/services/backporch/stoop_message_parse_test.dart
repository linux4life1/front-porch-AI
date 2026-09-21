// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Inbox Notifications only shows kind == SYSTEM. A renamed field (type,
// snake_case, text vs body) makes every notice look like an empty card.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backporch/stoop_message.dart';

void main() {
  group('StoopMessage.fromJson', () {
    test('canonical camelCase SYSTEM notice', () {
      final m = StoopMessage.fromJson({
        'id': '1',
        'fromMod': true,
        'kind': 'SYSTEM',
        'body': 'Your card is approved.',
        'character': {'id': 'c', 'name': 'Zinnia'},
        'createdAt': '2026-09-12T00:00:00.000Z',
      });
      expect(m.isSystem, isTrue);
      expect(m.body, 'Your card is approved.');
      expect(m.character?.name, 'Zinnia');
    });

    test('snake_case keys and type instead of kind', () {
      final m = StoopMessage.fromJson({
        'id': '1',
        'from_mod': true,
        'type': 'SYSTEM',
        'text': 'Your card is approved.',
        'character': {'id': 'c', 'name': 'Zinnia'},
        'created_at': '2026-09-12T00:00:00.000Z',
      });
      expect(m.isSystem, isTrue);
      expect(m.body, 'Your card is approved.');
      expect(m.fromMod, isTrue);
    });

    test('kind is case-insensitive; body can live under message', () {
      final m = StoopMessage.fromJson({
        'id': '1',
        'fromMod': true,
        'kind': 'system',
        'message': 'Needs changes before we can list it.',
        'createdAt': '2026-09-12T00:00:00.000Z',
      });
      expect(m.isSystem, isTrue);
      expect(m.body, 'Needs changes before we can list it.');
    });

    test('isSystem flag without a kind string still files as a notice', () {
      final m = StoopMessage.fromJson({
        'id': '1',
        'fromMod': true,
        'isSystem': true,
        'content': 'Your card wasn’t approved.',
        'createdAt': '2026-09-12T00:00:00.000Z',
      });
      expect(m.isSystem, isTrue);
      expect(m.body, contains('wasn’t approved'));
    });
  });
}
