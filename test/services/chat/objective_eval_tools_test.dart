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

// Live ObjectiveProposal through the tools-vs-text fork. Canned LLM
// payloads — not source greps. Confused/unparsed must never fake a win.
//
// 2026-10-16 (objectives that keep up): the YES/NO completion check became
// the goal sync — per goal a status (on_track / done / overtaken / dormant),
// steps done in any order, and a rewritten next step. The checker cases below
// were rewritten to that answer; what they assert is unchanged in spirit
// (a usable tool call does not text-retry, garbage never wins, the text floor
// and preferText still work, a goal let go is never a win). The KEEP/STALE
// relevance cases and the two-in-a-row retire are gone because the behaviour
// is gone: one "overtaken" answer replaces them. Step-generation cases are
// unchanged.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/objective_eval_tools.dart';
import 'package:front_porch_ai/services/chat/objective_origin.dart';
import 'package:front_porch_ai/services/chat/objective_proposal.dart';
import 'package:front_porch_ai/services/chat/objective_sync.dart';
import 'package:front_porch_ai/services/chat/objective_sync_tools.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/llm_service.dart';

class _FakeLlm extends LLMService {
  _FakeLlm(this._streamFactory);

  final Stream<String> Function(GenerationParams) _streamFactory;
  bool _ready = true;
  int streamCalls = 0;
  final List<String> prompts = [];

  @override
  bool get isReady => _ready;
  set isReady(bool v) => _ready = v;

  @override
  String get backendName => 'fake-objective-tools';

  @override
  Stream<String> generateStream(GenerationParams params) {
    streamCalls++;
    prompts.add(params.prompt);
    return _streamFactory(params);
  }

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void notifyListeners() {}
  @override
  // ignore: must_call_super
  void dispose() {}
}

Objective _mkObj(
  String id,
  String o, {
  String? origin,
  String? status,
  String tasks = '[]',
}) => Objective(
  id: id,
  characterId: 'c1',
  objective: o,
  chatId: null,
  active: true,
  isPrimary: true,
  injectionDepth: 3,
  checkFrequency: 3,
  tasks: tasks,
  createdAt: DateTime.now(),
  origin: origin,
  status: status,
);

/// What the sync wrote, in order.
class _Writes {
  final tasks = <String, List<Map<String, dynamic>>>{};
  final ends = <String, ObjectiveEnd>{};
  final dormant = <String, bool>{};
  final saved = <String, String>{};
  final achieved = <String>[];
  final letGo = <String>[];
}

ObjectiveProposal _live({
  required _FakeLlm llm,
  required List<Objective> actives,
  required _Writes w,
  List<Map<String, dynamic>> Function(Objective)? tasksFor,
  LlmToolResponse? Function(ToolEvalSpec spec)? onTool,
  bool preferText = false,
}) {
  final probe = ToolTransportProbe();
  return ObjectiveProposal(
    stripThinkBlocks: (t) => t,
    getLlmService: () => llm,
    getActiveCharacter: () => CharacterCard(name: 'Nia', scenario: 'dock'),
    getActiveGroup: () => null,
    getIsObserverMode: () => false,
    getUserName: () => 'User',
    getRealismEnabled: () => true,
    getMessages: () => const <ChatMessage>[],
    getActiveObjectives: () => actives,
    tasksForObjective:
        tasksFor ??
        (o) => (jsonDecode(o.tasks) as List).cast<Map<String, dynamic>>(),
    loadActiveObjectives: () async {},
    saveObjectiveTasks: (id, j) async => w.saved[id] = j,
    writeSyncedTasks: (o, t) async => w.tasks[o.id] = t,
    retireObjective: (o, end) async => w.ends[o.id] = end,
    setObjectiveDormant: (o, d) async => w.dormant[o.id] = d,
    onQuestAchieved: (o) => w.achieved.add(o.id),
    onObjectiveStale: (o) => w.letGo.add(o.id),
    getIsCheckingCompletion: () => false,
    setIsCheckingCompletion: (v) {},
    onNotify: () {},
    fireToolEval: (ToolEvalSpec spec) async => onTool?.call(spec),
    probe: probe,
    getBackendIdentity: () => 'fake-objective-tools||',
    getPreferTextEvals: () => preferText,
  );
}

LlmToolResponse _sync(List<Map<String, dynamic>> goals) => LlmToolResponse(
  calls: [
    LlmToolCall(name: kObjectiveSyncTool, arguments: {'goals': goals}),
  ],
  text: '',
);

LlmToolResponse _tasks(List<String> tasks) => LlmToolResponse(
  calls: [
    LlmToolCall(name: kObjectiveTasksTool, arguments: {'tasks': tasks}),
  ],
  text: '',
);

const _twoSteps =
    '[{"description":"ask at the dock","completed":false},'
    '{"description":"walk the cliff path","completed":false}]';

void main() {
  group('live checker — tools payload', () {
    test('a sync tool call ticks steps in any order and rewrites the next '
        'step of the character\'s own goal', () async {
      final w = _Writes();
      final llm = _FakeLlm((_) => Stream.value('1: done | none | none'));
      final p = _live(
        llm: llm,
        w: w,
        actives: [
          _mkObj(
            'o1',
            'find the keeper',
            origin: kObjectiveOriginCharacter,
            tasks: _twoSteps,
          ),
        ],
        onTool: (_) => _sync([
          {
            'goal': 1,
            'status': 'on_track',
            'steps_done': [2],
            'next_step': 'wait for the ferry',
          },
        ]),
      );
      final outcome = await p.checkTaskCompletionInBackground();
      expect(outcome, ObjectiveSyncOutcome.applied);
      final tasks = w.tasks['o1']!;
      expect(tasks[0]['description'], 'wait for the ferry');
      expect(tasks[0]['completed'], isFalse);
      expect(tasks[1]['completed'], isTrue);
      expect(w.ends, isEmpty);
      expect(
        llm.streamCalls,
        0,
        reason: 'usable tool call must not text-retry',
      );
    });

    test('garbage / empty / unknown statuses never fake a win', () async {
      for (final payload in [
        _sync([
          {
            'goal': 1,
            'status': 'HUH',
            'steps_done': [1],
            'next_step': 'none',
          },
        ]),
        _sync([]),
        _sync([
          {'goal': 7, 'status': 'done', 'steps_done': [], 'next_step': 'none'},
        ]),
      ]) {
        final w = _Writes();
        final llm = _FakeLlm((_) => Stream.value('1: YES'));
        final p = _live(
          llm: llm,
          w: w,
          actives: [_mkObj('oNo', 'find the keeper', tasks: _twoSteps)],
          onTool: (_) => payload,
        );
        await p.checkTaskCompletionInBackground();
        expect(w.tasks, isEmpty, reason: '$payload must not tick');
        expect(w.ends, isEmpty, reason: '$payload must not retire the goal');
      }
    });

    test('overtaken lets the goal go and is never a win', () async {
      final w = _Writes();
      final p = _live(
        llm: _FakeLlm((_) => const Stream.empty()),
        w: w,
        actives: [_mkObj('oO', 'win the race', tasks: _twoSteps)],
        onTool: (_) => _sync([
          {
            'goal': 1,
            'status': 'overtaken',
            'steps_done': [],
            'next_step': 'none',
          },
        ]),
      );
      await p.checkTaskCompletionInBackground();
      expect(w.ends['oO'], ObjectiveEnd.letGo);
      expect(w.letGo, ['oO']);
      expect(w.achieved, isEmpty);
    });

    // Set aside is for the character's own wants; a goal the user set keeps
    // its place in the prompt (live run 2026-10-16).
    test('dormant sets the character\'s goal aside without retiring it, and '
        'leaves the user\'s goal alone', () async {
      final w = _Writes();
      final p = _live(
        llm: _FakeLlm((_) => const Stream.empty()),
        w: w,
        actives: [
          _mkObj(
            'oD',
            'visit the island',
            tasks: _twoSteps,
            origin: kObjectiveOriginCharacter,
          ),
          _mkObj('oU', 'learn why she left', tasks: _twoSteps),
        ],
        onTool: (_) => _sync([
          for (final g in [1, 2])
            {
              'goal': g,
              'status': 'dormant',
              'steps_done': [],
              'next_step': 'none',
            },
        ]),
      );
      await p.checkTaskCompletionInBackground();
      expect(w.dormant['oD'], isTrue);
      expect(w.dormant.containsKey('oU'), isFalse);
      expect(w.ends, isEmpty);
    });
  });

  group('live task gen — tools payload', () {
    test('tasks array is saved', () async {
      final w = _Writes();
      final llm = _FakeLlm(
        (_) => Stream.value('gibberish that must not parse'),
      );
      final p = _live(
        llm: llm,
        w: w,
        actives: const [],
        tasksFor: (o) => const [],
        onTool: (_) => _tasks([
          'Nia asks the harbour master about the keeper',
          'Nia walks the cliff path at dusk',
        ]),
      );
      await p.generateObjectiveTasks(
        _mkObj('oT', 'find the keeper'),
        taskCount: 2,
      );
      final parsed = (jsonDecode(w.saved['oT']!) as List)
          .cast<Map<String, dynamic>>();
      expect(parsed.map((t) => t['description']), [
        'Nia asks the harbour master about the keeper',
        'Nia walks the cliff path at dusk',
      ]);
      expect(parsed.every((t) => t['completed'] == false), isTrue);
      expect(llm.streamCalls, 0);
    });
  });

  group('text path still scrapes', () {
    test('the line floor ticks a step; the old 1: YES still does', () async {
      for (final answer in ['1: on_track | 1 | none', '1: YES']) {
        final w = _Writes();
        final p = _live(
          llm: _FakeLlm((_) => Stream.value(answer)),
          w: w,
          actives: [_mkObj('oY', 'g', tasks: _twoSteps)],
          onTool: (_) => null,
        );
        await p.checkTaskCompletionInBackground();
        expect(w.tasks['oY']![0]['completed'], isTrue, reason: answer);
      }
    });

    test('1. do the thing saves a task', () async {
      final w = _Writes();
      final llm = _FakeLlm(
        (_) => Stream.value('1. do the thing\n2. then this'),
      );
      final p = _live(llm: llm, w: w, actives: const [], onTool: (_) => null);
      await p.generateObjectiveTasks(_mkObj('oL', 'g'), taskCount: 2);
      final parsed = (jsonDecode(w.saved['oL']!) as List)
          .cast<Map<String, dynamic>>();
      expect(parsed.map((t) => t['description']), [
        'do the thing',
        'then this',
      ]);
    });

    test(
      'preferText skips the tool even when a done call is waiting',
      () async {
        final w = _Writes();
        final llm = _FakeLlm((_) => Stream.value('1: on_track | none | none'));
        var toolCalls = 0;
        final p = _live(
          llm: llm,
          w: w,
          actives: [_mkObj('oP', 'g', tasks: _twoSteps)],
          preferText: true,
          onTool: (_) {
            toolCalls++;
            return _sync([
              {
                'goal': 1,
                'status': 'done',
                'steps_done': [],
                'next_step': 'none',
              },
            ]);
          },
        );
        await p.checkTaskCompletionInBackground();
        expect(toolCalls, 0);
        expect(w.ends, isEmpty);
        expect(llm.streamCalls, 1);
      },
    );

    test('a re-plan carries the elapsed span into the prompt', () async {
      final llm = _FakeLlm((_) => Stream.value('1: on_track | none | none'));
      final p = _live(
        llm: llm,
        w: _Writes(),
        actives: [_mkObj('oS', 'g', tasks: _twoSteps)],
        onTool: (_) => null,
      );
      await p.checkTaskCompletionInBackground(
        elapsedSpan:
            'About 2 weeks have passed since these goals were last '
            'looked at.',
      );
      expect(llm.prompts.single, contains('About 2 weeks have passed'));
      expect(llm.prompts.single, contains('Evaluate EACH item below'));
    });
  });

  group('a newborn goal of the character waits for its steps', () {
    test('no steps yet: it is left out, its steps are generated once, and a '
        'lenient answer cannot win it', () async {
      final w = _Writes();
      var syncCalls = 0;
      final llm = _FakeLlm((_) => Stream.value('1: YES'));
      final p = _live(
        llm: llm,
        w: w,
        actives: [
          _mkObj('oN', 'learn the shanty', origin: kObjectiveOriginCharacter),
        ],
        onTool: (spec) {
          if (spec.toolChoice == kObjectiveSyncTool) {
            syncCalls++;
            return _sync([
              {
                'goal': 1,
                'status': 'done',
                'steps_done': [],
                'next_step': 'none',
              },
            ]);
          }
          return _tasks(['Nia hums it on the pier', 'Nia sings it aloud']);
        },
      );
      final outcome = await p.checkTaskCompletionInBackground();
      expect(outcome, ObjectiveSyncOutcome.notRun);
      expect(syncCalls, 0, reason: 'a goal with no steps is not asked about');
      expect(w.ends, isEmpty);
      await pumpEventQueue();
      expect(w.saved['oN'], contains('Nia hums it on the pier'));
    });

    test(
      'a goal the user typed has no steps by design and is asked about',
      () async {
        final w = _Writes();
        final p = _live(
          llm: _FakeLlm((_) => const Stream.empty()),
          w: w,
          actives: [_mkObj('oU', 'make it to the dance')],
          onTool: (_) => _sync([
            {
              'goal': 1,
              'status': 'done',
              'steps_done': [],
              'next_step': 'none',
            },
          ]),
        );
        await p.checkTaskCompletionInBackground();
        expect(w.ends['oU'], ObjectiveEnd.achieved);
        expect(w.achieved, ['oU']);
      },
    );
  });
}
