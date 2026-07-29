// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/storage_service.dart';

List<int> _solidPng({int r = 100, int g = 120, int b = 140}) {
  // Creator / V2 synthesizer size — isPlaceholderPortrait requires 400×600.
  final image = img.Image(width: 400, height: 600);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}

List<int> _variedPng() {
  final image = img.Image(width: 64, height: 64);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  // One different pixel so it is not a solid fill (and size ≠ 400×600).
  image.setPixelRgb(32, 32, 200, 50, 50);
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late StorageService storage;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('fpai_portrait_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tmp.path;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
  });

  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('hasUsablePortrait', () {
    test('false when imagePath is null or empty', () {
      final card = CharacterCard(name: 'NoPath');
      expect(hasUsablePortrait(card, storage), isFalse);
      card.imagePath = '';
      expect(hasUsablePortrait(card, storage), isFalse);
    });

    test('false when the resolved file is missing', () {
      final card = CharacterCard(
        name: 'Missing',
        imagePath: '${storage.charactersDir.path}/ghost.png',
      );
      expect(hasUsablePortrait(card, storage), isFalse);
    });

    test('true when the portrait file exists', () {
      final file = File('${storage.charactersDir.path}/real.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_variedPng());
      final card = CharacterCard(name: 'Real', imagePath: file.path);
      expect(hasUsablePortrait(card, storage), isTrue);
    });
  });

  group('isPlaceholderPortrait', () {
    test('true for solid-color creator placeholder', () async {
      final file = File('${storage.charactersDir.path}/ph.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_solidPng());
      final card = CharacterCard(name: 'Ph', imagePath: file.path);
      expect(await isPlaceholderPortrait(card, storage), isTrue);
    });

    test('false for a real (varied) image', () async {
      final file = File('${storage.charactersDir.path}/photo.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_variedPng());
      final card = CharacterCard(name: 'Photo', imagePath: file.path);
      expect(await isPlaceholderPortrait(card, storage), isFalse);
    });
  });

  group('bootstrapPortraitIfMissing', () {
    test('writes a portrait and updates imagePath when none exists', () async {
      final card = CharacterCard(name: 'Boot Me');
      var updates = 0;
      final real = _variedPng();
      final wrote = await bootstrapPortraitIfMissing(
        card: card,
        storage: storage,
        bytes: real,
        updateCharacter: (c) async {
          updates++;
          expect(c.imagePath, isNotNull);
          expect(File(c.imagePath!).existsSync(), isTrue);
        },
      );
      expect(wrote, isTrue);
      expect(updates, 1);
      expect(hasUsablePortrait(card, storage), isTrue);
    });

    test('overwrites a solid-color placeholder with the real image', () async {
      final existing = File('${storage.charactersDir.path}/keep.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_solidPng(r: 80, g: 90, b: 100));
      final card = CharacterCard(name: 'Keep', imagePath: existing.path);
      final real = _variedPng();
      var updates = 0;
      final wrote = await bootstrapPortraitIfMissing(
        card: card,
        storage: storage,
        bytes: real,
        updateCharacter: (_) async => updates++,
      );
      expect(wrote, isTrue);
      expect(updates, 1);
      expect(card.imagePath, existing.path); // in-place overwrite
      expect(existing.readAsBytesSync(), real);
      expect(await isPlaceholderPortrait(card, storage), isFalse);
    });

    test('is a no-op when a real portrait already exists', () async {
      final existing = File('${storage.charactersDir.path}/keep.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_variedPng());
      final before = existing.readAsBytesSync();
      final card = CharacterCard(name: 'Keep', imagePath: existing.path);
      var updates = 0;
      final wrote = await bootstrapPortraitIfMissing(
        card: card,
        storage: storage,
        bytes: _solidPng(),
        updateCharacter: (_) async => updates++,
      );
      expect(wrote, isFalse);
      expect(updates, 0);
      expect(card.imagePath, existing.path);
      expect(existing.readAsBytesSync(), before);
    });

    test('is a no-op for empty bytes', () async {
      final card = CharacterCard(name: 'Empty');
      final wrote = await bootstrapPortraitIfMissing(
        card: card,
        storage: storage,
        bytes: const [],
        updateCharacter: (_) async => fail('should not update'),
      );
      expect(wrote, isFalse);
      expect(card.imagePath, isNull);
    });

    test('is a no-op for non-image garbage bytes', () async {
      final card = CharacterCard(name: 'Garbage');
      final wrote = await bootstrapPortraitIfMissing(
        card: card,
        storage: storage,
        bytes: const [1, 2, 3, 4],
        updateCharacter: (_) async => fail('should not update'),
      );
      expect(wrote, isFalse);
      expect(card.imagePath, isNull);
    });
  });
}
