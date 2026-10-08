// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('discard refuses a concurrent real pack import', () async {
    final dir = await Directory.systemTemp.createTemp('pack_import_discard_');
    final storage = StorageService.sandbox(dir.path);
    final database = AppDatabase.forTesting();
    final repository = CharacterRepository(database, storage);
    final image = ImageGenService(storage);
    final board = ExpressionPackBoard();
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 32, height: 32)),
    );
    final session = ExpressionPackSession(
      emotions: ['happy'],
      basePrompt: 'portrait',
      negativePrompt: '',
      denoise: 0.7,
      editMode: true,
      generate:
          ({
            required prompt,
            required negativePrompt,
            required seed,
            required denoise,
          }) async => png,
    );
    try {
      await repository.loadCharacters();
      final card = CharacterCard(name: 'Pack import test');
      await repository.addCharacter(card);
      await session.run();
      final run = PackRun(
        session: session,
        mode: PackMode.edit,
        origin: PackOrigin.phone,
        characterName: card.name,
        characterId: card.dbId,
      );
      board.publish(run);
      final facade = ImageFacade(image, storage, repository, board);
      final importing = facade.importPack({});
      expect(run.importing, isTrue);
      expect(
        facade.discardPack,
        throwsA(
          isA<DeskRefused>()
              .having((error) => error.code, 'code', 'importing')
              .having((error) => error.status, 'status', 409),
        ),
      );
      await expectLater(
        facade.startPack({}),
        throwsA(
          isA<DeskRefused>().having((error) => error.code, 'code', 'importing'),
        ),
      );
      final result = await importing;
      expect(result['imported'], 1);
      expect(run.importing, isFalse);
      expect(board.run, same(run));
      expect(await repository.getAvatarImages(card.dbId!), hasLength(1));
    } finally {
      board.clear();
      image.dispose();
      repository.dispose();
      storage.dispose();
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
