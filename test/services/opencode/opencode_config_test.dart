// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('OpenCode agent prompt is the card plus write-not-joke', () {
    final card = CharacterCard(
      name: 'Mira',
      personality: 'tsundere',
      description: 'sharp engineer',
      scenario: 'SCENARIO_MUST_NOT_APPEAR',
      firstMessage: 'FIRST_MESSAGE_MUST_NOT_APPEAR',
      mesExample: '{{char}}: Hmph.\n{{user}}: hi',
    );
    final prompt = buildWaifuOpenCodeAgentPrompt(card);
    expect(prompt, contains('Name: Mira'));
    expect(prompt, contains('Persona: tsundere'));
    expect(prompt, contains('If a joke and a write are both possible, write'));
    expect(prompt, contains('Do not mix lorebook, Needs, weather'));
    expect(prompt, isNot(contains('SCENARIO_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('FIRST_MESSAGE_MUST_NOT_APPEAR')));
  });

  test('config is isolated porch provider with waifu default agent', () {
    final map = buildOpenCodeConfigMap(
      agentPrompt: 'Name: Mira\nYou are a coding agent.',
      baseUrl: 'http://127.0.0.1:5001/v1',
      apiKey: 'x',
      modelId: 'local',
      permission: openCodePermissionMap(folderJail: true, yolo: false),
    );
    expect(map['default_agent'], 'waifu');
    expect(map['autoupdate'], isFalse);
    expect(map['model'], 'porch/current');
    expect(map['enabled_providers'], ['porch']);
    final porch = (map['provider'] as Map)['porch'] as Map;
    expect(porch['npm'], kOpenCodeCompatibleNpm);
    expect((porch['options'] as Map)['baseURL'], 'http://127.0.0.1:5001/v1');
    expect((porch['models'] as Map)['current']['id'], 'local');
    expect(porch.containsKey('api'), isFalse);
    final agent = map['agent'] as Map;
    expect(agent['waifu']['mode'], 'primary');
    expect(agent['waifu']['prompt'], contains('Name: Mira'));
    final perm = map['permission'] as Map;
    expect(perm['external_directory'], 'deny');
    expect(perm['edit'], 'ask');
    expect((perm['bash'] as Map)['rm -rf *'], 'deny');
  });

  test('yolo allows edits; disk does not deny external_directory', () {
    final yolo = openCodePermissionMap(folderJail: false, yolo: true);
    expect(yolo['edit'], 'allow');
    expect(yolo['external_directory'], 'allow');
  });

  test('plan mode selects the native plan agent', () {
    expect(openCodeAgentForMode(WaifuMode.plan), 'plan');
    expect(openCodeAgentForMode(WaifuMode.build), 'waifu');
    expect(openCodeAgentForMode(WaifuMode.yolo), 'waifu');
  });

  test('mcp servers are written into isolated config, not a Dart gym', () {
    final map = buildOpenCodeConfigMap(
      agentPrompt: 'Name: Mira',
      baseUrl: 'http://127.0.0.1:5001/v1',
      apiKey: 'x',
      modelId: 'local',
      permission: openCodePermissionMap(folderJail: true, yolo: false),
      mcp: {
        'docs': {
          'type': 'local',
          'command': ['npx', '-y', 'docs'],
          'enabled': true,
        },
      },
    );
    expect((map['mcp'] as Map)['docs']['type'], 'local');
    expect(map.containsKey('mcp'), isTrue);
  });

  test('Nano-GPT URL and model name land on openai-compatible porch', () {
    const fakeKey = 'sk-fake-nano';
    final svc = OpenRouterService(
      apiUrl: kNanoGptApiV1,
      apiKey: fakeKey,
      modelName: 'gpt-4o-mini',
    );
    final backend = openCodeBackendFromProvider(svc);
    expect(backend.baseUrl, kNanoGptApiV1);
    expect(backend.modelId, 'gpt-4o-mini');
    final map = buildOpenCodeConfigMap(
      agentPrompt: 'Name: Mira',
      baseUrl: backend.baseUrl,
      apiKey: backend.apiKey,
      modelId: backend.modelId,
      permission: openCodePermissionMap(folderJail: true, yolo: false),
    );
    expect(map['model'], 'porch/current');
    expect(map['enabled_providers'], ['porch']);
    final porch = (map['provider'] as Map)['porch'] as Map;
    expect(porch['npm'], kOpenCodeCompatibleNpm);
    final options = porch['options'] as Map;
    expect(options['baseURL'], kNanoGptApiV1);
    expect(options.containsKey('apiKey'), isTrue);
    expect((porch['models'] as Map)['current']['id'], 'gpt-4o-mini');
    expect((porch['models'] as Map)['current']['name'], 'gpt-4o-mini');
    expect(porch.containsKey('api'), isFalse);
  });

  test('OpenRouter slash model id stays in models.current.id', () {
    const fakeKey = 'sk-fake-or';
    final svc = OpenRouterService(
      apiUrl: kOpenRouterApiV1,
      apiKey: fakeKey,
      modelName: 'anthropic/claude-sonnet-4',
    );
    final backend = openCodeBackendFromProvider(svc);
    expect(backend.baseUrl, kOpenRouterApiV1);
    expect(backend.modelId, 'anthropic/claude-sonnet-4');
    final map = buildOpenCodeConfigMap(
      agentPrompt: 'Name: Mira',
      baseUrl: backend.baseUrl,
      apiKey: backend.apiKey,
      modelId: backend.modelId,
      permission: openCodePermissionMap(folderJail: true, yolo: false),
    );
    expect(map['model'], 'porch/current');
    final porch = (map['provider'] as Map)['porch'] as Map;
    expect(porch['npm'], kOpenCodeCompatibleNpm);
    expect((porch['options'] as Map)['baseURL'], kOpenRouterApiV1);
    expect(
      (porch['models'] as Map)['current']['id'],
      'anthropic/claude-sonnet-4',
    );
    expect(porch.containsKey('api'), isFalse);
  });
}
