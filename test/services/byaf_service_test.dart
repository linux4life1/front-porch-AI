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
import 'package:front_porch_ai/services/byaf_service.dart';

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
}
