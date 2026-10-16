// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/expression_workspace_harness.dart' as fixture;

Future<void> finish(WidgetTester tester, Future<void> Function() action) =>
    fixture.finishReal(tester, action);

Future<void> stateFailure(Future<void> Function() action) async {
  Object? failure;
  try {
    await action();
  } catch (error) {
    failure = error;
  }
  expect(failure, isA<StateError>());
}

void main() {
  testWidgets(
    'corrupt queue preserves its file, allows relocation and can retry',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final folder = Directory(
          '${rig.storage.rootPath ?? rig.storage.binDir.parent.path}/ImageBatches',
        );
        await folder.create(recursive: true);
        final manifest = File('${folder.path}/queue.json');
        await manifest.writeAsString('not json');
        final queue = ImageBatchService(rig.storage, rig.image);
        await queue.ready;
        expect(queue.loadFailed, isTrue);
        expect(await manifest.readAsString(), 'not json');
        expect(rig.storage.rootRelocation.refusal, isNull);
        await stateFailure(queue.run);
        await manifest.writeAsString(jsonEncode({'version': 1, 'jobs': []}));
        await queue.retryLoad();
        expect(queue.loadFailed, isFalse);
        expect(queue.jobs, isEmpty);
        queue.dispose();
      });
    },
  );
  testWidgets(
    'active frames reject review writes and redo captures current parameters',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final queue = ImageBatchService(rig.storage, rig.image);
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'additional',
          prompt: 'Garden',
        );
        rig.image.paused = true;
        final flight = queue.run();
        while (rig.image.pending == null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await stateFailure(() => queue.decide(queue.jobs.single.id, 'discard'));
        await stateFailure(() => queue.saveKept(rig.repository));
        rig.image.pending!.complete(rig.image.picture);
        await flight;
        rig.image.paused = false;
        await rig.storage.imageGenSettings.setImageGenSize('512x512');
        await rig.storage.imageGenSettings.setImageGenNegativePrompt(
          'latest negative',
        );
        await rig.storage.imageGenSettings.setImageGenDenoise(0.25);
        await queue.decide(
          queue.jobs.single.id,
          'redo',
          newSeed: false,
          repository: rig.repository,
        );
        expect(queue.jobs.last.data['size'], '512x512');
        expect(queue.jobs.last.data['negativePrompt'], 'latest negative');
        expect(queue.jobs.last.data['denoise'], 0.25);
        queue.dispose();
      });
    },
  );
  testWidgets(
    'save and discard remove candidate files while preserving character images',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final queue = ImageBatchService(rig.storage, rig.image);
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!, rig.second.dbId!],
          kind: 'additional',
          prompt: 'Garden',
        );
        await queue.run();
        final folder = Directory(
          '${rig.storage.rootPath ?? rig.storage.binDir.parent.path}/ImageBatches',
        );
        expect(
          await folder
              .list()
              .where((file) => file.path.endsWith('.png'))
              .length,
          2,
        );
        await queue.decide(queue.jobs.first.id, 'keep');
        await queue.saveKept(rig.repository);
        await queue.decide(queue.jobs.last.id, 'discard');
        expect(
          await folder
              .list()
              .where((file) => file.path.endsWith('.png'))
              .length,
          0,
        );
        expect(
          await rig.repository.getAvatarImages(rig.first.dbId!),
          hasLength(1),
        );
        queue.dispose();
      });
    },
  );
  testWidgets(
    'primary promotion keeps external imports intact and demotes the previous portrait',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final external = File(
          '${rig.storage.binDir.parent.path}/external-import.png',
        );
        await external.writeAsBytes(fixture.workspacePicture(120));
        rig.first.imagePath = external.path;
        await rig.repository.updateCharacter(rig.first);
        final original = await external.readAsBytes();
        final queue = ImageBatchService(rig.storage, rig.image);
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'portrait',
          prompt: 'Portrait',
        );
        await queue.run();
        await queue.decide(queue.jobs.single.id, 'keep');
        await queue.saveKept(rig.repository);
        expect(await external.readAsBytes(), original);
        final current = (await rig.repository.getCharacterCardById(
          rig.first.dbId!,
        ))!;
        expect(current.imagePath, isNot(external.path));
        final gallery = await rig.repository.getAvatarImages(rig.first.dbId!);
        expect(gallery, hasLength(1));
        expect(gallery.single.isLook, isTrue);
        expect(
          await gallery.single
              .resolveFile(rig.storage.characterBaseDir(current.name).path)
              .readAsBytes(),
          original,
        );
        queue.dispose();
      });
    },
  );
}
