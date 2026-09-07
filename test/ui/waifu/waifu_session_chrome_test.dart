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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  testWidgets('empty Waifu Coder chrome shows coworker, folder, and composer', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));

    expect(find.text('Mira'), findsOneWidget);
    expect(find.text('throwaway-waifu'), findsOneWidget);
    expect(find.byKey(const Key('waifu-composer')), findsOneWidget);
    expect(find.byKey(const Key('waifu-send')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('waifu-composer')), 'add hello');
    await tester.tap(find.byKey(const Key('waifu-send')));
    await tester.pump();
    expect(find.text('add hello'), findsOneWidget);
    expect(session.transcript, hasLength(1));
    expect(session.transcript.single.isUser, isTrue);
  });

  test('Waifu Coder island does not import ChatService', () {
    const roots = ['lib/services/waifu', 'lib/ui/waifu'];
    for (final root in roots) {
      final dir = Directory(root);
      expect(dir.existsSync(), isTrue, reason: root);
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = File(entity.path).readAsStringSync();
        final importsChat = src
            .split('\n')
            .any(
              (line) =>
                  line.contains('import') && line.contains('chat_service.dart'),
            );
        expect(
          importsChat,
          isFalse,
          reason: '${entity.path} must not import chat_service.dart',
        );
      }
    }
  });
}
