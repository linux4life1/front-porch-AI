// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

void main() {
  final url = Platform.environment['FPAI_COMFY_LIVE_URL'];
  final workflow = Platform.environment['FPAI_COMFY_LIVE_WORKFLOW'];

  testWidgets(
    'Edit can cancel, confirm, and revoke existing GGUF support',
    (tester) async {
      HttpOverrides.global = null;
      final previous = City96Gate.instance;
      City96Gate.instance = City96Gate();
      addTearDown(() => City96Gate.instance = previous);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gguf-support-desk-'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final storage = StorageService.sandbox(dir.path);
      await tester.runAsync(() async {
        await storage.imageGenSettings.setImageGenBackend('comfyui');
        await storage.imageGenSettings.setComfyUiUrl(url!);
        await storage.imageGenSettings.setComfyEditUploadedWorkflow(
          await File(workflow!).readAsString(),
          title: 'GGUF compatibility test',
        );
        await storage.imageGenSettings.setComfyEditWorkflowId(
          kComfyUploadedWorkflowId,
        );
        await storage.imageGenSettings.setImageGenEditModel(
          'qwen-image-2.1.gguf',
        );
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var reportedReady = false;
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StudioDesk(
                  editMode: true,
                  onReadyChanged: (ready) => reportedReady = ready,
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> waitFor(String text) async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          if (find.text(text).evaluate().isNotEmpty) return;
        }
        fail('Did not find $text on the live Edit desk');
      }

      await waitFor('Use existing GGUF support…');
      await tester.tap(find.text('Use existing GGUF support…'));
      await tester.pumpAndSettle();
      expect(find.text('Use existing GGUF support?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(City96Gate.instance.hasExistingSupport(url!), isFalse);

      await tester.tap(find.text('Use existing GGUF support…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use existing support'));
      await waitFor('Recheck GGUF support');
      expect(City96Gate.instance.hasExistingSupport(url), isTrue);
      for (var i = 0; i < 100 && !reportedReady; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(reportedReady, isTrue);
      expect(
        find.textContaining('This model needs the GGUF loader update.'),
        findsNothing,
      );
      await tester.tap(find.text('Recheck GGUF support'));
      await waitFor('Use existing GGUF support…');
      expect(City96Gate.instance.hasExistingSupport(url), isFalse);
      expect(reportedReady, isFalse);
      await tester.pumpWidget(const SizedBox());
      storage.dispose();
    },
    tags: ['live'],
    skip: url == null || workflow == null,
  );
}
