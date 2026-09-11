// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
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
}
