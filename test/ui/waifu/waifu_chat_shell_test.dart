// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_shell_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  WaifuSession session() => WaifuSession(
    folderRoot: root.path,
    coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
  );

  testWidgets(
    'sidebar is portrait, Main Settings, harness, MCP — not realism',
    (tester) async {
      final s = session();
      final harness = WaifuHarness(
        session: s,
        llm: ScriptedWaifuLlm.repeat(
          const LlmToolResponse(calls: [], text: 'Hmph.'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WaifuPage(session: s, harness: harness),
        ),
      );

      expect(find.byKey(const Key('waifu-sidebar')), findsOneWidget);
      expect(find.byKey(const Key('waifu-main-settings')), findsOneWidget);
      expect(find.text('Main Settings'), findsOneWidget);
      expect(find.text('Harness'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('MCP'),
        80,
        scrollable: find.descendant(
          of: find.byKey(const Key('waifu-sidebar')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('MCP'), findsOneWidget);
      expect(find.text('Character State'), findsNothing);
      expect(find.text('Journal'), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('Regenerate'), findsNothing);

      await tester.tap(find.byKey(const Key('waifu-main-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Chat Settings'), findsOneWidget);
      expect(find.text('Model Settings'), findsOneWidget);
      expect(find.text('UI Settings'), findsOneWidget);
    },
  );
}
