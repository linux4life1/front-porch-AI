// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('waifu_tokens_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('resume restores tokensUsed so the context bar is not 0/N', () async {
    final store = WaifuStore(dir.path);
    final folder = p.join(dir.path, 'Kabbage');
    final session = WaifuSession(
      folderRoot: folder,
      coworker: CharacterCard(name: 'Iris'),
      title: 'what does this project do',
    )..tokensUsed = 4321;
    session.transcript.add(
      const WaifuMessage(isUser: true, text: 'what does this project do'),
    );
    await store.saveLast(session);

    final loaded = await store.loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.tokensUsed, 4321);
    expect(loaded.transcript, isNotEmpty);

    final last = await store.loadLast();
    expect(last, isNotNull);
    expect(last!.tokensUsed, 4321);
  });

  test('resume restores chat theme overrides', () async {
    final store = WaifuStore(dir.path);
    final folder = p.join(dir.path, 'Kabbage');
    final session = WaifuSession(
      folderRoot: folder,
      coworker: CharacterCard(name: 'Iris'),
      themeOverrides: ChatThemeOverrides(
        themeId: 'sakura',
        userTextColor: '5D2A3E',
      ),
    );
    await store.saveLast(session);

    final loaded = await store.loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.themeOverrides.themeId, 'sakura');
    expect(loaded.themeOverrides.userTextColor, '5D2A3E');
  });

  test('old session JSON without tokensUsed still loads at 0', () async {
    final store = WaifuStore(dir.path);
    final folder = p.join(dir.path, 'Kabbage');
    await Directory(p.join(dir.path, 'sessions')).create(recursive: true);
    final slug = waifuSessionSlug(folder);
    await File(p.join(dir.path, 'sessions', '$slug.json')).writeAsString(
      '{"title":"old","folderRoot":"$folder","mode":"yolo",'
      '"coworker":{"name":"Iris","personality":"","description":"",'
      '"systemPrompt":""},"transcript":[]}',
    );
    final loaded = await store.loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.tokensUsed, 0);
  });
}
