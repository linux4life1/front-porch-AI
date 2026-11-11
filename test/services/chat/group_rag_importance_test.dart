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

// "Per-Character Memory Importance" (Group Settings, Memory tab). The slider
// was stored under the member's roster id while retrieval multiplies a row by
// its OWNER'S memory id (the library id), so no row was ever touched: the
// sliders were dead. What retrieval is handed must be keyed by the ids it
// searches.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/group_memory_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockPathProvider('rag_importance');

  late GroupMemoryHarness h;

  setUp(() async {
    h = await GroupMemoryHarness.open();
    await h.seedLongChat();
    final pool = 'group_${GroupMemoryHarness.groupId}';
    for (var at = 0; at + 2 < 70; at += 3) {
      await h.window(pool, 'filler $at', at, matches: false);
    }
    await h.window(GroupMemoryHarness.adaKey, 'ADAONLY window', 3);
    await h.window('mem-bea', 'BEAONLY window', 6);
    await h.openGroup();
    await h.chat.loadSession(GroupMemoryHarness.sessionId);
  });
  tearDown(() => h.close());

  test(
    'a member\'s importance slider reaches the rows retrieval multiplies',
    () async {
      h.chat.setRAGPriorityForGroupCharacter(h.member('Ada'), 0.1);
      await h.say('Ada', 'Ada, remember what you said?');

      final asked = h.memory.asked.last;
      expect(
        asked.priorities?.keys,
        everyElement(isIn(asked.sources)),
        reason:
            'a priority keyed by an id retrieval never searches multiplies '
            'nothing; it must use the same ids the rows carry',
      );
      expect(asked.priorities?[GroupMemoryHarness.adaKey], 0.1);
      expect(
        h.backend.lastChatBody,
        isNot(contains('ADAONLY')),
        reason: 'at 0.1 her own window falls under the memory threshold',
      );

      // The sliders left at neutral change nothing: Bea reads her own window.
      await h.say('Bea', 'Bea, remember what you said?');
      expect(h.backend.lastChatBody, contains('BEAONLY'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
