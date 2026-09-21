// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The card keeps its authored "Current Task / Quest" after the editors stopped
// asking for one.
//
// Retiring an authoring surface is the moment a field quietly dies: nothing
// writes it any more, so the next person to read the code sees a value with no
// producer and deletes it. But cards on disk — and cards on The Stoop — still
// carry tasks their authors typed, and the chat now imports them as a starting
// objective on first entry. Delete the field and that import silently finds
// nothing, for every card made before today.
//
// Two halves are pinned here: the card's own JSON (§1) and the web bridge (§2),
// which is the half the parity work just made fragile — the React form no
// longer sends `currentTask`, so an edit-from-web must fall back to the stored
// value instead of overwriting it with a default.
//
// §3 is the structural half, and is honestly a tripwire rather than a
// behaviour test: a real one needs a live ChatService with a database and a
// session, which only integration_test/ can build. Read it as "nobody deleted
// the call", not "the import works".

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§1 the card still carries the task nobody authors any more', () {
    test('current_task survives a full JSON round-trip', () {
      final saved = FrontPorchExtensions(
        currentTask: 'Find the missing artifact',
      );

      final restored = FrontPorchExtensions.fromJson(saved.toJson());

      expect(
        restored.currentTask,
        'Find the missing artifact',
        reason:
            'the field has no editor left, so this round-trip is the only '
            'thing keeping a pre-swap card whole — the chat reads it here to '
            'seed the starting objective',
      );
    });

    test('a card that never had a task reads back empty, not null', () {
      final restored = FrontPorchExtensions.fromJson(
        FrontPorchExtensions().toJson(),
      );

      expect(
        restored.currentTask,
        '',
        reason:
            'empty is the "nothing to import" signal the entry paths test '
            'for; a null here would throw on first chat entry instead',
      );
    });
  });

  group('§2 a web edit must not wipe the stored task', () {
    // The React Realism form stopped rendering — and therefore stopped sending
    // — `currentTask` when Ambitions replaced it. Every save from the web is
    // now a partial payload with respect to this field.
    test('a payload with no currentTask key keeps the base value', () {
      final base = FrontPorchExtensions(currentTask: 'Survive the first day');

      final saved = frontPorchFromFields({
        'realismEnabled': true,
        'ambitions': ['open her own bakery'],
      }, base: base);

      expect(
        saved.currentTask,
        'Survive the first day',
        reason:
            'the web form no longer sends this key; falling back to a '
            'default here would erase an old card\'s quest the first time its '
            'owner edited anything about it from a phone',
      );
      expect(saved.ambitions, ['open her own bakery']);
    });

    test('the bridge still hands the task back out', () {
      final json = frontPorchToJson(
        FrontPorchExtensions(currentTask: 'Guard the north gate'),
      );

      expect(
        json['currentTask'],
        'Guard the north gate',
        reason:
            'the form does not draw it, but /detail must still return it '
            'or the very next save has nothing to send back',
      );
    });
  });
}
