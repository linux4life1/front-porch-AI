// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('recap kind is recap; a typed compact prefix stays a user line', () {
    const recap = WaifuMessage.recap(
      '$kWaifuCompactPrefix\nEdited PageLayoutEngine.swift.',
    );
    const typed = WaifuMessage.user(
      '$kWaifuCompactPrefix\nI typed this myself.',
    );
    const user = WaifuMessage.user('keep going');
    const iris = WaifuMessage.assistant('On it.');
    expect(recap.kind, WaifuMsgKind.recap);
    expect(recap.hidden, isTrue);
    expect(recap.isUser, isFalse);
    expect(waifuIsPromptRecap(recap), isTrue);
    expect(typed.kind, WaifuMsgKind.user);
    expect(waifuIsPromptRecap(typed), isFalse);
    expect(
      waifuPromptSpeech(recap, 'Iris', preserveThinking: false),
      startsWith('Session recap'),
    );
    expect(
      waifuPromptSpeech(typed, 'Iris', preserveThinking: false),
      startsWith('User:'),
    );
    expect(
      waifuPromptSpeech(user, 'Iris', preserveThinking: false),
      'User: keep going',
    );
    expect(
      waifuPromptSpeech(iris, 'Iris', preserveThinking: false),
      'Iris: On it.',
    );
  });

  test('tool kind is tagged, not spoken as Iris', () {
    const tool = WaifuMessage.tool(
      name: 'write',
      output: 'wrote PageTurn.swift',
      ok: true,
    );
    expect(tool.kind, WaifuMsgKind.tool);
    expect(tool.isUser, isFalse);
    expect(tool.hidden, isFalse);
    expect(
      waifuPromptSpeech(tool, 'Iris', preserveThinking: false),
      '[tool write ok]\nwrote PageTurn.swift',
    );
  });

  test('load heals hidden recap but not a typed compact prefix', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_kind_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final folder = '${dir.path}/proj';
    await Directory('${dir.path}/sessions').create(recursive: true);
    final slug = waifuSessionSlug(folder);
    await File('${dir.path}/sessions/$slug.json').writeAsString(
      '{"title":"t","folderRoot":"$folder","mode":"build",'
      '"coworker":{"name":"Iris","personality":"","description":"",'
      '"systemPrompt":""},"transcript":['
      '{"isUser":true,"hidden":true,'
      '"text":"$kWaifuCompactPrefix\\nEdited the renderer."},'
      '{"isUser":true,'
      '"text":"$kWaifuCompactPrefix\\nI typed this myself."},'
      '{"kind":"recap","text":"$kWaifuCompactPrefix\\nKind recap."}'
      ']}',
    );
    final loaded = await WaifuStore(dir.path).loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.transcript, hasLength(3));
    expect(loaded.transcript[0].kind, WaifuMsgKind.recap);
    expect(loaded.transcript[0].isUser, isFalse);
    expect(loaded.transcript[1].kind, WaifuMsgKind.user);
    expect(loaded.transcript[1].isUser, isTrue);
    expect(waifuIsPromptRecap(loaded.transcript[1]), isFalse);
    expect(loaded.transcript[2].kind, WaifuMsgKind.recap);
    expect(
      waifuPromptSpeech(loaded.transcript[1], 'Iris', preserveThinking: false),
      startsWith('User:'),
    );
  });

  test('hidden ctor still builds a recap so old tests keep compiling', () {
    const recap = WaifuMessage(
      isUser: true,
      hidden: true,
      text: '$kWaifuCompactPrefix\nEdited.',
    );
    expect(recap.kind, WaifuMsgKind.recap);
    expect(recap.isUser, isFalse);
  });
}
