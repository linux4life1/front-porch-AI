// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import '../../helpers/expression_workspace_harness.dart' as fixture;

class CaptureImages extends fixture.WorkspaceImages {
  CaptureImages(super.picture, super.storage);
  final requests = <Map<String, Object?>>[];
  @override
  Future<Uint8List?> generateImage({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    String? model,
    bool isPortrait = false,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) async {
    requests.add({
      'source': referenceImage,
      'negative': negativePrompt,
      'size': size,
      'denoise': denoise,
      'seed': seed,
    });
    return picture;
  }
}

void main() {
  testWidgets(
    'redo of a saved expression retains img2img source, counters and explicit strength',
    (tester) async {
      final rig = await fixture.workspaceRig(tester);
      final image = CaptureImages(rig.image.picture, rig.storage);
      late ImageBatchService queue;
      addTearDown(() {
        queue.dispose();
        image.dispose();
      });
      await tester.runAsync(() async {
        queue = ImageBatchService(rig.storage, image);
        await queue.ready;
        await queue.prepare(
          repository: rig.repository,
          characterIds: [rig.first.dbId!],
          kind: 'expressions',
          prompt: 'portrait',
          denoise: 0.42,
        );
        await queue.run();
        final first = queue.jobs.first;
        expect(first.edit, isFalse);
        expect(image.requests.first['source'], isNotNull);
        await queue.decide(first.id, 'keep');
        await queue.saveKept(rig.repository);
        await File(
          rig.first.imagePath!,
        ).writeAsBytes(fixture.workspacePicture(170));
        await rig.storage.imageGenSettings.setImageGenNegativePrompt(
          'latest global',
        );
        await rig.storage.imageGenSettings.setImageGenSize('512x512');
        await rig.storage.imageGenSettings.setImageGenDenoise(0.23);
        await queue.decide(
          first.id,
          'redo',
          newSeed: false,
          repository: rig.repository,
        );
        final redo = queue.jobs.last;
        expect(redo.data['source'], isNotNull);
        expect(
          redo.data['negativePrompt'],
          contains(kExpressionNegatives[first.label]!),
        );
        image.requests.clear();
        await queue.run();
        final request = image.requests.single;
        expect(request['source'], isA<Uint8List>());
        expect(
          img.decodePng(request['source']! as Uint8List)!.getPixel(0, 0).r,
          170,
        );
        expect(
          request['negative'],
          'latest global, ${kExpressionNegatives[first.label]}',
        );
        expect(request['denoise'], 0.42);
        expect(request['size'], '512x512');
        expect(request['seed'], first.data['seed']);
      });
    },
  );
}
