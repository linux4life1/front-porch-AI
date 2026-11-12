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

// The phone's cast route changes the group's rows, and a chat that has the
// group open follows (docs/design/group-editor.md B1).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/group_editor_relay.dart';

import '../../helpers/group_memory_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockPathProvider('cast_relay');

  test(
    'remove and bring back reach the chat that has the group open',
    () async {
      final h = await GroupMemoryHarness.open(withCy: true);
      addTearDown(h.close);
      final groups = GroupChatRepository(h.storage, h.db);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await h.chat.setActiveGroup(
        groups.getById(GroupMemoryHarness.groupId)!,
        groupRepo: groups,
      );
      final relay = GroupEditorRelay(
        groups,
        h.storage,
        h.db,
        h.library,
        h.chat,
      );
      expect(h.chat.groupCharacters.map((c) => c.name), contains('Cy'));

      final after = await relay.cast(GroupMemoryHarness.groupId, {
        'action': 'remove',
        'memberId': 'mem-cy',
      });
      expect(after, isNotNull);
      expect(
        h.chat.groupCharacters.map((c) => c.name),
        isNot(contains('Cy')),
        reason: 'the open chat still had the removed member',
      );
      expect(after!['removedCount'], 1);

      await relay.cast(GroupMemoryHarness.groupId, {'action': 'bringBack'});
      expect(h.chat.groupCharacters.map((c) => c.name), contains('Cy'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
