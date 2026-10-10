// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character made without a portrait still gets a card picture: the card
// file needs one, so V2CardService writes a flat 400×600 colour. Home used
// to show that flat box (blue for "Juniper"); a character with no picture at
// all showed the person icon. Both now show the person icon on the desktop,
// and the phone's library is told (placeholderPortrait) so it draws its
// initial.
// Real portraits, including a real 400×600 one, are left alone.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card.dart';

void _mockPathProvider(Directory root) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return root.path;
        return null;
      });
}

/// A real picture at the placeholder's exact size: a gradient, so the
/// samples differ.
File _realPortrait400x600(String path) {
  final image = img.Image(width: 400, height: 600);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 400; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, 120);
    }
  }
  return File(path)..writeAsBytesSync(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File placeholder;
  late File real;

  setUp(() async {
    PlaceholderPortraitProbe.clearCache();
    root = Directory.systemTemp.createTempSync('fpai_noportrait_');
    final chars = Directory(p.join(root.path, 'chars'))..createSync();
    placeholder = File(p.join(chars.path, 'Juniper_1.png'));
    // The exact file the creators write for "no portrait yet".
    await V2CardService().saveCardAsPng(
      CharacterCard(name: 'Juniper'),
      placeholder.path,
      null,
    );
    real = _realPortrait400x600(p.join(chars.path, 'Marlow_1.png'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the probe knows the creators\' placeholder from a real picture',
    () async {
      expect(
        await PlaceholderPortraitProbe.check(placeholder, version: 1),
        isTrue,
      );
      expect(await PlaceholderPortraitProbe.check(real, version: 1), isFalse);

      final square = File(p.join(root.path, 'square.png'))
        ..writeAsBytesSync(
          img.encodePng(
            img.fill(
              img.Image(width: 512, height: 512),
              color: img.ColorRgb8(90, 120, 200),
            ),
          ),
        );
      expect(await PlaceholderPortraitProbe.check(square, version: 1), isFalse);
      expect(
        await PlaceholderPortraitProbe.check(
          File(p.join(root.path, 'gone.png')),
          version: 1,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'Home shows the person icon for a card with only the placeholder',
    (tester) async {
      Widget card(File file) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 320,
            child: CharacterGridCard(
              character: CharacterCard(name: 'Juniper', imagePath: file.path),
              activeFolderId: null,
              messageCountCache: const {},
              isSelecting: false,
              isOrganizing: false,
              selectedCharacterIds: const {},
              onTapCharacter: (_) async {},
              onToggleSelect: (_) {},
              onContextMenuAction: (_, _) {},
              onResolveCharImage: (_) => file,
            ),
          ),
        ),
      );

      // Probe on real time first (file reads and the decode isolate do not
      // run under the widget test's fake clock); the card then paints from
      // the cached answer, as it does on every rebuild after the first.
      await tester.runAsync(() async {
        await PlaceholderPortraitProbe.check(placeholder, version: 0);
        await PlaceholderPortraitProbe.check(real, version: 0);
      });

      await tester.pumpWidget(card(placeholder));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(card(real));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
    },
  );

  test('the phone library flags a placeholder picture', () async {
    SharedPreferences.setMockInitialValues(const {});
    _mockPathProvider(root);
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final storage = StorageService();
    await storage.initialized;
    addTearDown(storage.dispose);
    final dir = storage.charactersDir..createSync(recursive: true);
    placeholder.copySync(p.join(dir.path, 'Juniper_1.png'));
    real.copySync(p.join(dir.path, 'Marlow_1.png'));
    for (final (id, name, file) in [
      ('c1', 'Juniper', 'Juniper_1.png'),
      ('c2', 'Marlow', 'Marlow_1.png'),
    ]) {
      await db.insertCharacter(
        CharactersCompanion(
          id: Value(id),
          name: Value(name),
          imagePath: Value(file),
        ),
      );
    }

    final rows = await CharacterFacade(db, storage, null, null, null).list();
    Map<String, dynamic> row(String name) =>
        rows.firstWhere((r) => r['name'] == name);
    // Both still have a card file; only the placeholder is flagged.
    expect(row('Juniper')['hasAvatar'], isTrue);
    expect(row('Juniper')['placeholderPortrait'], isTrue);
    expect(row('Marlow')['hasAvatar'], isTrue);
    expect(row('Marlow')['placeholderPortrait'], isFalse);
  });
}
