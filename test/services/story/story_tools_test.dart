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

// Tool calling is the primary transport for the structured Studio stages;
// tags are the backup. Two contracts: (1) a tool call's arguments, turned
// back into tag text, read correctly through the REAL parsers — the
// schemas mirror the prompt templates; (2) the pipeline asks for the tool
// first, uses the call it gets back, and a host that refuses the tool gets
// the tag prompt from then on instead of being asked again.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tool arguments → tags → the real parsers', () {
    test('a review verdict', () {
      final text = StoryTools.toTags(StoryTools.review, {
        'critique_analysis': 'Act II has no one-way door.',
        'status': 'FAIL',
        'deviation_reasons': ['Act II ends on a pause, not a break.'],
      });
      final v = StoryReview.parse(text);
      expect(v.pass, isFalse);
      expect(v.parsed, isTrue);
      expect(v.critique, contains('one-way door'));
      expect(v.feedback, contains('pause'));
    });

    test('a passing review with no reasons', () {
      final v = StoryReview.parse(
        StoryTools.toTags(StoryTools.review, {'status': 'PASS'}),
      );
      expect(v.pass, isTrue);
    });

    test('beats', () {
      final text = StoryTools.toTags(StoryTools.beats, {
        'beats': [
          {
            'beat_type': 'Action',
            'initiator': 'Mara',
            'reactor': 'Joss',
            'action': 'Mara slides the ledger across the table.',
            'reaction': 'Joss does not pick it up.',
            'subtext': 'She is daring him.',
            'anchor': 'the ledger',
          },
          {
            'beat_type': 'Dialogue',
            'initiator': 'Joss',
            'reactor': 'Mara',
            'action': 'Joss names the day the caravan leaves.',
            'reaction': 'Mara counts the days on her fingers.',
            'anchor': 'the caravan date',
          },
        ],
      });
      expect(StudioParseProse.checkBeats(text, min: 2), isNull);
      final beats = StudioParseProse.beats(text, max: 10);
      expect(beats.length, 2);
      expect(beats.first.initiator, 'Mara');
      expect(beats.first.anchor, 'the ledger');
      expect(beats.last.type, 'Dialogue');
    });

    test('an archive with facts and a relationship shift', () {
      final p = StoryProject(title: 'T')
        ..cast = [
          StoryCastMember(name: 'Wren Hale', role: 'Protagonist'),
          StoryCastMember(name: 'Dov Marsh', role: 'Supporting'),
        ]
        ..acts = [StoryAct(number: 1, title: 'One', description: '')]
        ..scenes = {
          0: [StoryScene(number: 1, title: 'Porch', id: 's1', sequence: 1)],
        };
      final text = StoryTools.toTags(StoryTools.archive, {
        'scene_summary': 'They talked on the porch.',
        'continuity_facts': [
          {
            'category': 'Object',
            'key': 'The letters',
            'detail': 'Dov has them in his coat.',
            'character': 'Dov Marsh',
          },
        ],
        'relationship_updates': [
          {
            'from': 'Wren Hale',
            'to': 'Dov Marsh',
            'new_feeling': 'Wary',
            'trust_level': 4,
            'trigger': 'the letters',
          },
        ],
      });
      StudioParseProse.applyArchive(p, 0, 0, text);
      expect(p.scenes[0]!.first.summary, 'They talked on the porch.');
      expect(p.continuity.single.key, 'The letters');
      expect(p.relationship('Wren Hale', 'Dov Marsh')?.trust, 4);
    });

    test('a Director plan', () {
      final p = StoryProject(title: 'T')
        ..acts = [StoryAct(number: 1, title: 'One', description: '')]
        ..scenes = {
          0: [StoryScene(number: 1, title: 'Porch', id: 's1', sequence: 1)],
        };
      final text = StoryTools.toTags(StoryTools.director, {
        'evaluation': 'A small local change.',
        'scope_kind': 'local',
        'actions': [
          {
            'action_type': 'EDIT_PROSE',
            'scene': '1.1',
            'summary': 'The porch light smells of lamp oil.',
            'details': {'instructions': 'Add the smell of lamp oil.'},
          },
        ],
      });
      final plan = StoryDirector.parsePlan(p, text, directive: 'lamp oil');
      expect(plan.scope, 'local');
      expect(plan.actions.single.summary, contains('lamp oil'));
    });

    test('text in arguments is escaped so a < never opens a tag', () {
      final text = StoryTools.toTags(StoryTools.sequenceSummary, {
        'story_so_far': 'Mara wrote "<ledger> & more" on the wall.',
      });
      expect(StoryXml.tag(text, 'story_so_far'), contains('<ledger> & more'));
    });

    test('the shared definition list names every spec once', () {
      final names = StoryTools.definitions
          .map((d) => (d['function'] as Map)['name'])
          .toList();
      expect(names.toSet().length, names.length);
      expect(
        names,
        containsAll(['report_review', 'plan_beats', 'plan_director']),
      );
    });
  });

  group('the pipeline asks for the tool first', () {
    test('a tool call is used; a refusal falls back to tags and is '
        'remembered', () async {
      // The reviewer answers by tool on a willing host and by tags on one
      // that refuses; the generator always answers in tags.
      final willing = _ToolLlm(refuse: false);
      final refusing = _ToolLlm(refuse: true);
      for (final llm in [willing, refusing]) {
        final h = await _harness(llm);
        final p = await h.repo.createProject(title: 'T');
        p
          ..engineMode = StoryEngineMode.studio
          ..concept = 'A porch light.'
          ..reviewEnabled = true
          ..reviewLane = StoryLaneChoice.chat();
        await h.repo.saveProject(p);
        // The Director is the smallest reviewed stage: plan → review.
        p.acts = [StoryAct(number: 1, title: 'One', description: '')];
        p.scenes = {
          0: [StoryScene(number: 1, title: 'Porch', id: 's1', sequence: 1)],
        };
        await h.pipeline.runDirectorPlan(
          p,
          'lamp oil',
          protectWrittenProse: true,
        );
        await h.dispose();
      }
      // Willing host: both calls went through the tool, none by text.
      expect(willing.toolCalls, ['plan_director', 'report_review']);
      expect(willing.textCalls, 0);
      // Refusing host: asked once, refused, then every call by text —
      // the second stage never asks again.
      expect(refusing.toolCalls, ['plan_director']);
      expect(refusing.textCalls, 2);
    });
  });
}

/// Answers a Director plan and a PASS review, by tool when asked and
/// willing, otherwise by tags over the text stream.
class _ToolLlm extends LLMService {
  _ToolLlm({required this.refuse});

  final bool refuse;
  final List<String> toolCalls = [];
  int textCalls = 0;

  @override
  bool get isReady => true;

  @override
  String get backendName => 'tool-fake';

  bool _isReview(String prompt) => prompt.contains(DirectorPrompts.reviewRole);

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    toolCalls.add(params.toolChoice ?? '?');
    if (refuse) return null;
    expect(tools, same(StoryTools.definitions), reason: 'one shared list');
    if (_isReview(params.prompt)) {
      return const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'report_review',
            arguments: {'status': 'PASS', 'critique_analysis': 'Fine.'},
          ),
        ],
        text: '',
      );
    }
    return const LlmToolResponse(
      calls: [
        LlmToolCall(
          name: 'plan_director',
          arguments: {
            'evaluation': 'Small.',
            'scope_kind': 'local',
            'actions': [
              {
                'action_type': 'EDIT_PROSE',
                'scene': '1.1',
                'summary': 'Lamp oil.',
                'details': {'instructions': 'Add lamp oil.'},
              },
            ],
          },
        ),
      ],
      text: '',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    textCalls++;
    if (_isReview(params.prompt)) {
      yield '<response><status>PASS</status></response>';
      return;
    }
    yield '<response><evaluation>Small.</evaluation><scope_kind>local</scope_kind>'
        '<actions><action><action_type>EDIT_PROSE</action_type><scene>1.1</scene>'
        '<summary>Lamp oil.</summary><details><instructions>Add lamp oil.</instructions></details>'
        '</action></actions></response>';
  }

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void dispose() {}
  @override
  void notifyListeners() {}
}

class _Harness {
  _Harness(this.db, this.repo, this.pipeline);
  final AppDatabase db;
  final StoryRepository repo;
  final StoryPipelineService pipeline;
  Future<void> dispose() => db.close();
}

Future<_Harness> _harness(LLMService llm) async {
  final db = AppDatabase.forTesting(sameIsolate: true);
  final repo = StoryRepository(db);
  final storage = StorageService();
  final memory = MemoryService(EmbeddingService(storage), storage, db);
  return _Harness(db, repo, StoryPipelineService(repo, llm, memory, db));
}
