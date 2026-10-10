// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'expression_workspace_test.dart' as fixture;

void main() {
  testWidgets(
    'batch survives navigation, pauses, persists review and saves additional portraits without promotion',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      Future<void> finish(Future<void> Function() action) async {
        var done = false;
        Object? failure;
        await tester.runAsync(() async {
          action().then<void>(
            (_) {
              done = true;
            },
            onError: (Object e) {
              failure = e;
              done = true;
            },
          );
        });
        for (var i = 0; i < 200 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue, reason: 'real I/O action did not complete');
        if (failure != null) throw failure!;
      }

      late ImageBatchService queue;
      final initialPath = rig.first.imagePath;
      late List<int> original;
      await finish(() async {
        queue = ImageBatchService(rig.storage, rig.image);
        await File(initialPath!).writeAsBytes(
          img.encodePng(
            img.copyResize(
              img.decodePng(rig.image.picture)!,
              width: 400,
              height: 600,
            ),
          ),
        );
        original = await File(initialPath).readAsBytes();
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!, rig.second.dbId!],
          kind: 'additional',
          prompt: '{character} in a garden',
        );
      });
      expect(queue.jobs.map((j) => j.prompt), [
        'First card in a garden',
        'Second card in a garden',
      ]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CharacterRepository>.value(
              value: rig.repository,
            ),
          ],
          child: MaterialApp(home: ImageBatchesPage(queue: queue)),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.tap(find.text('Queue'));
      await tester.pump();
      expect(find.text('Start 2 images'), findsOneWidget);
      rig.image.paused = true;
      await tester.tap(find.text('Start 2 images'));
      for (var i = 0; i < 50 && rig.image.pending == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(rig.image.calls, hasLength(1));
      await tester.tap(find.text('Pause after current image'));
      await tester.pumpWidget(const SizedBox());
      rig.image.pending!.complete(rig.image.picture);
      for (var i = 0; i < 50 && queue.running; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(queue.jobs.map((j) => j.state), ['review', 'waiting']);
      rig.image.paused = false;
      await finish(queue.run);
      expect(queue.jobs.map((j) => j.state), ['review', 'review']);
      await finish(() async {
        await queue.decide(queue.jobs.first.id, 'keep');
        await queue.saveKept(rig.repository);
        final looks = await rig.repository.getAvatarImages(rig.first.dbId!);
        expect(looks, hasLength(1));
        expect(looks.single.isLook, isTrue);
        final pixels = img.decodePng(await queue.picture(queue.jobs.first.id))!;
        expect((pixels.width, pixels.height), (64, 80));
        queue.jobs.first.data['state'] = 'review';
        await queue.saveKept(rig.repository);
        expect(
          await rig.repository.getAvatarImages(rig.first.dbId!),
          hasLength(1),
        );
        expect(
          (await rig.repository.getCharacterCardById(
            rig.first.dbId!,
          ))!.imagePath,
          initialPath,
        );
        expect(await File(initialPath!).readAsBytes(), original);
        final restored = ImageBatchService(rig.storage, rig.image);
        await restored.ready;
        expect(restored.jobs.map((j) => j.state), ['saved', 'review']);
        await restored.decide(
          restored.jobs.last.id,
          'redo',
          prompt: 'A refined garden scene',
          newSeed: false,
        );
        expect(restored.jobs.last.prompt, 'A refined garden scene');
        expect(restored.jobs.last.data['seed'], restored.jobs[1].data['seed']);
        expect(restored.jobs[1].state, 'review');
        await rig.storage.imageGenSettings.setImageGenSteps(17);
        await restored.run();
        expect(restored.jobs.last.state, 'waiting');
        expect(restored.error, contains('settings changed'));
      });
    },
  );
}
