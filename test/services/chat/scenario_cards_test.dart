// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/doors/turn/scenario_prompt.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/web/facade/character/character_card_edits.dart';
import 'package:front_porch_ai/ui/widgets/scenario_card_type_field.dart';

void main() {
  test(
    'empty-setting Scenario survives the normal web-to-V2 PNG/JSON path',
    () async {
      final dir = await Directory.systemTemp.createTemp('scenario_cards_');
      addTearDown(() => dir.delete(recursive: true));
      final card = newCharacterFromFields({
        'name': 'Crossroads Dispatch',
        'cardType': 'scenario',
        'facilitationRules': 'Ask where the player wants to start.',
        'firstMessage': 'Which trail would you like to explore?',
        'alternateGreetings': ['Where would you like the journey to begin?'],
      })!;
      card.rawExtensions!['opaque_test_key'] = {'enabled': true};
      final service = V2CardService();
      final png = p.join(dir.path, 'crossroads.png');
      final json = p.join(dir.path, 'crossroads.json');
      await service.saveCardAsPng(card, png, null);
      await service.saveCardAsJson(card, json);

      for (final reloaded in [
        await service.readCard(png),
        await service.readCardFromJsonFile(json),
      ]) {
        expect(reloaded, isNotNull);
        final copy = reloaded!;
        expect(copy.isScenarioCard, isTrue);
        expect(copy.scenario, isEmpty);
        expect(copy.facilitationRules, 'Ask where the player wants to start.');
        expect(copy.allGreetings, hasLength(2));
        applyCharacterFields(copy, {
          'name': 'Dispatch',
        }, needsSimDefault: false);
        expect(copy.isScenarioCard, isTrue);
        expect(copy.rawExtensions!['opaque_test_key'], {'enabled': true});
      }
    },
  );

  test(
    'existing fields do not infer type and opaque future types round trip',
    () {
      final card = CharacterCard(name: 'Archive', scenario: 'A forest');
      expect(card.isScenarioCard, isFalse);
      final unknown = {'version': 7, 'kind': 'scenario', 'future_rules': []};
      card.rawExtensions = {scenarioCardExtension: unknown};
      applyCharacterFields(card, {
        'cardType': 'character',
        'scenario': 'A shore',
      }, needsSimDefault: false);
      expect(card.hasUnsupportedCardMode, isTrue);
      expect(card.rawExtensions![scenarioCardExtension], unknown);
    },
  );

  test(
    'mode snapshot persists without generation overrides, by group member',
    () {
      final card = CharacterCard(
        name: 'Gantry',
        scenario: 'A lift stalled at dusk',
      )..setScenarioCard(true, 'Offer choices without taking one.');
      final snapshot = ScenarioCardSnapshot.fromCard(card)!;
      final settings = ChatGenerationSettings(
        soloScenario: snapshot,
        groupScenarios: {'member-instance': snapshot},
      );
      final raw = settings.toJsonString();
      expect(raw, isNotNull);
      card.scenario = 'This later edit belongs to new chats.';
      final reloaded = ChatGenerationSettings.fromJsonString(raw);
      expect(reloaded.soloScenario?.setting, 'A lift stalled at dusk');
      expect(reloaded.groupScenarios['member-instance']?.rules, snapshot.rules);
      expect(reloaded.groupScenarios['other-member'], isNull);
      expect(
        ChatGenerationSettings.fromJsonString(
          jsonEncode({'temperature': 0.3}),
        ).soloScenario,
        isNull,
      );
    },
  );

  test('scenario can use plain text labels and literal card macros', () {
    final snapshot = ScenarioCardSnapshot.fromCard(
      CharacterCard(name: 'Gantry')..setScenarioCard(true, 'Check the bell.'),
    )!;
    expect(
      resolveScenarioText(
        'Hello {user}. {{char}} {{persona}} {{setvar::private::changed}}',
        snapshot,
        cardName: '{{user}} Bell',
        playerName: 'Visitor',
        setting: '',
      ),
      'Hello Visitor. {{user}} Bell  ',
    );
    expect(scenarioStops(['\nUser:', '\n###', '<END>', 'CUT']), [
      '<END>',
      'CUT',
    ]);
    final reply = ChatMessage(
      text: 'Keeper: “Upstairs.”',
      sender: 'Gantry',
      isUser: false,
    );
    reply.activeMetadata = {'presentation': scenarioPresentation};
    expect(reply.isScenarioProse, isTrue);
    expect(reply.toPromptHistoryLine(), 'Narrator: Keeper: “Upstairs.”');
  });

  test('a split stop is withheld from the Scenario speech stream', () {
    final stream = ScenarioReplyStream(['STOP']);
    expect(stream.take('Footsteps. ST'), 'Footsteps. ');
    expect(stream.take('Footsteps. ', done: true), isEmpty);
    final partial = ScenarioReplyStream(['STOP']);
    expect(partial.take('ST'), isEmpty);
    expect(partial.take('STAIR'), 'STAIR');
  });

  testWidgets('desktop selector exposes Scenario as an explicit opt-in', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ScenarioCardTypeField(
                scenario: selected,
                onChanged: (value) {
                  setState(() => selected = value);
                },
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Card type'), findsOneWidget);
    await tester.tap(find.text('Character'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scenario').last);
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(find.textContaining('without a primary character'), findsOneWidget);
  });
}
