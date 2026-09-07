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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as p;

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_g_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('over-budget transcript is compacted without inventing files', () {
    final msgs = <WaifuMessage>[
      for (var i = 0; i < 40; i++)
        WaifuMessage(isUser: i.isEven, text: 'line $i ' * 20),
    ];
    final compact = waifuCompactTranscript(msgs, budgetChars: 200, keep: 4);
    expect(compact.length, lessThan(msgs.length));
    expect(compact.last.text, msgs.last.text);
    expect(compact.first.text.toLowerCase(), contains('recap'));
    expect(compact.first.text, isNot(contains('invented.txt')));
    expect(compact.first.text, isNot(contains('secret.py')));
  });

  test('resume restores folder, coworker, title, and transcript', () async {
    final storeDir = Directory(p.join(root.path, 'store'))..createSync();
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
      title: 'fix the empty-email test',
    );
    session.transcript.add(const WaifuMessage(isUser: true, text: 'add hello'));
    session.transcript.add(
      const WaifuMessage(isUser: false, text: 'Hmph. Done.'),
    );
    final store = WaifuStore(storeDir.path);
    await store.saveLast(session);

    final loaded = await store.loadLast();
    expect(loaded, isNotNull);
    expect(loaded!.folderRoot, session.folderRoot);
    expect(loaded.coworker.name, 'Mira');
    expect(loaded.coworker.personality, contains('tsundere'));
    expect(loaded.title, 'fix the empty-email test');
    expect(loaded.transcript, hasLength(2));
    expect(loaded.transcript.first.text, 'add hello');
    expect(loaded.mode, WaifuMode.yolo);
  });

  test('send compact+save uses the store and sets a title', () async {
    final storeDir = Directory(p.join(root.path, 'store'))..createSync();
    final store = WaifuStore(storeDir.path);
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'Hmph. Fine.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    final harness = WaifuHarness(session: session, llm: llm, store: store);
    await harness.send('add a hello.txt please');
    expect(session.title, isNotEmpty);
    expect(session.title, contains('hello'));
    final loaded = await store.loadLast();
    expect(loaded, isNotNull);
    expect(loaded!.folderRoot, root.path);
    expect(loaded.coworker.name, 'Mira');
  });

  test('saveLast does not dump firstMes or other card secrets', () async {
    final storeDir = Directory(p.join(root.path, 'store'))..createSync();
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(
        name: 'Mira',
        personality: 'tsundere',
        firstMessage: 'SECRET_GREETING',
        scenario: 'SECRET_SCENARIO',
      ),
      title: 'task',
    );
    final store = WaifuStore(storeDir.path);
    await store.saveLast(session);
    final raw = await File(p.join(storeDir.path, kWaifuLastFile)).readAsString();
    expect(raw, isNot(contains('SECRET_GREETING')));
    expect(raw, isNot(contains('SECRET_SCENARIO')));
    expect(raw, contains('tsundere'));
  });

  test('corrupt last_waifu.json loads as null', () async {
    final storeDir = Directory(p.join(root.path, 'store'))..createSync();
    File(p.join(storeDir.path, kWaifuLastFile)).writeAsStringSync('{not json');
    expect(await WaifuStore(storeDir.path).loadLast(), isNull);
  });

  test('waifuStoreDirectory is dataRoot/waifu', () {
    expect(
      p.equals(waifuStoreDirectory('/data'), p.join('/data', 'waifu')),
      isTrue,
    );
  });
}
