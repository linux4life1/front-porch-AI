// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';
import 'package:front_porch_ai/ui/image_studio/studio_widgets.dart';
import 'expression_workspace_test.dart' as fixture;

Future<void> settleSources(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('workspace can discard a stopped phone pack and keep its draft', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
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
        characterName: 'Phone character',
      ),
    );
    addTearDown(expressionPackBoard.clear);
    await fixture.pumpWorkspace(tester, rig);
    await tester.tap(find.text('Expressions'));
    await settleSources(tester);
    final field = find.byKey(const Key('expression-description'));
    await tester.enterText(field, 'Keep this draft');
    await fixture.tapVisible(tester, find.text('Discard phone pack'));
    await tester.pump();
    expect(expressionPackBoard.run!.session, same(foreign));
    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(expressionPackBoard.run, isNull);
    expect(tester.widget<TextField>(field).controller!.text, 'Keep this draft');
  });
  testWidgets('same-character shortcut transfers a typed Studio prompt once', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await fixture.pumpWorkspace(tester, rig);
    final view = tester.widget<StudioView>(find.byType(StudioView));
    view.onPromptChanged('A deliberate image prompt');
    await tester.pump();
    tester.widget<StudioView>(find.byType(StudioView)).onExpressionPack!();
    await settleSources(tester);
    final field = find.byKey(const Key('expression-description'));
    expect(
      tester.widget<TextField>(field).controller!.text,
      'A deliberate image prompt',
    );
    await tester.enterText(field, 'An independent pack draft');
    await tester.tap(find.text('Create'));
    await tester.pump();
    tester.widget<StudioView>(find.byType(StudioView)).onExpressionPack!();
    await settleSources(tester);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'An independent pack draft',
    );
  });

  testWidgets(
    'prompt preparation disables pack startup until the actual writer finishes',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      final release = Completer<void>();
      final writer = ImageGenService(rig.storage);
      addTearDown(writer.dispose);
      await tester.binding.setSurfaceSize(const Size(1050, 1000));
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
              body: StudioExpressionTab(
                initialCharacterId: rig.first.dbId,
                onCraftPrompt: (card, instruction) async {
                  await release.future;
                  return writer.generateSmartPrompt(
                    mode: ImageGenMode.characterPortrait,
                    style: rig.storage.imageGenSettings.imageGenStyle,
                    characterName: card.name,
                    characterDescription: card.description,
                    currentExpression: 'neutral',
                    userInstruction: instruction,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await settleSources(tester);
      await tester.tap(find.text('Write it for me'));
      await tester.pump();
      expect(
        tester
            .widget<ExpressionPackSetup>(find.byType(ExpressionPackSetup))
            .busy,
        isTrue,
      );
      expect(rig.image.calls, isEmpty);
      release.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExpressionPackSetup>(find.byType(ExpressionPackSetup))
            .busy,
        isFalse,
      );
      expect(
        tester
            .widget<ExpressionPackDialog>(find.byType(ExpressionPackDialog))
            .basePrompt,
        isNotEmpty,
      );
    },
  );

  testWidgets('Freeform Expressions requires an explicit library target', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await fixture.pumpWorkspace(
      tester,
      rig,
      studio: const ImageStudio(mode: ImageGenMode.customPrompt),
    );
    await tester.tap(find.text('Expressions'));
    await tester.pump();
    expect(find.byType(ExpressionPackSetup), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('expression-character')),
          )
          .initialValue,
      isNull,
    );
    await tester.tap(find.byKey(const Key('expression-character')));
    await tester.pump();
    await tester.tap(find.text(rig.second.name).last);
    await settleSources(tester);
    expect(
      tester
          .widget<ExpressionPackDialog>(find.byType(ExpressionPackDialog))
          .characterDbId,
      rig.second.dbId,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('expression-description')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('group header tab hands the chosen member to Expressions', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await fixture.pumpWorkspace(
      tester,
      rig,
      studio: ImageStudio(
        mode: ImageGenMode.characterPortrait,
        groupCharacters: [
          (
            name: rig.first.name,
            description: rig.first.description,
            dbId: rig.first.dbId,
          ),
          (
            name: rig.second.name,
            description: rig.second.description,
            dbId: rig.second.dbId,
          ),
        ],
      ),
    );
    final subject = tester.widget<SubjectPicker>(find.byType(SubjectPicker));
    subject.onPickGroupMember!(1);
    await tester.pump();
    await tester.tap(find.text('Expressions'));
    await settleSources(tester);
    expect(
      tester
          .widget<ExpressionPackDialog>(find.byType(ExpressionPackDialog))
          .characterDbId,
      rig.second.dbId,
    );
  });

  testWidgets('busy focus loss preserves the settings draft until Apply', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await fixture.pumpWorkspace(tester, rig);
    await fixture.tapVisible(tester, find.textContaining('Advanced').first);
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
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(rig.storage.imageGenSettings.imageGenSeed, before);
    expect(tester.widget<TextField>(seed).controller!.text, '4321');
    rig.image.setBusy(false);
    await tester.pump();
    await fixture.tapVisible(tester, find.text('Apply'));
    await tester.pump();
    expect(rig.storage.imageGenSettings.imageGenSeed, 4321);
  });
}
