// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

void main() {
  late V2CardService service;
  late String tempDir;

  setUp(() {
    service = V2CardService();
    tempDir = Directory.systemTemp.createTempSync('fpai_v2test_').path;
  });

  tearDown(() {
    try {
      Directory(tempDir).deleteSync(recursive: true);
    } catch (_) {}
  });

  group('V2CardService - PNG Round-Trip', () {
    test('round-trip preserves basic fields', () async {
      final card = CharacterCard(
        name: 'Test Character',
        description: 'A test character for PNG round-trip testing',
        personality: 'Friendly and helpful',
        scenario: 'In a test world',
        firstMessage: 'Hello, traveler!',
        mesExample: 'Example dialogue here',
        systemPrompt: 'Be nice',
        postHistoryInstructions: 'Keep responses short',
      );

      final outputPath = '$tempDir/basic_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.name, card.name);
      expect(loaded.description, card.description);
      expect(loaded.personality, card.personality);
      expect(loaded.scenario, card.scenario);
      expect(loaded.firstMessage, card.firstMessage);
      expect(loaded.mesExample, card.mesExample);
      expect(loaded.systemPrompt, card.systemPrompt);
      expect(loaded.postHistoryInstructions, card.postHistoryInstructions);
    });

    test('round-trip preserves FrontPorch extensions', () async {
      final card = CharacterCard(
        name: 'Realism Character',
        personality: 'Has realism',
        firstMessage: 'Greetings',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 42,
          trustLevel: 15,
          dayCount: 7,
          timeOfDay: 'night',
          characterEmotion: 'happy',
          emotionIntensity: 'strong',
          chaosModeEnabled: true,
          currentTask: 'Guard the gate',
        ),
      );

      final outputPath = '$tempDir/extensions_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.frontPorchExtensions, isNotNull);
      expect(loaded.frontPorchExtensions!.realismEnabled, true);
      expect(loaded.frontPorchExtensions!.shortTermBond, 42);
      expect(loaded.frontPorchExtensions!.trustLevel, 15);
      expect(loaded.frontPorchExtensions!.dayCount, 7);
      expect(loaded.frontPorchExtensions!.timeOfDay, 'night');
      expect(loaded.frontPorchExtensions!.characterEmotion, 'happy');
      expect(loaded.frontPorchExtensions!.emotionIntensity, 'strong');
      expect(loaded.frontPorchExtensions!.chaosModeEnabled, true);
      expect(loaded.frontPorchExtensions!.currentTask, 'Guard the gate');
    });

    test('round-trip preserves lorebook', () async {
      final card = CharacterCard(
        name: 'Lore Character',
        personality: 'Knows things',
        lorebook: Lorebook(entries: [
          LorebookEntry(name: 'World Lore', key: 'magic', content: 'Magic exists'),
          LorebookEntry(name: 'Character Lore', key: 'sword', content: 'Wields a sword'),
        ]),
      );

      final outputPath = '$tempDir/lorebook_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.lorebook, isNotNull);
      expect(loaded.lorebook!.entries.length, 2);
      expect(loaded.lorebook!.entries[0].name, 'World Lore');
      expect(loaded.lorebook!.entries[1].name, 'Character Lore');
    });

    test('round-trip preserves alternate greetings', () async {
      final card = CharacterCard(
        name: 'Greeting Character',
        firstMessage: 'Hello!',
        alternateGreetings: ['Hi there!', 'Hey!', 'Greetings!'],
      );

      final outputPath = '$tempDir/greetings_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.alternateGreetings, ['Hi there!', 'Hey!', 'Greetings!']);
    });

    test('round-trip preserves tags and world names', () async {
      final card = CharacterCard(
        name: 'Tagged Character',
        tags: ['fantasy', 'magic', 'dragon'],
        worldNames: ['Fantasy Realm', 'Dragon Keep'],
      );

      final outputPath = '$tempDir/tags_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.tags, ['fantasy', 'magic', 'dragon']);
      expect(loaded!.worldNames, ['Fantasy Realm', 'Dragon Keep']);
    });

    test('round-trip preserves system prompt and post history', () async {
      final card = CharacterCard(
        name: 'Prompt Character',
        systemPrompt: 'You are a helpful assistant.',
        postHistoryInstructions: 'Maintain character voice.',
      );

      final outputPath = '$tempDir/prompts_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.systemPrompt, 'You are a helpful assistant.');
      expect(loaded!.postHistoryInstructions, 'Maintain character voice.');
    });

    test('round-trip preserves mesExample', () async {
      final card = CharacterCard(
        name: 'Example Character',
        mesExample: '''
{{char}}: Hello there, friend!
{{user}}: Hi! How are you?
{{char}}: I'm doing well, thank you for asking!
''',
      );

      final outputPath = '$tempDir/mesexample_test.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.mesExample, card.mesExample);
    });

    test('saveCardAsPng creates PNG when no source image', () async {
      final card = CharacterCard(name: 'No Image Character');
      final outputPath = '$tempDir/no_source.png';
      await service.saveCardAsPng(card, outputPath, null);

      final file = File(outputPath);
      expect(await file.exists(), true);
      final bytes = await file.readAsBytes();
      expect(bytes.isNotEmpty, true);
    });

    test('saveCardAsPng uses source image when provided', () async {
      // Create a source image
      final sourceImg = img.Image(width: 100, height: 100);
      img.fill(sourceImg, color: img.ColorRgb8(255, 0, 0));
      final sourcePath = '$tempDir/source.png';
      final sourceFile = File(sourcePath);
      await sourceFile.writeAsBytes(img.encodePng(sourceImg)!);

      final card = CharacterCard(name: 'With Image Character');
      final outputPath = '$tempDir/with_source.png';
      await service.saveCardAsPng(card, outputPath, sourcePath);

      final file = File(outputPath);
      expect(await file.exists(), true);
    });

    test('readCard throws for non-existent file', () async {
      expect(() => service.readCard('$tempDir/nonexistent.png'), throwsA(isA<PathNotFoundException>()));
    });

    test('readCard returns null for invalid PNG', () async {
      final invalidPath = '$tempDir/invalid.png';
      await File(invalidPath).writeAsString('not a png file at all');
      final loaded = await service.readCard(invalidPath);
      expect(loaded, isNull);
    });

    test('readCard returns null for PNG without chara chunk', () async {
      final plainImg = img.Image(width: 50, height: 50);
      img.fill(plainImg, color: img.ColorRgb8(0, 0, 255));
      final noCharaPath = '$tempDir/no_chara.png';
      await File(noCharaPath).writeAsBytes(img.encodePng(plainImg)!);

      final loaded = await service.readCard(noCharaPath);
      expect(loaded, isNull);
    });

    test('full round-trip with all fields', () async {
      final card = CharacterCard(
        name: 'Full Test Character',
        description: 'A comprehensive test character with all possible fields populated',
        personality: 'Brave, clever, and slightly mischievous',
        scenario: 'During a grand festival in a medieval city',
        firstMessage: 'The festival lights dance across the square as you approach.',
        mesExample: '{{char}}: Welcome to the festival!\n{{user}}: Thank you!',
        systemPrompt: 'You are a festival guide.',
        postHistoryInstructions: 'Describe the atmosphere.',
        alternateGreetings: ['The festival is lively tonight!', 'Care to join the celebration?'],
        tags: ['fantasy', 'festival', 'guide'],
        lorebook: Lorebook(entries: [
          LorebookEntry(name: 'Festival Lore', key: 'festival', content: 'Annual celebration'),
        ]),
        worldNames: ['Festival City'],
        ttsVoice: 'en_us',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 30,
          dayCount: 3,
          timeOfDay: 'evening',
        ),
        rawExtensions: {'third_party': 'some_data'},
      );

      final outputPath = '$tempDir/full_roundtrip.png';
      await service.saveCardAsPng(card, outputPath, null);

      final loaded = await service.readCard(outputPath);
      expect(loaded, isNotNull);
      expect(loaded!.name, card.name);
      expect(loaded.description, card.description);
      expect(loaded.personality, card.personality);
      expect(loaded.scenario, card.scenario);
      expect(loaded.firstMessage, card.firstMessage);
      expect(loaded.mesExample, card.mesExample);
      expect(loaded.systemPrompt, card.systemPrompt);
      expect(loaded.postHistoryInstructions, card.postHistoryInstructions);
      expect(loaded.alternateGreetings, card.alternateGreetings);
      expect(loaded.tags, card.tags);
      expect(loaded.lorebook, isNotNull);
      expect(loaded.lorebook!.entries.length, 1);
      expect(loaded.worldNames, card.worldNames);
      expect(loaded.ttsVoice, card.ttsVoice);
      expect(loaded.frontPorchExtensions, isNotNull);
      expect(loaded.frontPorchExtensions!.realismEnabled, true);
      expect(loaded.rawExtensions, isNotNull);
      expect(loaded.rawExtensions!['third_party'], 'some_data');
    });
  });
}
