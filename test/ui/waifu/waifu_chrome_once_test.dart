// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_sit_down_step.dart';

void main() {
  testWidgets('Plan/Build/Yolo chips live only on the sidebar ModeBar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.byKey(const Key('waifu-mode-plan')), findsOneWidget);
    expect(find.byKey(const Key('waifu-mode-build')), findsOneWidget);
    expect(find.byKey(const Key('waifu-mode-yolo')), findsOneWidget);
    expect(find.byKey(const Key('waifu-path-mode-folderJail')), findsOneWidget);
    expect(find.byKey(const Key('waifu-path-mode-wholeDisk')), findsOneWidget);
    // 3 mode chips + 2 Jail/Disk chips. AppBar scope stays a receipt.
    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.byKey(const Key('waifu-appbar-mode')), findsOneWidget);
    expect(find.byKey(const Key('waifu-appbar-scope')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('waifu-appbar-scope')),
        matching: find.byType(ChoiceChip),
      ),
      findsNothing,
    );
    expect(session.pathMode, WaifuPathMode.folderJail);
  });

  testWidgets('MCP consent is Let her use MCP', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    await tester.ensureVisible(find.byKey(const Key('waifu-mcp-opt-in')));
    expect(find.text('Let her use MCP'), findsOneWidget);
    expect(find.text('MCP tools from Settings'), findsNothing);
  });

  testWidgets('sidebar shows used vs max context', (tester) async {
    final session =
        WaifuSession(
            folderRoot: '/tmp/throwaway-waifu',
            coworker: CharacterCard(name: 'Iris'),
          )
          ..tokensUsed = 1200
          ..contextBudget = 8192;
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.byKey(const Key('waifu-context-bar')), findsOneWidget);
    expect(find.text('1200 / 8192'), findsOneWidget);
  });

  testWidgets('consented sit-down skips the honesty re-quiz', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuWizardSitDownStep(
            folderPath: '/tmp/porch',
            coworker: CharacterCard(name: 'Mira'),
            backendLabel: 'remote',
            isLocalBackend: false,
            toolsSupported: true,
            mode: WaifuMode.build,
            pathMode: WaifuPathMode.wholeDisk,
            honestyAccepted: true,
            skipHonestyQuiz: true,
            onModeChanged: (_) {},
            onPathModeChanged: (_) {},
            onHonestyChanged: (_) {},
            onConfirm: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-honesty-checkbox')), findsNothing);
    expect(find.byKey(const Key('waifu-honesty-skipped')), findsOneWidget);
    // Radios stay so a known porch can leave jail. Honesty is the skip.
    expect(find.byKey(const Key('waifu-path-mode-wholeDisk')), findsOneWidget);
    final confirm = find.byKey(const Key('waifu-sit-down-confirm'));
    expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
  });

  test('saved map with pathMode and honesty is porch consent', () {
    expect(
      waifuSkipHonestyQuiz(
        waifuPorchConsentFromMap({
          'folderRoot': '/tmp/porch',
          'pathMode': 'wholeDisk',
          'honestyAccepted': true,
        }),
      ),
      isTrue,
    );
    expect(
      waifuPorchConsentFromMap({
        'folderRoot': '/tmp/porch',
        'pathMode': 'folderJail',
        'honestyAccepted': false,
      }),
      isNull,
    );
    expect(waifuPorchConsentFromMap({'title': 'no folder'}), isNull);
  });

  test(
    'store loadPorchConsent reads pathMode and honesty from a saved porch',
    () async {
      final dir = await Directory.systemTemp.createTemp('waifu_consent_store_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final store = WaifuStore(dir.path);
      const folder = '/tmp/known-porch';
      await store.saveLast(
        WaifuSession(
          folderRoot: folder,
          coworker: CharacterCard(name: 'Iris'),
          pathMode: WaifuPathMode.wholeDisk,
        ),
      );
      final consent = await store.loadPorchConsent(folder);
      expect(waifuSkipHonestyQuiz(consent), isTrue);
      expect(consent!.pathMode, WaifuPathMode.wholeDisk);
      expect(await store.loadPorchConsent('/tmp/unknown-porch'), isNull);
    },
  );
}
