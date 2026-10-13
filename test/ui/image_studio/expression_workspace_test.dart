// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';
import 'package:front_porch_ai/ui/image_studio/studio_widgets.dart';

import '../../helpers/expression_workspace_harness.dart';
export '../../helpers/expression_workspace_harness.dart';

Future<void> pumpWorkspace(
  WidgetTester tester,
  WorkspaceRig rig, {
  Size size = const Size(1050, 1400),
  ValueChanged<String>? onImported,
  ImageStudio? studio,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: rig.storage),
        ChangeNotifierProvider<ImageGenService>.value(value: rig.image),
        ChangeNotifierProvider<CharacterRepository>.value(
          value: rig.repository,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    studio ??
                    ImageStudio(
                      mode: ImageGenMode.characterPortrait,
                      characterName: rig.first.name,
                      characterDbId: rig.first.dbId,
                      onExpressionsImported: onImported,
                    ),
              ),
              child: const Text('Open Studio'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Studio'));
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump(const Duration(milliseconds: 400));
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    });
    await tester.pump();
    if (find
        .byType(ExpressionPackSetup, skipOffstage: false)
        .evaluate()
        .isNotEmpty) {
      break;
    }
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets(
    'Expressions retains independent drafts and current card portrait across Create and Edit',
    (tester) async {
      final rig = await workspaceRig(tester);
      // A previous expression differs visibly from the current main card image.
      await tester.runAsync(
        () => rig.repository.addLook(
          rig.first.dbId!,
          rig.first.name,
          workspacePicture(230),
        ),
      );
      await pumpWorkspace(tester, rig);
      await tester.tap(find.text('Expressions'));
      await tester.pump();
      expect(find.text('Source: Character portrait'), findsOneWidget);

      final setup = tester.widget<ExpressionPackSetup>(
        find.byType(ExpressionPackSetup),
      );
      expect(img.decodePng(setup.baseImage)!.getPixel(0, 0).r, 100);
      await tester.enterText(
        find.byKey(const Key('expression-description')),
        'keep this expression draft',
      );
      await tester.tap(find.text('Create'));
      await tester.pump();
      final createPrompt = find
          .descendant(
            of: find.byType(StudioDeskFrame),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(createPrompt, 'Create stays independent');
      await tester.tap(find.text('Edit').first);
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).first,
        'Edit stays independent',
      );
      await tester.tap(find.text('Expressions'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('expression-description')))
            .controller!
            .text,
        'keep this expression draft',
      );
      expect(
        tester
            .widget<ExpressionPackDialog>(find.byType(ExpressionPackDialog))
            .characterDbId,
        rig.first.dbId,
      );
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(find.text('Create stays independent'), findsOneWidget);
      expect(find.byType(ExcludeFocus, skipOffstage: false), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'active pack survives navigation, locks settings, cancels with results and imports into its frozen target',
    (tester) async {
      final rig = await workspaceRig(tester);
      final imports = <String>[];
      await pumpWorkspace(
        tester,
        rig,
        size: const Size(800, 1000),
        onImported: imports.add,
      );
      await tester.tap(find.text('Expressions'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('expression-character')));
      await tester.pump();
      await tester.tap(find.text(rig.second.name).last);
      await tester.pump();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump();
        if (find.byType(ExpressionPackSetup).evaluate().isNotEmpty) break;
      }
      rig.image.paused = true;
      await tapVisible(tester, find.textContaining('Start ('));
      for (
        var attempt = 0;
        attempt < 20 && expressionPackBoard.run == null;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(expressionPackBoard.run?.characterId, rig.second.dbId);
      expect(rig.image.calls.single.intent, StudioIntent.create);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('expression-description')))
            .enabled,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Discard expression pack?'), findsOneWidget);
      await tester.tap(find.text('Keep pack'));
      await tester.pump();
      expect(expressionPackBoard.run!.session.isRunning, isTrue);
      await tester.tap(find.text('Create'));
      await tester.pump();
      final prompt = find
          .descendant(
            of: find.byType(StudioDeskFrame),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(prompt, 'draft during pack');
      final gates = tester.widgetList<StudioSettingsGate>(
        find.byType(StudioSettingsGate),
      );
      expect(gates.every((g) => g.busy), isTrue);
      await tester.tap(find.text('Expressions'));
      await tester.pump();
      await tapVisible(tester, find.text('Cancel'));
      rig.image.pending!.complete(rig.image.picture);
      await tester.pump();
      expect(expressionPackBoard.run!.session.doneCount, 1);
      expect(find.textContaining('Generate remaining'), findsOneWidget);
      rig.image.setBusy(true);
      await tester.pump();
      await tapVisible(tester, find.textContaining('Generate remaining'));
      expect(
        rig.image.calls,
        hasLength(1),
        reason: 'A retained pack must not add frames to another generation.',
      );
      rig.image.setBusy(false);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Import 1 expressions'));
      for (var attempt = 0; attempt < 40 && imports.isEmpty; attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump();
      }
      expect(imports, [rig.second.dbId]);
      expect(find.text('Image Studio'), findsOneWidget);
      expect(
        await tester
            .state<StudioExpressionTabState>(find.byType(StudioExpressionTab))
            .confirmClose(),
        isTrue,
        reason: 'Imported results must not trigger a discard warning on close.',
      );
      expect(find.text('Discard expression pack?'), findsNothing);
      await tapVisible(tester, find.text('Reset pack'));
      await tester.pump();
      expect(find.text('Discard expression pack?'), findsNothing);
      expect(expressionPackBoard.run, isNull);
      await tester.pumpWidget(const SizedBox());
      expect(expressionPackBoard.run, isNull);
    },
  );

  testWidgets(
    'retained phone pack cannot be replaced or released by the workspace',
    (tester) async {
      final rig = await workspaceRig(tester);
      final foreign = ExpressionPackSession(
        emotions: ['joy'],
        basePrompt: 'foreign',
        negativePrompt: '',
        denoise: .7,
        generate:
            ({
              required prompt,
              required negativePrompt,
              required seed,
              required denoise,
            }) async => rig.image.picture,
      );
      expressionPackBoard.publish(
        PackRun(
          session: foreign,
          mode: PackMode.img2img,
          origin: PackOrigin.phone,
          characterName: 'Other card',
        ),
      );
      addTearDown(() {
        expressionPackBoard.clear();
      });
      await pumpWorkspace(tester, rig);
      await tester.tap(find.text('Expressions'));
      await tester.pump();
      await tapVisible(tester, find.textContaining('Start ('));
      expect(expressionPackBoard.run!.session, same(foreign));
      expect(rig.image.calls, isEmpty);
      expect(
        find.textContaining('Another screen has an expression pack'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(expressionPackBoard.run!.session, same(foreign));
    },
  );

  testWidgets(
    'busy focus loss and already open model picker do not mutate shared settings',
    (tester) async {
      final rig = await workspaceRig(tester);
      await pumpWorkspace(tester, rig);
      await tapVisible(tester, find.textContaining('Advanced').first);
      final seed = find
          .descendant(
            of: find.byKey(
              ValueKey('seed-${rig.storage.imageGenSettings.imageGenSeed}'),
            ),
            matching: find.byType(TextField),
          )
          .first;
      await tester.ensureVisible(seed);
      await tester.enterText(seed, '4321');
      final before = rig.storage.imageGenSettings.imageGenSeed;
      rig.image.setBusy(true);
      await tester.pump();
      expect(rig.storage.imageGenSettings.imageGenSeed, before);
      rig.image.setBusy(false);
      await tester.pump();
      await tapVisible(tester, find.text('Change model').first);
      rig.image.setBusy(true);
      await tester.pump();
      await tester.tap(find.text('alternate').last);
      await tester.pump();
      expect(rig.storage.imageGenSettings.imageGenModel, 'portrait');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('portrait reload uses the current card image after it changes', (
    tester,
  ) async {
    final rig = await workspaceRig(tester);
    await pumpWorkspace(tester, rig);
    await tester.tap(find.text('Expressions'));
    await tester.pump();
    await tester.runAsync(
      () => File(rig.first.imagePath!).writeAsBytes(workspacePicture(201)),
    );
    await tapVisible(tester, find.text('Use character portrait'));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump();
      if (find.byType(ExpressionPackSetup).evaluate().isNotEmpty) break;
    }
    expect(
      img
          .decodePng(
            tester
                .widget<ExpressionPackSetup>(find.byType(ExpressionPackSetup))
                .baseImage,
          )!
          .getPixel(0, 0)
          .r,
      201,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Expressions explains an unavailable library while its backend controls stay available',
    (tester) async {
      final rig = await workspaceRig(tester);
      await tester.binding.setSurfaceSize(const Size(440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: rig.storage),
            ChangeNotifierProvider<ImageGenService>.value(value: rig.image),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ImageStudio(mode: ImageGenMode.characterPortrait),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Expressions'));
      await tester.pump();
      expect(
        find.textContaining('Character library is unavailable'),
        findsOneWidget,
      );
      expect(find.byType(StudioDesk), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
