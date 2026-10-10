// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'expression_workspace_test.dart' as fixture;

Future<void> finish(WidgetTester tester, Future<void> Function() action) async {
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
  for (var i = 0; i < 300 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done, isTrue);
  if (failure != null) throw failure!;
}

void main() {
  testWidgets('settings changes during preparation refuse the entire pass', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await finish(tester, () async {
      final queue = ImageBatchService(rig.storage, rig.image);
      await queue.ready;
      var changed = false;
      queue.addListener(() {
        if (queue.working && !changed) {
          changed = true;
          unawaited(rig.storage.imageGenSettings.setImageGenSize('512x512'));
        }
      });
      await expectLater(
        queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'additional',
          prompt: 'A garden',
        ),
        throwsStateError,
      );
      expect(queue.jobs, isEmpty);
    });
  });

  testWidgets(
    'a queue opened during relocation loads only the destination manifest',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final original = ImageBatchService(rig.storage, rig.image);
        await original.ready;
        await original.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'additional',
          prompt: 'A garden',
        );
        original.dispose();
        final destination = await Directory.systemTemp.createTemp(
          'batch_lazy_move_',
        );
        final entered = Completer<void>(), release = Completer<void>();
        final moving = rig.storage.setRootPath(
          destination.path,
          beforeMove: () async {
            entered.complete();
            await release.future;
          },
        );
        await entered.future;
        final lazy = ImageBatchService(rig.storage, rig.image);
        var loaded = false;
        final loading = lazy.ready.then((_) {
          loaded = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(loaded, isFalse);
        release.complete();
        try {
          expect(await moving, isNull);
          await loading;
          expect(lazy.jobs, hasLength(1));
          expect(lazy.jobs.single.data['config']['root'], destination.path);
        } finally {
          lazy.dispose();
          await destination.delete(recursive: true);
        }
      });
    },
  );

  testWidgets('busy batch refuses relocation before database-close callback', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    await finish(tester, () async {
      final queue = ImageBatchService(rig.storage, rig.image);
      await queue.ready;
      await queue.prepare(
        repository: rig.repository,
        characterIds: [rig.first.dbId!],
        kind: 'additional',
        prompt: 'A garden',
      );
      rig.image.paused = true;
      final flight = queue.run();
      while (rig.image.pending == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      var closed = false;
      expect(
        await rig.storage.setRootPath(
          '${rig.storage.rootPath}_other',
          beforeMove: () async {
            closed = true;
          },
        ),
        isNotNull,
      );
      expect(closed, isFalse);
      expect(
        await rig.repository.getCharacterCardById(rig.first.dbId!),
        isNotNull,
      );
      rig.image.pending!.complete(rig.image.picture);
      await flight;
    });
  });

  testWidgets(
    'primary save preserves raw card metadata and canonical filename',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final queue = ImageBatchService(rig.storage, rig.image);
        await queue.ready;
        final original = rig.first.imagePath!;
        final payload = base64Encode(
          utf8.encode(
            jsonEncode({
              'spec': 'chara_card_v2',
              'spec_version': '2.0',
              'data': {
                'name': rig.first.name,
                'creator_notes': 'Preserve this',
                'custom_field': {'a': 7},
              },
            }),
          ),
        );
        await File(original).writeAsBytes(
          PngMetadataUtils.encodeWithTextChunk(
            img.decodePng(rig.image.picture)!,
            'chara',
            payload,
          ),
        );
        final provider = FileImage(File(original));
        final decoded = Completer<void>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((_, _) => decoded.complete());
        stream.addListener(listener);
        await decoded.future;
        stream.removeListener(listener);
        final cacheKey = await provider.obtainKey(ImageConfiguration.empty);
        expect(
          PaintingBinding.instance.imageCache.containsKey(cacheKey),
          isTrue,
        );
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'portrait',
          prompt: 'A portrait',
        );
        await queue.run();
        await queue.decide(queue.jobs.single.id, 'keep');
        await queue.saveKept(rig.repository);
        final card = (await rig.repository.getCharacterCardById(
          rig.first.dbId!,
        ))!;
        expect(
          PngMetadataUtils.extractTextChunk(
            await File(card.imagePath!).readAsBytes(),
            'chara',
          ),
          payload,
        );
        expect(card.imagePath, original);
        expect(
          PaintingBinding.instance.imageCache.containsKey(cacheKey),
          isFalse,
        );
      });
    },
  );

  testWidgets('deleted characters cannot receive kept results', (tester) async {
    final rig = await fixture.workspaceRig(tester);
    await finish(tester, () async {
      final queue = ImageBatchService(rig.storage, rig.image);
      await queue.ready;
      await queue.prepare(
        repository: rig.repository,
        characterIds: [rig.first.dbId!],
        kind: 'additional',
        prompt: 'A garden',
      );
      await queue.run();
      await queue.decide(queue.jobs.single.id, 'keep');
      await rig.repository.deleteCharacter(rig.first);
      await expectLater(queue.saveKept(rig.repository), throwsStateError);
      expect(await rig.repository.getAvatarImages(rig.first.dbId!), isEmpty);
      expect(queue.jobs.single.state, 'review');
    });
  });

  testWidgets(
    'data relocation keeps candidates and waiting configuration across restart',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final queue = ImageBatchService(rig.storage, rig.image);
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'additional',
          prompt: 'A garden',
        );
        await queue.run();
        await queue.decide(queue.jobs.single.id, 'redo');
        final bytes = await queue.picture(queue.jobs.first.id);
        final destination = await Directory.systemTemp.createTemp(
          'batch_relocation_',
        );
        try {
          expect(await rig.storage.setRootPath(destination.path), isNull);
          expect(await queue.picture(queue.jobs.first.id), bytes);
          final restored = ImageBatchService(rig.storage, rig.image);
          await restored.ready;
          expect(restored.jobs, hasLength(2));
          await restored.run();
          expect(restored.jobs.last.state, 'review');
        } finally {
          await destination.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'initial manifest failure leaves a recoverable request and releases real lock',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final realImage = ImageGenService(rig.storage);
        final queue = ImageBatchService(rig.storage, realImage);
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'additional',
          prompt: 'A garden',
        );
        final blocker = Directory(
          '${rig.storage.rootPath}/ImageBatches/queue.json.tmp',
        );
        await blocker.create();
        try {
          await queue.run();
        } catch (_) {
          /* The real disk error is expected. */
        }
        expect(queue.running, isFalse);
        expect(realImage.isGenerating, isFalse);
        expect(queue.jobs.single.state, isNot('running'));
        await blocker.delete();
        await queue.decide(queue.jobs.single.id, 'discard');
        realImage.dispose();
      });
    },
  );

  testWidgets(
    'queue cannot enter a production image service flight already held by another operation',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      await finish(tester, () async {
        final image = ImageGenService(rig.storage);
        final queue = ImageBatchService(rig.storage, image);
        await queue.ready;
        final entered = Completer<void>(), release = Completer<void>();
        final flight = image.startExpressionPack([], (_) async {
          entered.complete();
          await release.future;
          return [];
        });
        await entered.future;
        expect(image.isGenerating, isTrue);
        await expectLater(queue.run(), throwsStateError);
        expect(image.isGenerating, isTrue);
        release.complete();
        await flight;
        expect(image.isGenerating, isFalse);
        image.dispose();
      });
    },
  );
}
