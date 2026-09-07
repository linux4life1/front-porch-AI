// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/chat_image_attachment.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Uint8List _tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

void main() {
  test('looksLikeImageFileName accepts photos, not dart files', () {
    expect(looksLikeImageFileName('shot.PNG'), isTrue);
    expect(looksLikeImageFileName('notes.dart'), isFalse);
  });

  test('firstDroppedImage skips non-images and keeps a png', () async {
    final png = _tinyPng();
    final got = await firstDroppedImage([
      (name: 'readme.md', read: () async => Uint8List.fromList([1, 2, 3])),
      (name: 'shot.png', read: () async => png),
    ]);
    expect(got, isNotNull);
    expect(got!.length, greaterThan(8));
  });

  test(
    'harness first generate carries the photo; later steps do not',
    () async {
      final root = await Directory.systemTemp.createTemp('desk_img_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final png = _tinyPng();
      final path = await deskSaveInboxPhoto(root.path, png);
      expect(File(path).existsSync(), isTrue);
      expect(p.basename(p.dirname(path)), 'inbox');

      final llm = ScriptedDeskLlm([
        const LlmToolResponse(calls: [], text: 'Hmph. I see it.'),
      ]);
      final session = DeskSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      );
      await DeskHarness(
        session: session,
        llm: llm,
      ).send('what is this', imagePng: png, imagePath: path);
      expect(llm.calls, hasLength(1));
      expect(llm.calls.first.images, isNotNull);
      expect(llm.calls.first.images, isNotEmpty);
      expect(session.transcript.first.imagePath, path);
      expect(
        session.transcript.first
            .toChatMessage('Iris')
            .activeMetadata?['is_user_image'],
        isTrue,
      );
    },
  );
}
