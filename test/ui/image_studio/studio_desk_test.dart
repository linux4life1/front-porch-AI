import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';
import 'package:front_porch_ai/ui/image_studio/studio_edit_pane.dart';
import 'package:provider/provider.dart';

void main() {
  test(
    'a comfy run uses the workflow file, not a leftover checkpoint name',
    () {
      expect(
        deskPrimaryFile(
          backend: 'comfyui',
          edit: false,
          workflowId: 'z_image_turbo',
          choices: const {
            'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors',
          },
          legacyModel: 'qwen_image.safetensors',
        ),
        'z_image_turbo_bf16.safetensors',
      );
    },
  );

  testWidgets('the studio desk keeps Generate off until a model is saved', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('studio-desk');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final page = File(
      'lib/ui/image_studio/studio_view.dart',
    ).readAsStringSync();
    expect(page.contains('StudioDesk'), isTrue);
    expect(page.contains('StudioSettingsPanel'), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: Scaffold(
            body: SingleChildScrollView(child: StudioDesk(onGenerate: () {})),
          ),
        ),
      ),
    );
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Model search'), findsOneWidget);
    FilledButton generate() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(generate().onPressed, isNull);

    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic1111').last);
    await tester.pumpAndSettle();
    expect(storage.imageGenSettings.imageGenBackend, 'a1111');

    await tester.tap(find.text('Model search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'portrait.safetensors');
    await tester.pump();
    await tester.tap(find.text('Use portrait.safetensors'));
    await tester.pumpAndSettle();

    expect(storage.imageGenSettings.imageGenModel, 'portrait.safetensors');
    expect(generate().onPressed, isNotNull);
  });

  test(
    'the edit pane is fixed to edit and local backends list their models',
    () {
      final desk = File(
        'lib/ui/image_studio/studio_desk.dart',
      ).readAsStringSync();
      final view = File(
        'lib/ui/image_studio/studio_view.dart',
      ).readAsStringSync();
      final pane = File(
        'lib/ui/image_studio/studio_edit_pane.dart',
      ).readAsStringSync();
      expect(desk.contains('fetchA1111Models'), isTrue);
      expect(desk.contains('fetchDrawThingsModels'), isTrue);
      expect(view.contains('editMode: false'), isTrue);
      expect(pane.contains('editMode: true'), isTrue);
    },
  );

  testWidgets('the edit pane reports the edit model, not the create slot', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('studio-edit-pane');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('remote');
    await storage.imageGenSettings.setImageGenEditModel('vendor/flux');
    bool? ready;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: Scaffold(
            body: SingleChildScrollView(
              child: StudioEditPane(onReadyChanged: (value) => ready = value),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Create'), findsNothing);
    expect(find.text('vendor/flux'), findsOneWidget);
    expect(ready, isTrue);
    expect(storage.imageGenSettings.imageGenModel, isNot('vendor/flux'));
  });
}
