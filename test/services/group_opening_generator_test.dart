// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create Group's opening generator writes the scene where the group's chats
// really start. Before, the scenario and first message were written from the
// cast and dynamics alone and could put the group anywhere. These pin what
// the prompts ask (no model is called): the Setting's place, its world, the
// weather and the always-on lore go in, and nothing does without a world.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/group_opening_generator.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/web/facade/group_draft_opening.dart';

import '../golden/support/fakes.dart';

World _w(
  String id,
  String name, {
  String? parent,
  String description = '',
  List<LorebookEntry> lore = const [],
}) => World(
  id: id,
  name: name,
  description: description,
  parentWorldId: parent,
  lorebook: Lorebook(entries: List.of(lore)),
);

void main() {
  final vale = _w(
    'vale',
    'Green Vale',
    description: 'Wet lowland forest under a low grey sky.',
    lore: [
      LorebookEntry(
        keys: const [],
        content: 'The river floods every spring.',
        constant: true,
      ),
      LorebookEntry(keys: const ['inn'], content: 'An inn sells cider.'),
    ],
  )..defaultPlaceId = 'mill';
  final places = [
    vale,
    _w(
      'mill',
      'The Mill',
      parent: 'vale',
      description: 'A flour mill on stilts above the floodplain.',
    ),
    _w('bridge', 'Old Bridge', parent: 'vale'),
  ];
  World? lookup(String id) => places.where((w) => w.id == id).firstOrNull;
  String? weather(String id) => 'Rainforest';

  group('groupSettingBrief', () {
    test('a world starts at its star, with its prose, weather and '
        'always-on lore', () {
      final brief = groupSettingBrief(
        const GroupWorldChoice(settingId: 'vale'),
        lookup: lookup,
        weatherOf: weather,
      );
      expect(brief, contains('The scene starts at The Mill, in Green Vale.'));
      expect(brief, contains('flour mill on stilts'));
      expect(brief, contains('Wet lowland forest'));
      expect(brief, contains('Weather: Rainforest.'));
      expect(brief, contains('The river floods every spring.'));
      expect(
        brief,
        isNot(contains('cider')),
        reason: 'keyed lore waits for its keys; only always-on facts go in',
      );
    });

    test('a picked place starts there', () {
      final brief = groupSettingBrief(
        const GroupWorldChoice(settingId: 'bridge'),
        lookup: lookup,
      );
      expect(
        brief,
        startsWith('The scene starts at Old Bridge, in Green Vale.'),
      );
    });

    test('no world, no brief', () {
      expect(
        groupSettingBrief(const GroupWorldChoice(), lookup: lookup),
        isEmpty,
      );
    });
  });

  group('the prompts carry the brief', () {
    final cast = [
      CharacterCard(name: 'Juniper', personality: 'Dry wit.'),
      CharacterCard(name: 'Marlow', personality: 'Restless.'),
    ];
    const brief = 'The scene starts at The Mill, in Green Vale.';

    test('scenario', () {
      final withIt = GroupOpeningGenerator.scenarioPrompt(
        members: cast,
        settingBrief: brief,
      );
      expect(withIt, contains('WHERE THE SCENE TAKES PLACE'));
      expect(withIt, contains(brief));
      expect(
        GroupOpeningGenerator.scenarioPrompt(members: cast),
        isNot(contains('WHERE THE SCENE TAKES PLACE')),
      );
    });

    for (final director in [false, true]) {
      test('first message${director ? ' (Director Mode)' : ''}', () {
        final withIt = GroupOpeningGenerator.firstMessagePrompt(
          members: cast,
          scenario: '',
          isDirector: director,
          settingBrief: brief,
        );
        expect(withIt, contains(brief));
        expect(
          GroupOpeningGenerator.firstMessagePrompt(
            members: cast,
            scenario: '',
            isDirector: director,
          ),
          isNot(contains('WHERE THE SCENE TAKES PLACE')),
        );
      });
    }
  });

  // The web wizard's Generate (POST /api/groups/draft/*) goes through
  // GroupDraftOpening. The recording service only captures what is sent;
  // the returned text is never asserted.
  group('web draft opening', () {
    final juniper = CharacterCard(name: 'Juniper', personality: 'Dry wit.')
      ..dbId = 'j';
    final marlow = CharacterCard(name: 'Marlow', personality: 'Restless.')
      ..dbId = 'm';
    final body = {
      'memberIds': ['j', 'm'],
      'worlds': {'settingId': 'vale'},
      'relationships': {
        'j': {'m': 60},
      },
    };

    late _RecordingLlm llm;
    late GroupDraftOpening opening;
    setUp(() {
      llm = _RecordingLlm();
      opening = GroupDraftOpening(
        _RecordingLlmProvider(llm),
        FakeCharacterRepository([juniper, marlow]),
        FakeWorldRepository(places),
      );
    });

    for (final first in [false, true]) {
      test('${first ? 'first message' : 'scenario'} sends the place and '
          'the dynamics', () async {
        final r = await opening.generate(body, firstMessage: first);
        expect(r.error, isNull);
        final prompt = llm.seen.single.prompt;
        expect(prompt, contains('WHERE THE SCENE TAKES PLACE'));
        expect(
          prompt,
          contains('The scene starts at The Mill, in Green Vale.'),
        );
        expect(prompt, contains('Juniper feels'));
        expect(prompt, contains('toward Marlow'));
      });
    }

    test('fewer than two members is a 400; nothing is sent', () async {
      final r = await opening.generate({
        ...body,
        'memberIds': ['j'],
      }, firstMessage: true);
      expect(r.status, 400);
      expect(r.error, isNotNull);
      expect(llm.seen, isEmpty);
    });

    test('a model that is not ready is a 503; nothing is sent', () async {
      llm.ready = false;
      final r = await opening.generate(body, firstMessage: true);
      expect(r.status, 503);
      expect(llm.seen, isEmpty);
    });
  });

  group('groupDynamicsContext', () {
    final pair = [(id: 'a', name: 'Aerin'), (id: 'b', name: 'Bo')];

    test('a score of 0 is no feeling, so nobody feeling anything sends '
        'nothing', () {
      expect(
        groupDynamicsContext(pair, {
          'a': {'b': 0},
        }),
        isEmpty,
      );
    });

    test('a moved slider is sent with its tier', () {
      final ctx = groupDynamicsContext(pair, {
        'a': {'b': 0},
        'b': {'a': -30},
      });
      expect(ctx, contains('Bo feels'));
      expect(ctx, contains('toward Aerin (score: -30'));
      expect(ctx, isNot(contains('score: 0 ')));
    });
  });
}

class _RecordingLlm extends LLMService {
  final List<GenerationParams> seen = [];
  bool ready = true;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    seen.add(params);
    yield 'The rain drums on the mill roof.';
  }

  @override
  bool get isReady => ready;

  @override
  String get backendName => 'recording';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingLlmProvider extends FakeLLMProvider {
  _RecordingLlmProvider(this._service);
  final LLMService _service;

  @override
  LLMService get activeService => _service;
}
