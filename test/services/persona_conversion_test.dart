// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character ↔ persona conversion (SillyTavern's "Convert to Persona" and its
// reverse). Through the real persona service and database: what a persona
// made from a card holds, that its picture is a real copy, and what a
// character made from a persona starts with.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late UserPersonaService personas;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai_persona_convert_');
    db = AppDatabase.forTesting(sameIsolate: true);
    personas = UserPersonaService(db);
    final waiting = Stopwatch()..start();
    while (personas.personas.isEmpty) {
      if (waiting.elapsed > const Duration(seconds: 20)) {
        fail('the persona service never loaded its personas');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  tearDown(() async {
    personas.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('swapping macros trades {{char}} and {{user}} in one pass', () {
    expect(
      PersonaConversion.swapCharUserMacros(
        '{{char}} is {{user}}\'s neighbour. {{Char}} waves at {{USER}}.',
      ),
      '{{user}} is {{char}}\'s neighbour. {{user}} waves at {{char}}.',
    );
    expect(PersonaConversion.hasCharUserMacros('No macros here.'), isFalse);
  });

  test('a character becomes a persona with its text, birthday and a copied '
      'portrait, and the card is left alone', () async {
    final portrait = p.join(root.path, 'card.png');
    await File(
      portrait,
    ).writeAsBytes(img.encodePng(img.Image(width: 4, height: 3)));
    final card = CharacterCard(
      name: 'Mabel',
      description: '{{char}} lives next door to {{user}}.',
      personality: 'Nosy but kind.',
      scenario: 'A summer evening on the porch.',
      firstMessage: 'Evening!',
      frontPorchExtensions: FrontPorchExtensions(birthday: '1990-06-14'),
    )..imagePath = portrait;
    final defaultBefore = personas.defaultPersona.id;
    final activeBefore = personas.persona.id;

    final persona = await PersonaConversion.createPersonaFromCharacter(
      card,
      personas: personas,
      swapMacros: true,
      avatarDir: p.join(root.path, 'persona_avatars'),
    );

    expect(persona.name, 'Mabel');
    expect(persona.title, isEmpty);
    expect(
      persona.persona,
      '{{user}} lives next door to {{char}}.\n\nPersonality: Nosy but kind.',
    );
    expect(persona.birthday, '1990-06-14');
    // Only joins the list: who you are, now and in new chats, stays put.
    expect(personas.defaultPersona.id, defaultBefore);
    expect(personas.persona.id, activeBefore);
    expect(persona.id, isNot(defaultBefore));
    final copied = persona.avatarPath;
    expect(copied, isNotNull);
    expect(copied, isNot(portrait));
    expect(p.isWithin(p.join(root.path, 'persona_avatars'), copied!), isTrue);
    final pixels = img.decodePng(await File(copied).readAsBytes())!;
    expect([pixels.width, pixels.height], [4, 3]);
    expect(card.description, '{{char}} lives next door to {{user}}.');

    final row = (await db.getAllPersonas()).firstWhere(
      (r) => r.id == persona.id,
    );
    expect(row.persona, persona.persona);
    expect(row.avatarPath, copied);
    expect(row.isActive, isFalse);
  });

  test('a second persona of the same name is told apart by its title, and '
      'macros stay when not swapped', () async {
    final card = CharacterCard(
      name: 'User',
      description: '{{char}} and {{user}}',
    );
    final persona = await PersonaConversion.createPersonaFromCharacter(
      card,
      personas: personas,
      swapMacros: false,
    );
    expect(persona.title, 'User (from character)');
    expect(persona.persona, '{{char}} and {{user}}');
    expect(persona.avatarPath, isNull);
  });

  test('a persona seeds a character with its name, swapped text, birthday '
      'and picture; AI Assist gets them as its brief', () {
    final seed = PersonaConversion.characterSeedFromPersona(
      UserPersona(
        id: 'p1',
        name: 'Jo',
        persona: '{{user}} keeps bees for {{char}}.',
        avatarPath: '/pics/jo.png',
        birthday: '1988-03-02',
      ),
      swapMacros: true,
    );
    expect(seed.name, 'Jo');
    expect(seed.description, '{{char}} keeps bees for {{user}}.');
    expect(seed.birthday, '1988-03-02');
    expect(seed.portraitPath, '/pics/jo.png');
    expect(seed.aiConcept, contains('{{char}} keeps bees for {{user}}.'));
    expect(seed.aiConcept, contains('Birthday: 1988-03-02'));
  });
}
