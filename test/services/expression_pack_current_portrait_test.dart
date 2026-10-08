// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

Uint8List _portrait(int color) {
  final image = img.Image(width: 64, height: 80);
  img.fill(image, color: img.ColorRgb8(color, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a new pack follows the changed card portrait before old expressions',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pack_current_portrait_',
      );
      final storage = StorageService.sandbox(directory.path);
      final database = AppDatabase.forTesting();
      final repository = CharacterRepository(database, storage);
      await repository.loadCharacters();
      try {
        final source = File('${directory.path}/source.png');
        final first = _portrait(80);
        final second = _portrait(160);
        final oldExpression = _portrait(230);
        await source.writeAsBytes(first);
        final card = CharacterCard(
          name: 'Portrait test',
          imagePath: source.path,
        );
        await repository.addCharacter(card);
        await repository.addAvatar(
          card.dbId!,
          card.name,
          oldExpression,
          'neutral',
        );
        expect(
          await packBaseImage(repository, storage, card.dbId!, card.name),
          first,
        );
        await source.writeAsBytes(second);
        expect(
          await packBaseImage(repository, storage, card.dbId!, card.name),
          second,
        );
        await source.delete();
        expect(
          await packBaseImage(repository, storage, card.dbId!, card.name),
          oldExpression,
        );
      } finally {
        repository.dispose();
        storage.dispose();
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
