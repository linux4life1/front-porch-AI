// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:front_porch_ai/database/database.dart';

void main() {
  group('AvatarImage (drift-generated)', () {
    final now = DateTime.now();

    test('creates with all required fields', () {
      final avatar = AvatarImage(
        id: 'test-id-1',
        characterId: 'char-123',
        filename: 'avatar_1.png',
        label: 'casual',
        displayOrder: 0,
        createdAt: now,
      );

      expect(avatar.id, 'test-id-1');
      expect(avatar.characterId, 'char-123');
      expect(avatar.filename, 'avatar_1.png');
      expect(avatar.label, 'casual');
      expect(avatar.displayOrder, 0);
      expect(avatar.createdAt, now);
    });

    test('creates with nullable label', () {
      final avatar = AvatarImage(
        id: 'test-id-2',
        characterId: 'char-123',
        filename: 'avatar_2.png',
        displayOrder: 1,
        createdAt: now,
      );

      expect(avatar.label, isNull);
    });

    test('copyWith creates modified copy', () {
      final original = AvatarImage(
        id: 'test-id-5',
        characterId: 'char-789',
        filename: 'old.png',
        label: 'old label',
        displayOrder: 0,
        createdAt: now,
      );

      final copied = original.copyWith(
        filename: 'new.png',
        label: const drift.Value('new label'),
        displayOrder: 5,
      );

      expect(copied.filename, 'new.png');
      expect(copied.label, 'new label');
      expect(copied.displayOrder, 5);
      expect(copied.id, 'test-id-5');
      expect(copied.characterId, 'char-789');
      expect(copied.createdAt, now);
    });

    test('copyWith with no args returns equivalent', () {
      final original = AvatarImage(
        id: 'test-id-6',
        characterId: 'char-789',
        filename: 'test.png',
        displayOrder: 0,
        createdAt: now,
      );

      final copied = original.copyWith();
      expect(copied.id, original.id);
      expect(copied.characterId, original.characterId);
      expect(copied.filename, original.filename);
      expect(copied.displayOrder, original.displayOrder);
      expect(copied.createdAt, original.createdAt);
    });
  });

  group('AvatarImage — displayOrder edge cases', () {
    test('handles negative displayOrder', () {
      final avatar = AvatarImage(
        id: 'test-id-9',
        characterId: 'char-000',
        filename: 'test.png',
        displayOrder: -1,
        createdAt: DateTime.now(),
      );
      expect(avatar.displayOrder, -1);
    });

    test('handles large displayOrder', () {
      final avatar = AvatarImage(
        id: 'test-id-10',
        characterId: 'char-000',
        filename: 'test.png',
        displayOrder: 999999,
        createdAt: DateTime.now(),
      );
      expect(avatar.displayOrder, 999999);
    });
  });
}
