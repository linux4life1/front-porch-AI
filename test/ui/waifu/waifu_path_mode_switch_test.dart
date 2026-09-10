// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_sit_down_step.dart';

void main() {
  testWidgets('consented jail still shows Disk; picking it reopens honesty', (
    tester,
  ) async {
    var pathMode = WaifuPathMode.folderJail;
    var honesty = true;
    var skip = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return WaifuWizardSitDownStep(
                folderPath: '/tmp/porch',
                coworker: CharacterCard(name: 'Mira'),
                backendLabel: 'remote',
                isLocalBackend: false,
                toolsSupported: true,
                mode: WaifuMode.build,
                pathMode: pathMode,
                honestyAccepted: honesty,
                skipHonestyQuiz: skip,
                onModeChanged: (_) {},
                onPathModeChanged: (scope) => setState(() {
                  pathMode = scope;
                  skip = waifuHideHonestyForScope(
                    consent: const WaifuPorchConsent(
                      pathMode: WaifuPathMode.folderJail,
                      honestyAccepted: true,
                    ),
                    pathMode: scope,
                  );
                  honesty = skip;
                }),
                onHonestyChanged: (v) => setState(() => honesty = v),
                onConfirm: () {},
              );
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-path-mode-wholeDisk')), findsOneWidget);
    expect(find.byKey(const Key('waifu-honesty-skipped')), findsOneWidget);
    expect(find.byKey(const Key('waifu-honesty-checkbox')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('waifu-path-mode-wholeDisk')),
      300,
    );
    await tester.tap(find.byKey(const Key('waifu-path-mode-wholeDisk')));
    await tester.pump();
    expect(pathMode, WaifuPathMode.wholeDisk);
    await tester.scrollUntilVisible(
      find.byKey(const Key('waifu-honesty-checkbox')),
      300,
    );
    expect(find.byKey(const Key('waifu-honesty-checkbox')), findsOneWidget);
    expect(find.byKey(const Key('waifu-honesty-skipped')), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('waifu-sit-down-confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('waifu-path-mode-folderJail')),
      300,
    );
    await tester.tap(find.byKey(const Key('waifu-path-mode-folderJail')));
    await tester.pump();
    expect(pathMode, WaifuPathMode.folderJail);
    expect(find.byKey(const Key('waifu-honesty-skipped')), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('waifu-sit-down-confirm')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('sidebar Jail chip leaves whole-disk without a quiz', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      pathMode: WaifuPathMode.wholeDisk,
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    await tester.ensureVisible(
      find.byKey(const Key('waifu-path-mode-folderJail')),
    );
    await tester.tap(find.byKey(const Key('waifu-path-mode-folderJail')));
    await tester.pump();
    expect(session.pathMode, WaifuPathMode.folderJail);
    expect(find.byKey(const Key('waifu-whole-disk-honesty')), findsNothing);
  });

  testWidgets('sidebar Disk chip cancel stays in jail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    await tester.ensureVisible(
      find.byKey(const Key('waifu-path-mode-wholeDisk')),
    );
    await tester.tap(find.byKey(const Key('waifu-path-mode-wholeDisk')));
    await tester.pump();
    expect(find.byKey(const Key('waifu-whole-disk-honesty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('waifu-whole-disk-honesty-cancel')));
    await tester.pump();
    expect(session.pathMode, WaifuPathMode.folderJail);
  });

  testWidgets('sidebar Disk chip confirm opens the disk', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = await Directory.systemTemp.createTemp('waifu_switch_store_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = WaifuStore(dir.path);
    const folder = '/tmp/throwaway-waifu';
    final session = WaifuSession(
      folderRoot: folder,
      coworker: CharacterCard(name: 'Iris'),
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
      store: store,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness, store: store),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('waifu-path-mode-wholeDisk')),
    );
    await tester.tap(find.byKey(const Key('waifu-path-mode-wholeDisk')));
    await tester.pump();
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('waifu-whole-disk-honesty-confirm')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('waifu-whole-disk-honesty-check')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('waifu-whole-disk-honesty-confirm')));
    await tester.pump();
    expect(session.pathMode, WaifuPathMode.wholeDisk);
    await tester.pump(const Duration(milliseconds: 50));
    final consent = await store.loadPorchConsent(folder);
    expect(consent, isNotNull);
    expect(consent!.pathMode, WaifuPathMode.wholeDisk);
  });
}
