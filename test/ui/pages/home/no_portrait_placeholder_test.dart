// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character made without a portrait still gets a card picture: the card
// file needs one, so V2CardService writes a flat 400×600 colour. Home used
// to show that flat box (blue for "Juniper"); a character with no picture at
// all showed the person icon. Both now show the person icon on the desktop,
// and the phone's library is told (placeholderPortrait) so it draws its
// initial. Real portraits, including a real 400×600 one, are left alone,
// and most of them are turned away by the chunk headers without a decode.

import 'dart:async';
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

/// A real photo at the placeholder's exact size (most imported cards are
/// 400×600): one of the app's own background pictures, cropped.
File _realPortrait400x600(String path) {
  final photo = img.decodeImage(
    File('assets/backgrounds/beach.png').readAsBytesSync(),
  )!;
  final portrait = img.copyResizeCropSquare(photo, size: 600);
  final cropped = img.copyCrop(portrait, x: 100, y: 0, width: 400, height: 600);
  return File(path)..writeAsBytesSync(img.encodePng(cropped));
}

Widget _card(File file) => MaterialApp(
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

  test('a real 400×600 portrait is turned away before any decode', () async {
    // The header gate reads chunk headers only: the placeholder's pixel data
    // is a few KB (its big card-data chunk is skipped), a photo's is not.
    expect(
      await PlaceholderPortraitProbe.mightBeFlatPlaceholder(placeholder),
      isTrue,
    );
    expect(
      await PlaceholderPortraitProbe.mightBeFlatPlaceholder(real),
      isFalse,
    );
  });

  testWidgets('a cold card never paints the flat colour first', (tester) async {
    // Nothing probed yet: the first frame must not draw the picture, for a
    // placeholder or a real portrait, until the probe has answered.
    await tester.pumpWidget(_card(placeholder));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);

    await tester.pumpWidget(_card(real));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets(
    'Home shows the person icon for a card with only the placeholder',
    (tester) async {
      // Probe on real time first (file reads and the decode isolate do not
      // run under the widget test's fake clock); the card then paints from
      // the cached answer, as it does on every rebuild after the first.
      await tester.runAsync(() async {
        await PlaceholderPortraitProbe.check(placeholder, version: 0);
        await PlaceholderPortraitProbe.check(real, version: 0);
      });

      await tester.pumpWidget(_card(placeholder));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(_card(real));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
    },
  );

  test(
    'the phone library never waits on a probe, then refetches once',
    () async {
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

      final facade = CharacterFacade(db, storage, null, null, null);
      var refreshes = 0;
      final found = Completer<void>();
      facade.onPlaceholderPortraitsFound = () {
        refreshes++;
        if (!found.isCompleted) found.complete();
      };

      Map<String, dynamic> row(List<Map<String, dynamic>> rows, String name) =>
          rows.firstWhere((r) => r['name'] == name);

      // Cold: the list answers at once, counting the unknown picture as real.
      final cold = await facade.list();
      expect(row(cold, 'Juniper')['placeholderPortrait'], isFalse);
      expect(refreshes, 0);

      // The background probe finds the placeholder and asks for a refetch.
      await found.future.timeout(const Duration(seconds: 10));
      final warm = await facade.list();
      // Both still have a card file; only the placeholder is flagged.
      expect(row(warm, 'Juniper')['hasAvatar'], isTrue);
      expect(row(warm, 'Juniper')['placeholderPortrait'], isTrue);
      expect(row(warm, 'Marlow')['hasAvatar'], isTrue);
      expect(row(warm, 'Marlow')['placeholderPortrait'], isFalse);

      // Everything is known now: no further refetch requests.
      await facade.list();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(refreshes, 1);
    },
  );
}
