// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/image_studio/expression_pack_dialog.dart';
import 'package:front_porch_ai/ui/image_studio/expression_pack_setup.dart';

Uint8List picture(int red) {
  final image = img.Image(width: 64, height: 80);
  img.fill(image, color: img.ColorRgb8(red, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  testWidgets('pack launch uses the replacement card portrait', (tester) async {
    late StorageService storage;
    late CharacterRepository repository;
    late ImageGenService image;
    late AppDatabase database;
    late Directory dir;
    late CharacterCard card;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('portrait_launch_');
      storage = StorageService.sandbox(dir.path);
      final prefs = await SharedPreferences.getInstance();
      storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
      await storage.imageGenSettings.setImageGenBackend('a1111');
      database = AppDatabase.forTesting();
      repository = CharacterRepository(database, storage);
      await repository.loadCharacters();
      final source = File('${storage.charactersDir.path}/portrait.png');
      await source.writeAsBytes(picture(80));
      card = CharacterCard(name: 'Portrait test', imagePath: source.path);
      await repository.addCharacter(card);
      await repository.addAvatar(
        card.dbId!,
        card.name,
        picture(230),
        'neutral',
      );
      await source.writeAsBytes(picture(160));
      image = ImageGenService(storage);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      image.dispose();
      repository.dispose();
      storage.dispose();
      await database.close();
      await dir.delete(recursive: true);
    });
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ImageGenService>.value(value: image),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ExpressionPackDialog.launch(
                  context,
                  characterDbId: card.dbId!,
                  characterName: card.name,
                  repository: repository,
                  candidateBase: null,
                  basePrompt: 'portrait',
                  negativePrompt: '',
                ),
                child: const Text('Open pack'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open pack'));
    for (
      var i = 0;
      i < 30 && find.byType(ExpressionPackSetup).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final setup = tester.widget<ExpressionPackSetup>(
      find.byType(ExpressionPackSetup),
    );
    expect(img.decodePng(setup.baseImage)!.getPixel(0, 0).r, 160);
  });
}
