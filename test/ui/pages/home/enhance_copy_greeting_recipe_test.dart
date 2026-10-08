// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AN "(ENHANCED)" COPY CARRIES THE GREETING RECIPE ENHANCE WROTE WITH (#370).
//
// AI Enhance saves its result as a duplicate of the original, and a
// duplicate copies the card's extension data, so the copy inherited the
// original creation's greeting recipe (Romantic, Long, its world lore) even
// when its greetings were Enhance's (a neutral tone, Enhance's length, no
// lore). A later rewrite on the copy, such as the phone's ?greetings=<copy>,
// then wrote in the wrong style. Here the real Enhance writes the greetings
// and the real review step saves the copy: taken greetings bring Enhance's
// recipe (and never the chat lines Enhance read); untaken ones leave the
// original's.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_review_body.dart';

const _lore = 'The tide-bell of Saltmere rings once at every dawn.';
const _chatLine = 'User: meet me at the old pier at midnight';

/// Answers each Enhance stage by what its prompt asks for.
class _EnhanceLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('Write an opening roleplay message')) {
      yield '*Aria Vale waits by the pier.* "You came after all."';
    } else if (p.contains('completely different meeting scenarios')) {
      yield '{"scenarios": ["a quiet morning in the lamp room"]}';
    } else {
      yield 'I keep the lamp lit. That is all anyone needs to know.';
    }
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'scripted-test';
}

void main() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_enh_docs_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late FolderService folders;
  late CharacterCard original;

  Future<void> setUpLibrary(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_enh_recipe_').path,
      );
      repo = CharacterRepository(db, storage);
      folders = FolderService(db);
      // A creator-made card: its recipe stamped as creation stamps it.
      original = CharacterCard(
        name: 'Aria Vale',
        description: '{{char}} keeps the lighthouse.',
        personality: 'Patient and dry.',
        scenario: '{{user}} climbs the tower stairs at dusk.',
        firstMessage: '*{{char}} trims the wick.* "You came."',
        alternateGreetings: const ['A storm on the jetty.'],
      );
      stampGreetingRecipe(
        original,
        const GreetingRecipe(
          greetingLength: 'Long (4-6 paragraphs)',
          tones: ['Neutral', 'Romantic'],
          worldLore: _lore,
        ),
      );
      await CharacterFacade(
        db,
        storage,
        null,
        null,
        repo,
      ).persistNewCard(original);
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        folders.dispose();
        repo.dispose();
        await db.close();
      });
    });
  }

  Future<CharacterCard> saveCopy(
    WidgetTester tester,
    EnhanceSelection selection,
  ) async {
    final enhanced = (await tester.runAsync(
      () => CharacterGenService(_EnhanceLlm()).enhanceCharacter(
        source: original,
        selection: selection,
        chatGrounding: _chatLine,
        greetingLength: 'Short (1-2 paragraphs)',
      ),
    ))!;
    final key = GlobalKey<EnhanceReviewBodyState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<FolderService>.value(value: folders),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: EnhanceReviewBody(
              key: key,
              original: original,
              enhanced: enhanced,
              selection: selection,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final copy = await tester.runAsync(() => key.currentState!.save());
    expect(copy, isNotNull, reason: 'the copy saved');
    return copy!;
  }

  testWidgets('taken greetings bring the recipe Enhance wrote them with', (
    tester,
  ) async {
    await setUpLibrary(tester);
    final copy = await saveCopy(
      tester,
      const EnhanceSelection(
        description: false,
        personality: false,
        exampleDialogue: false,
        greetings: true,
      ),
    );
    expect(copy.firstMessage, contains('waits by the pier'), reason: 'sanity');
    final recipe = readGreetingRecipe(copy)!;
    expect(recipe.tones, ['Neutral'], reason: 'Enhance writes in one tone');
    expect(recipe.greetingLength, 'Short (1-2 paragraphs)');
    expect(recipe.worldLore, isNull, reason: 'Enhance used no world lore');
    expect(recipe.characterContext, isEmpty);
    expect(
      copy.rawExtensions![kGreetingRecipeExtensionKey].toString(),
      isNot(contains('old pier')),
      reason: 'the chat Enhance read never travels on the card',
    );
    expect(readGreetingRecipe(original)!.tones, [
      'Neutral',
      'Romantic',
    ], reason: 'the original keeps its own');
  });

  testWidgets('untaken greetings keep the original recipe with them', (
    tester,
  ) async {
    await setUpLibrary(tester);
    final copy = await saveCopy(tester, const EnhanceSelection());
    expect(copy.firstMessage, original.firstMessage, reason: 'sanity');
    final recipe = readGreetingRecipe(copy)!;
    expect(recipe.tones, ['Neutral', 'Romantic']);
    expect(recipe.greetingLength, 'Long (4-6 paragraphs)');
    expect(recipe.worldLore, _lore);
  });
}
