// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/services/persona/user_persona.dart';

/// Build a minimal in-memory .byaf ZIP archive and write it to [dir].
/// [scenario] is merged over the spec-shaped defaults below.
Future<String> _writeByaf(
  Directory dir, {
  Map<String, dynamic> scenario = const {},
}) async {
  final scenarioJson = <String, dynamic>{
    'schemaVersion': 1,
    'formattingInstructions':
        'Text transcript of a chat between {user} and {character}.',
    'narrative': '{character} greets {user} on the porch.',
    'firstMessages': [
      {'text': 'Hello {user}!'},
    ],
    'exampleMessages': <dynamic>[],
    'messages': <dynamic>[],
    'temperature': 1.2,
    'minP': 0.1,
    'minPEnabled': true,
    'topP': 0.9,
    'topK': 30,
    'repeatPenalty': 1.05,
    'repeatLastN': 256,
    ...scenario,
  };
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'characters': ['characters/char1/character.json'],
          'scenarios': ['scenarios/scenario1.json'],
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'characters/char1/character.json',
        jsonEncode({
          'displayName': 'Aria',
          'persona': '{character} is a lighthouse keeper.',
        }),
      ),
    )
    ..addFile(
      ArchiveFile.string('scenarios/scenario1.json', jsonEncode(scenarioJson)),
    );
  final path = '${dir.path}/test.byaf';
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}

void main() {
  late Directory tempDir;
  final service = ByafService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('byaf_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('parseByaf reads example messages and model settings', () async {
    final path = await _writeByaf(
      tempDir,
      scenario: {
        'exampleMessages': [
          {'characterID': 'char1', 'text': 'Storms make honest sailors.'},
          {
            'characterID': 'char1',
            'text':
                '#{user}: Any ships tonight?\n'
                '#{character}: *scans the horizon* None yet.',
          },
        ],
      },
    );

    final preview = await service.parseByaf(path);
    expect(preview.name, 'Aria');
    expect(preview.exampleMessages, hasLength(2));
    expect(preview.modelSettings['temperature'], 1.2);
    expect(preview.modelSettings['minP'], 0.1);
    expect(preview.modelSettings['repeatLastN'], 256);
  });

  test('minPEnabled=false zeroes the imported min-p', () async {
    final path = await _writeByaf(
      tempDir,
      scenario: {'minP': 0.15, 'minPEnabled': false},
    );
    final preview = await service.parseByaf(path);
    expect(preview.modelSettings['minP'], 0.0);
  });

  test('toCharacterCard builds a V2 mes_example block', () async {
    final path = await _writeByaf(
      tempDir,
      scenario: {
        'exampleMessages': [
          {'characterID': 'char1', 'text': 'Storms make honest sailors.'},
          {
            'characterID': 'char1',
            'text':
                '#{user}: Any ships tonight?\n'
                '#{character}: *scans the horizon* None yet.',
          },
        ],
      },
    );

    final card = service.toCharacterCard(await service.parseByaf(path));
    expect(card.mesExample, startsWith('<START>\n'));
    // Unattributed text gets the character speaker prefix.
    expect(card.mesExample, contains('{{char}}: Storms make honest sailors.'));
    // Backyard `#` turn markers are stripped; placeholders converted.
    expect(card.mesExample, contains('{{user}}: Any ships tonight?'));
    expect(
      card.mesExample,
      contains('{{char}}: *scans the horizon* None yet.'),
    );
    expect(card.mesExample, isNot(contains('#')));
    expect(card.mesExample, isNot(contains('{character}')));
  });

  test('toCharacterCard leaves mes_example empty without examples', () async {
    final path = await _writeByaf(tempDir);
    final card = service.toCharacterCard(await service.parseByaf(path));
    expect(card.mesExample, isEmpty);
  });

  test('toGenerationSettings maps Backyard values to overrides', () async {
    final path = await _writeByaf(tempDir);
    final settings = service.toGenerationSettings(
      await service.parseByaf(path),
    );
    expect(settings, isNotNull);
    expect(settings!.temperature, 1.2);
    expect(settings.minP, 0.1);
    expect(settings.topP, 0.9);
    expect(settings.topK, 30);
    expect(settings.repeatPenalty, 1.05);
    expect(settings.repeatPenaltyTokens, 256);
    // Unset knobs stay null so they inherit the app's global defaults.
    expect(settings.maxLength, isNull);
    expect(settings.dryMultiplier, isNull);
  });

  test('toGenerationSettings returns null when no settings present', () async {
    final path = await _writeByaf(
      tempDir,
      scenario: {
        'temperature': 'invalid',
        'minP': null,
        'minPEnabled': true,
        'topP': null,
        'topK': null,
        'repeatPenalty': null,
        'repeatLastN': null,
      },
    );
    final settings = service.toGenerationSettings(
      await service.parseByaf(path),
    );
    expect(settings, isNull);
  });
  // Backyard's export shape for a turn the user regenerated: the second
  // output was the one on screen (latest activeTimestamp).
  final regeneratedChat = <String, dynamic>{
    'messages': [
      {
        'type': 'ai',
        'outputs': [
          {
            'activeTimestamp': '2025-02-27T10:07:34.471Z',
            'createdAt': '2025-02-27T10:07:34.474Z',
            'text': '*Aria shrugs.* Maybe tomorrow.',
          },
          {
            'activeTimestamp': '2025-02-27T10:07:42.986Z',
            'createdAt': '2025-02-27T10:07:42.989Z',
            'text': '*Aria nods and lights the lamp.*',
          },
        ],
      },
      {
        'type': 'human',
        'createdAt': '2025-02-27T10:08:29.854Z',
        'text': '"Good night," I say.',
      },
    ],
  };

  test(
    'parseByaf keeps every regeneration and lands on the shown one',
    () async {
      final path = await _writeByaf(tempDir, scenario: regeneratedChat);
      final preview = await service.parseByaf(path);
      expect(preview.messages, hasLength(2));
      final ai = preview.messages.first;
      expect(ai.swipes, [
        '*Aria shrugs.* Maybe tomorrow.',
        '*Aria nods and lights the lamp.*',
      ]);
      expect(ai.activeIndex, 1);
      expect(ai.text, '*Aria nods and lights the lamp.*');
    },
  );

  test('importSession opens with the greeting, keeps regenerations as '
      'swipes and speaks as the persona', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final path = await _writeByaf(tempDir, scenario: regeneratedChat);
    final preview = await service.parseByaf(path);
    final card = service.toCharacterCard(preview)..dbId = 'char-1';
    final persona = UserPersona(id: 'p-rowan', name: 'Rowan');

    await service.importSession(db, preview, card, persona: persona);

    final sessions = await db.getSessionsForCharacter('char-1');
    expect(sessions, hasLength(1));
    expect(sessions.single.userPersonaId, 'p-rowan');
    final rows = await db.getMessagesForSession(sessions.single.id);
    expect(rows, hasLength(3));

    // The scenario's opening message, names filled in like a new chat.
    expect(rows[0].isUser, isFalse);
    expect(rows[0].sender, 'Aria');
    expect(jsonDecode(rows[0].swipes), ['Hello Rowan!']);

    // Both Backyard outputs survive; the shown one is active.
    expect(jsonDecode(rows[1].swipes), hasLength(2));
    expect(rows[1].swipeIndex, 1);

    // The user's line is the persona's, not "User".
    expect(rows[2].isUser, isTrue);
    expect(rows[2].sender, 'Rowan');
    expect(jsonDecode(rows[2].metadata!), {'user_persona_id': 'p-rowan'});
  });

  test(
    'importSession does not repeat a greeting the history opens with',
    () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final path = await _writeByaf(
        tempDir,
        scenario: {
          'messages': [
            {
              'type': 'ai',
              'outputs': [
                {'text': 'Hello {user}!'},
              ],
            },
          ],
        },
      );
      final preview = await service.parseByaf(path);
      final card = service.toCharacterCard(preview)..dbId = 'char-2';
      await service.importSession(db, preview, card);
      final sessions = await db.getSessionsForCharacter('char-2');
      final rows = await db.getMessagesForSession(sessions.single.id);
      expect(rows, hasLength(1));
    },
  );
  group('recommendByafPersonaId', () {
    ByafChatMessage ai(String t) => ByafChatMessage(type: 'ai', swipes: [t]);
    ByafChatMessage me(String t) => ByafChatMessage(type: 'human', swipes: [t]);
    final rowan = UserPersona(id: 'p-rowan', name: 'Rowan');
    final sam = UserPersona(id: 'p-sam', name: 'Sam');
    final plain = UserPersona(id: 'p-user', name: 'User');

    test('names the persona the chat calls the user, any case', () {
      final chat = [
        ai("*Juniper grins.*\nYou worry too much, rowan."),
        me('"Well done," rowan says to Juniper.'),
      ];
      expect(recommendByafPersonaId(chat, [plain, sam, rowan]), 'p-rowan');
    });

    test('counts whole words only', () {
      // "Samantha" and "sample" are not Sam.
      final chat = [ai('Samantha took a sample.')];
      expect(recommendByafPersonaId(chat, [sam]), isNull);
    });

    test('a tie between different names, or no hits, recommends nobody', () {
      expect(
        recommendByafPersonaId([ai('Sam met Rowan.')], [sam, rowan]),
        isNull,
      );
      expect(
        recommendByafPersonaId([ai('Nobody here.')], [sam, rowan]),
        isNull,
      );
    });

    test('regenerations count too', () {
      final chat = [
        ByafChatMessage(
          type: 'ai',
          swipes: ['Hi Sam.', 'Hello again, Rowan. Rowan?'],
        ),
      ];
      expect(recommendByafPersonaId(chat, [sam, rowan]), 'p-rowan');
    });

    test('among same-named personas the default wins', () {
      final otherSam = UserPersona(id: 'p-sam-2', name: 'Sam');
      final chat = [ai('Morning, Sam.')];
      expect(
        recommendByafPersonaId(chat, [sam, otherSam], defaultId: 'p-sam-2'),
        'p-sam-2',
      );
      expect(recommendByafPersonaId(chat, [sam, otherSam]), 'p-sam');
    });
  });
  // A synthetic archive shaped exactly like the published BYAF v1 schemas
  // (github.com/backyardai/byaf, schemas/v1): every required key, nothing
  // extra, Backyard's folder layout and image paths. Invented content only.
  // If the importer is ever revisited, these pin what an export carries.
  group('BYAF v1 spec-shaped archive', () {
    const at = '2025-02-27T10:00:00.000Z';
    final manifest = <String, dynamic>{
      'schemaVersion': 1,
      'createdAt': '2025-07-03T09:11:40.283Z',
      'author': {
        'name': 'Fixture Author',
        'backyardURL': 'https://example.com/u',
      },
      'characters': ['characters/juniper1/character.json'],
      'scenarios': ['scenarios/scenario1.json'],
    };
    final character = <String, dynamic>{
      'schemaVersion': 1,
      'id': 'juniper1',
      'name': 'Juniper',
      'displayName': 'Juniper Fixture',
      'isNSFW': false,
      'persona': '{character} is a lighthouse painter who likes {user}.',
      'createdAt': at,
      'updatedAt': at,
      'loreItems': [
        {'key': 'pier', 'value': '{character} paints at the old pier.'},
      ],
      'images': [
        {'path': 'images/portrait.png', 'label': 'Portrait'},
        {'path': 'images/smile.png', 'label': 'Smiling'},
      ],
    };
    final scenario = <String, dynamic>{
      'schemaVersion': 1,
      'title': 'Harbour evenings',
      'model': 'fixture-model.gguf',
      'formattingInstructions': 'Text transcript of {character} and {user}.',
      'minP': 0.1,
      'minPEnabled': true,
      'temperature': 1.2,
      'repeatPenalty': 1.05,
      'repeatLastN': 256,
      'topK': 30,
      'topP': 0.9,
      'exampleMessages': [
        {
          'characterID': 'juniper1',
          'text': '#{user}: Hi.\n#{character}: Oh! Hi.',
        },
      ],
      'canDeleteExampleMessages': true,
      'firstMessages': [
        {
          'characterID': 'juniper1',
          'text': '*{character} looks up.* Hi, {user}.',
        },
      ],
      'narrative': '{character} and {user} share a harbour.',
      'promptTemplate': 'ChatML',
      'grammar': null,
      'messages': [
        // Regenerated once; the second output is the one on screen.
        {
          'type': 'ai',
          'outputs': [
            {
              'createdAt': '2025-02-27T10:07:34.474Z',
              'updatedAt': '2025-02-27T10:07:34.474Z',
              'text': "*Juniper grins.* You worry too much, Rowan.",
              'activeTimestamp': '2025-02-27T10:07:34.471Z',
            },
            {
              'createdAt': '2025-02-27T10:07:42.989Z',
              'updatedAt': '2025-02-27T10:07:42.989Z',
              'text': '*Juniper laughs.* The lamp is lit!',
              'activeTimestamp': '2025-02-27T10:07:42.986Z',
            },
          ],
        },
        {
          'type': 'human',
          'createdAt': '2025-02-27T10:08:29.854Z',
          'updatedAt': '2025-02-27T10:08:29.856Z',
          'text': '"Well done," Rowan says to Juniper.',
        },
        // Regenerated, then the user swiped BACK to the first output.
        {
          'type': 'ai',
          'outputs': [
            {
              'createdAt': '2025-02-27T10:09:00.000Z',
              'updatedAt': '2025-02-27T10:09:00.000Z',
              'text': 'Thank you, Rowan.',
              'activeTimestamp': '2025-02-27T10:09:30.000Z',
            },
            {
              'createdAt': '2025-02-27T10:09:10.000Z',
              'updatedAt': '2025-02-27T10:09:10.000Z',
              'text': 'Thanks!',
              'activeTimestamp': '2025-02-27T10:09:10.000Z',
            },
          ],
        },
      ],
    };

    // A second Backyard chat with the same character: its own title,
    // opening message, sampler values and history. Same v1 keys.
    final scenario2 = <String, dynamic>{
      ...scenario,
      'title': 'Rainy night',
      'temperature': 0.7,
      'firstMessages': [
        {'characterID': 'juniper1', 'text': 'Rain again, {user}.'},
      ],
      'messages': [
        {
          'type': 'human',
          'createdAt': '2025-03-01T20:00:00.000Z',
          'updatedAt': '2025-03-01T20:00:00.000Z',
          'text': 'Rowan shakes out an umbrella.',
        },
        {
          'type': 'ai',
          'outputs': [
            {
              'createdAt': '2025-03-01T20:00:05.000Z',
              'updatedAt': '2025-03-01T20:00:05.000Z',
              'text': 'Tea is on, Rowan.',
              'activeTimestamp': '2025-03-01T20:00:05.000Z',
            },
          ],
        },
      ],
    };

    Future<String> writeArchive(Directory dir, {bool twoChats = false}) async {
      final pix = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mP4/vU9VsQwtCQAafG2wXWW5mYAAAAASUVORK5CYII=',
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              ...manifest,
              if (twoChats)
                'scenarios': [
                  'scenarios/scenario1.json',
                  'scenarios/scenario2.json',
                ],
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'characters/juniper1/character.json',
            jsonEncode(character),
          ),
        )
        ..addFile(
          ArchiveFile(
            'characters/juniper1/images/portrait.png',
            pix.length,
            pix,
          ),
        )
        ..addFile(
          ArchiveFile('characters/juniper1/images/smile.png', pix.length, pix),
        )
        ..addFile(
          ArchiveFile.string('scenarios/scenario1.json', jsonEncode(scenario)),
        );
      if (twoChats) {
        archive.addFile(
          ArchiveFile.string('scenarios/scenario2.json', jsonEncode(scenario2)),
        );
      }
      final path = '${dir.path}/spec.byaf';
      await File(path).writeAsBytes(ZipEncoder().encode(archive));
      return path;
    }

    late ByafService byaf;
    setUp(() => byaf = ByafService(getTemporaryDirectory: () async => tempDir));

    test('the fixture carries exactly the keys the v1 schemas allow', () {
      // additionalProperties is false everywhere but manifest.author: a key
      // drifting in or out here means the fixture no longer matches Backyard.
      expect(manifest.keys.toSet(), {
        'schemaVersion',
        'createdAt',
        'author',
        'characters',
        'scenarios',
      });
      expect(character.keys.toSet(), {
        'schemaVersion',
        'id',
        'name',
        'displayName',
        'isNSFW',
        'persona',
        'createdAt',
        'updatedAt',
        'loreItems',
        'images',
      });
      expect(scenario.keys.toSet(), {
        'schemaVersion',
        'title',
        'model',
        'formattingInstructions',
        'minP',
        'minPEnabled',
        'temperature',
        'repeatPenalty',
        'repeatLastN',
        'topK',
        'topP',
        'exampleMessages',
        'canDeleteExampleMessages',
        'firstMessages',
        'narrative',
        'promptTemplate',
        'grammar',
        'messages',
      });
      for (final m in scenario['messages'] as List) {
        final keys = (m as Map).keys.toSet();
        if (m['type'] == 'ai') {
          expect(keys, {'type', 'outputs'});
          for (final o in m['outputs'] as List) {
            expect((o as Map).keys.toSet(), {
              'createdAt',
              'updatedAt',
              'text',
              'activeTimestamp',
            });
          }
        } else {
          expect(keys, {'type', 'createdAt', 'updatedAt', 'text'});
        }
      }
    });

    test('parseByaf reads every part of the archive', () async {
      final preview = await byaf.parseByaf(await writeArchive(tempDir));
      expect(preview.name, 'Juniper Fixture');
      expect(preview.persona, contains('lighthouse painter'));
      expect(preview.loreItems.single.key, 'pier');
      expect(preview.galleryImagePaths, hasLength(2));
      expect(preview.portraitBytes, isNotNull);
      expect(preview.firstMessage, '*{character} looks up.* Hi, {user}.');
      expect(preview.narrative, '{character} and {user} share a harbour.');
      expect(preview.exampleMessages, hasLength(1));
      expect(preview.modelSettings['repeatLastN'], 256);

      expect(preview.messages.map((m) => m.type), ['ai', 'human', 'ai']);
      expect(preview.messages[0].swipes, hasLength(2));
      expect(preview.messages[0].activeIndex, 1);
      // The latest activeTimestamp wins even when it is the older output.
      expect(preview.messages[2].activeIndex, 0);
      expect(preview.messages[2].text, 'Thank you, Rowan.');

      // The chat-only read a batch import uses agrees with the full parse.
      final chat = await byaf.readChat('${tempDir.path}/spec.byaf');
      expect(chat.map((m) => m.text), preview.messages.map((m) => m.text));
    });

    test('toCharacterCard converts every Backyard placeholder', () async {
      final card = byaf.toCharacterCard(
        await byaf.parseByaf(await writeArchive(tempDir)),
      );
      for (final field in [
        card.description,
        card.scenario,
        card.firstMessage,
        card.systemPrompt,
        card.mesExample,
        card.lorebook!.entries.single.content,
      ]) {
        // A single-brace Backyard placeholder, not the V2 `{{user}}` it
        // becomes.
        expect(field, isNot(matches(r'(?<!\{)\{(character|user)\}(?!\})')));
      }
      expect(card.firstMessage, '*{{char}} looks up.* Hi, {{user}}.');
    });

    test('importSession writes the whole chat in order', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final preview = await byaf.parseByaf(await writeArchive(tempDir));
      final card = byaf.toCharacterCard(preview)..dbId = 'juniper-db';
      final rowan = UserPersona(id: 'p-rowan', name: 'Rowan');

      await byaf.importSession(
        db,
        preview,
        card,
        genSettings: byaf.toGenerationSettings(preview),
        persona: rowan,
      );

      final session = (await db.getSessionsForCharacter('juniper-db')).single;
      expect(session.userPersonaId, 'p-rowan');
      expect(session.generationSettings, isNotNull);
      final rows = await db.getMessagesForSession(session.id);
      expect(rows.map((r) => r.position), [0, 1, 2, 3]);
      expect(rows.map((r) => r.isUser), [false, false, true, false]);
      expect(jsonDecode(rows[0].swipes), [
        '*Juniper Fixture looks up.* Hi, Rowan.',
      ]);
      expect(jsonDecode(rows[1].swipes), hasLength(2));
      expect(rows[1].swipeIndex, 1);
      expect(rows[2].sender, 'Rowan');
      expect(rows[3].swipeIndex, 0);
    });

    test(
      'the persona the chat names is recommended (a guess, not proof)',
      () async {
        final preview = await byaf.parseByaf(await writeArchive(tempDir));
        final personas = [
          UserPersona(id: 'p-user', name: 'User'),
          UserPersona(id: 'p-rowan', name: 'Rowan'),
        ];
        expect(recommendByafPersonaId(preview.messages, personas), 'p-rowan');
      },
    );
    test('the second chat carries the same v1 keys', () {
      expect(scenario2.keys.toSet(), scenario.keys.toSet());
    });

    test(
      'parseByaf reads every chat in the archive, not just the first',
      () async {
        final path = await writeArchive(tempDir, twoChats: true);
        final preview = await byaf.parseByaf(path);
        expect(preview.chats, hasLength(2));
        expect(preview.chats[0].title, 'Harbour evenings');
        expect(preview.chats[1].title, 'Rainy night');
        expect(preview.chats[1].firstMessage, 'Rain again, {user}.');
        expect(preview.chats[1].modelSettings['temperature'], 0.7);
        expect(preview.chats[1].messages.map((m) => m.type), ['human', 'ai']);
        // The card itself still comes from the first chat.
        expect(preview.firstMessage, '*{character} looks up.* Hi, {user}.');
        expect(preview.modelSettings['temperature'], 1.2);
        // Counts and the persona guess see every chat's turns.
        expect(preview.messages, hasLength(5));
        expect(await byaf.readChat(path), hasLength(5));
      },
    );

    test('importSession writes one chat per Backyard chat', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final preview = await byaf.parseByaf(
        await writeArchive(tempDir, twoChats: true),
      );
      final card = byaf.toCharacterCard(preview)..dbId = 'juniper-two';
      final rowan = UserPersona(id: 'p-rowan', name: 'Rowan');

      final made = await byaf.importSession(
        db,
        preview,
        card,
        genSettings: byaf.toGenerationSettings(preview),
        persona: rowan,
      );

      expect(made, 2);
      final sessions = await db.getSessionsForCharacter('juniper-two');
      expect(sessions, hasLength(2));
      expect(sessions.map((x) => x.id).toSet(), hasLength(2));
      final byName = {for (final x in sessions) x.name: x};
      expect(byName.keys.toSet(), {'Harbour evenings', 'Rainy night'});
      for (final x in sessions) {
        expect(x.userPersonaId, 'p-rowan');
      }
      // Each chat keeps its own Backyard sampler values.
      expect(
        jsonDecode(byName['Rainy night']!.generationSettings!)['temperature'],
        0.7,
      );

      final first = await db.getMessagesForSession(
        byName['Harbour evenings']!.id,
      );
      expect(first, hasLength(4));
      final second = await db.getMessagesForSession(byName['Rainy night']!.id);
      expect(second.map((r) => r.isUser), [false, true, false]);
      expect(jsonDecode(second[0].swipes), ['Rain again, Rowan.']);
      expect(second[1].sender, 'Rowan');
    });

    test('a chat that never started imports nothing for it', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final preview = ByafImportPreview(
        name: 'Juniper',
        persona: '',
        chats: [
          const ByafChat(title: 'Untouched', firstMessage: 'Hello.'),
          ByafChat(
            title: 'Talked',
            messages: [
              ByafChatMessage(type: 'human', swipes: ['Hi.']),
            ],
          ),
        ],
      );
      final card = byaf.toCharacterCard(preview)..dbId = 'juniper-skip';
      expect(await byaf.importSession(db, preview, card), 1);
      final sessions = await db.getSessionsForCharacter('juniper-skip');
      expect(sessions.single.name, 'Talked');
    });
  });
}
