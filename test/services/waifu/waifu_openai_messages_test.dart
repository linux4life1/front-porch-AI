// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('failed write is a tool-role message, not a user blob', () {
    final messages = waifuOpenAiMessages(
      folderName: '/tmp/porch',
      coworkerName: 'Iris',
      transcript: const [
        WaifuMessage.user('fix the curl'),
        WaifuMessage.tool(
          name: 'write',
          output: 'denied: path is outside the folder jail',
          ok: false,
          path: '../secret.txt',
          callId: 'waifu_write_1',
          args: {'path': '../secret.txt', 'contents': 'x'},
        ),
      ],
      todos: '',
      mentionBlock: '',
    );
    expect(messages.first['role'], 'user');
    expect(messages[1]['role'], 'user');
    expect(messages[2]['role'], 'assistant');
    final calls = messages[2]['tool_calls'] as List;
    expect(calls, isNotEmpty);
    expect((calls.first as Map)['id'], 'waifu_write_1');
    expect(messages[3]['role'], 'tool');
    expect(messages[3]['tool_call_id'], 'waifu_write_1');
    expect(messages[3]['content'], contains('FAILED'));
    expect(messages[3]['content'], contains('Disk was not changed'));
    expect(messages.any((m) => m['role'] == 'tool'), isTrue);
  });

  test('chat GenerationParams without chatMessages stays one user blob', () {
    const p = GenerationParams(prompt: 'hello', systemPrompt: 'sys');
    expect(p.chatMessages, isNull);
    expect(p.openAiMessages, hasLength(2));
    expect(p.openAiMessages[0]['role'], 'system');
    expect(p.openAiMessages[1]['role'], 'user');
    expect(p.openAiMessages[1]['content'], 'hello');
  });

  test('chatMessages + images puts the photo on the last user role', () {
    const original = [
      {'role': 'user', 'content': 'loop prefix'},
      {'role': 'user', 'content': '(photo)'},
      {'role': 'assistant', 'content': ''},
      {'role': 'tool', 'content': 'ok'},
    ];
    const p = GenerationParams(
      prompt: 'ignored',
      systemPrompt: 'sys',
      chatMessages: original,
      images: ['QUFB'],
    );
    final msgs = p.openAiMessages;
    expect(msgs[0]['role'], 'system');
    expect(msgs[1]['content'], 'loop prefix');
    expect(msgs[2]['role'], 'user');
    expect(msgs[2]['content'], [
      {'type': 'text', 'text': '(photo)'},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,QUFB'},
      },
    ]);
    expect(msgs[3]['role'], 'assistant');
    expect(msgs[4]['role'], 'tool');
    expect(original[1]['content'], '(photo)');
  });

  test('attachOpenAiImagesToLastUser no-ops without images or a user row', () {
    const users = [
      {'role': 'user', 'content': 'hi'},
    ];
    expect(attachOpenAiImagesToLastUser(users, null), same(users));
    expect(attachOpenAiImagesToLastUser(users, const []), same(users));
    expect(openAiContentWithImages('hi', const []), 'hi');
    const tools = [
      {'role': 'tool', 'content': 'ok'},
    ];
    expect(attachOpenAiImagesToLastUser(tools, const ['QUFB']), same(tools));
  });
}
