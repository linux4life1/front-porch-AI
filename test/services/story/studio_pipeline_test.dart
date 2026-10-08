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

// The Studio engine against a REAL StoryPipelineService (real in-memory DB,
// real StoryRepository) and a scripted model that answers by the stage it
// is asked for. The script is deliberately awkward — a reviewer that fails
// the first arc, a beat with a continuity slip, a Director plan that touches
// a written scene — so the loops that handle those are what get exercised.

// ignore_for_file: must_call_super

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_studio_').path;
        }
        return null;
      });
}

/// Answers by the role sentence each Studio prompt opens with, counting
/// calls per stage so an answer can change on the retry.
class _StageLlm extends LLMService {
  final List<String> prompts = [];
  final Map<String, int> calls = {};
  final String Function(String stage, int n, String prompt) answer;

  _StageLlm(this.answer);

  @override
  bool get isReady => true;

  @override
  String get backendName => 'scripted-studio';

  static const _stages = {
    'foundation': StudioBiblePrompts.foundationRole,
    'interview': StudioBiblePrompts.interviewRole,
    'arc': StudioBiblePrompts.arcRole,
    'arc-review': StudioBiblePrompts.arcReviewRole,
    'acts': StudioStructurePrompts.actsRole,
    'acts-review': StudioStructurePrompts.actsReviewRole,
    'sequences': StudioStructurePrompts.sequencesRole,
    'sequences-review': StudioStructurePrompts.sequencesReviewRole,
    'scenes': StudioStructurePrompts.scenesRole,
    'scenes-review': StudioStructurePrompts.scenesReviewRole,
    'beats': StudioProsePrompts.beatsRole,
    'beats-review': StudioProsePrompts.beatsReviewRole,
    'write': StudioProsePrompts.writerRole,
    'continuity': StudioProsePrompts.continuityRole,
    'fix': StudioProsePrompts.fixRole,
    'banned-fix': StudioProsePrompts.bannedFixRole,
    'patch': StudioProsePrompts.patchRole,
    'archivist': StudioArchivePrompts.archivistRole,
    'summary': StudioArchivePrompts.summaryRole,
    'director': DirectorPrompts.plannerRole,
    'director-review': DirectorPrompts.reviewRole,
  };

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    final stage = _stages.entries
        .firstWhere(
          (e) => params.prompt.contains(e.value),
          orElse: () => const MapEntry('unknown', ''),
        )
        .key;
    final n = (calls[stage] ?? 0) + 1;
    calls[stage] = n;
    yield answer(stage, n, params.prompt);
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
  void dispose() {}
}

const _pass = '<response><status>PASS</status></response>';
const _fail =
    '<response><status>FAIL</status><deviation_reasons>'
    '<reason>The theme is a slogan. Make it debatable.</reason>'
    '</deviation_reasons></response>';

String _foundation() =>
    '''<response><genre_label>Cozy fantasy</genre_label><mood_label>Warm</mood_label>
<genre_classification>Small-town magic.</genre_classification>
<tone_and_atmosphere>Gentle, wry.</tone_and_atmosphere>
<writing_style_description>Close third, plain sentences.</writing_style_description>
<status_quo>Wren keeps the porch light alone each evening.</status_quo>
<character_briefs>
<brief><name>Wren Hale</name><role>Protagonist — keeper of the light</role><description>Thirty, tired, kind.</description><core_flaw>Nobody will stay.</core_flaw><core_desire>To be waited for.</core_desire><vocal_cadence>Short, dry.</vocal_cadence></brief>
<brief><name>Dov Marsh</name><role>Supporting</role><description>The postman.</description><core_flaw>x</core_flaw><core_desire>y</core_desire><vocal_cadence>z</vocal_cadence></brief>
</character_briefs>
<relationship_matrix><relationship><from>Wren Hale</from><to>Dov Marsh</to><feeling>Fond</feeling><note>old friends</note><hidden_tension>He knows about the letters.</hidden_tension><trust_level>7</trust_level></relationship></relationship_matrix>
<world_lore><entry><topic>The Porch</topic><detail>It remembers every guest.</detail></entry></world_lore>
</response>''';

String _interview() =>
    '<response><interview>${List.filled(40, 'Wren looks away and talks about the light. ').join()}</interview>'
    '<appearance>Thin, grey eyes.</appearance><vocal_cadence>Short, dry.</vocal_cadence>'
    '<core_yearning>To be waited for.</core_yearning></response>';

String _arc() =>
    '''<response><global_arc><core_thematic_argument>Keeping a light for someone is a way of refusing to live.</core_thematic_argument>
<starting_value_state>Waiting</starting_value_state><ending_value_state>Leaving</ending_value_state>
<inciting_incident>The light flickers a message.</inciting_incident>
<major_surprises_and_twists>The message is from Wren.</major_surprises_and_twists></global_arc>
<narrative_threads><thread><thread_id>T1</thread_id><name>The flicker</name><description>What the light says.</description></thread>
<thread><thread_id>T2</thread_id><name>Dov</name><description>The letters.</description></thread></narrative_threads>
<character_arcs><arc><name>Wren Hale</name><lie_believed>Nobody will stay.</lie_believed><truth_needed>She can leave.</truth_needed><arc_catalyst>The flicker.</arc_catalyst><arc_description>From waiting to walking.</arc_description></arc></character_arcs></response>''';

String _acts() =>
    '<response><acts>${[for (var i = 1; i <= 3; i++) '<act><number>$i</number><title>Act $i</title><act_mandate>Mandate $i.</act_mandate><threads><thread>T1</thread></threads></act>'].join()}</acts></response>';

String _sequences() =>
    '<response><sequences>${[for (var i = 1; i <= 8; i++) '<sequence><number>$i</number><title>Seq $i</title><dramatic_question>Q$i?</dramatic_question><description>D$i</description><ending_hook>H$i</ending_hook></sequence>'].join()}</sequences></response>';

String _scenes(int count) =>
    '<response><scenes>${[for (var i = 1; i <= count; i++) '<scene><title>Scene $i</title><valence_score>${i.isOdd ? 1 : -1}</valence_score><scene_type>${i.isOdd ? 'ACTION' : 'REACTION'}</scene_type>'
          '<pov_character>Wren Hale</pov_character><characters_present><character>Wren Hale</character><character>Dov</character></characters_present>'
          '<setting>The porch</setting><narrative_lens>kinetic action</narrative_lens><scene_objective>O$i</scene_objective>'
          '<description>Things happen in scene $i.</description><value_shift><start_state>hope</start_state><end_state>dread</end_state></value_shift>'
          '<plot_commitments>None</plot_commitments><entrance_conditions>E$i</entrance_conditions><exit_conditions>X$i</exit_conditions></scene>'].join()}</scenes></response>';

String _beats(int count) =>
    '<response><beats>${[for (var i = 1; i <= count; i++) '<beat><beat_type>${i.isOdd ? 'DIALOGUE' : 'ACTION'}</beat_type><initiator>Wren Hale</initiator><reactor>Dov Marsh</reactor>'
          '<action>Beat $i happens.</action><reaction>Dov answers.</reaction><tactic>probes</tactic><subtext>fear</subtext><anchor>Fact $i.</anchor></beat>'].join()}</beats></response>';

String _prose(int beat) =>
    '<prose_text>${List.filled(70, 'word').join(' ')} Dov stood at the gate in beat $beat.</prose_text>';

const _continuityFail =
    '<response><issues><issue><severity>CRITICAL</severity>'
    '<description>Dov was sitting on the step in the previous passage, but here he is standing at the gate.</description>'
    '<location>Dov stood at the gate</location><fix_suggestion>Have him rise from the step.</fix_suggestion></issue></issues>'
    '<status>FAIL</status></response>';

String _fixFor(int beat) =>
    '<edits><edit><find>Dov stood at the gate in beat $beat.</find>'
    '<replace>Dov came off the step in beat $beat.</replace></edit></edits>';

const _archive =
    '<response><scene_summary>They talked on the porch.</scene_summary>'
    '<continuity_facts><fact><category>Object</category><key>The letters</key><detail>Dov has them in his coat.</detail><character>Dov Marsh</character></fact></continuity_facts>'
    '<relationship_updates><update><from>Wren Hale</from><to>Dov Marsh</to><new_feeling>Wary</new_feeling><trust_level>4</trust_level><trigger>the letters</trigger></update></relationship_updates>'
    '</response>';

class _Harness {
  _Harness(this.db, this.repo, this.llm, this.pipeline);
  final AppDatabase db;
  final StoryRepository repo;
  final _StageLlm llm;
  final StoryPipelineService pipeline;
  Future<void> dispose() => db.close();
}

Future<_Harness> _harness(
  String Function(String stage, int n, String prompt) answer,
) async {
  final db = AppDatabase.forTesting(sameIsolate: true);
  final repo = StoryRepository(db);
  final storage = StorageService();
  final memory = MemoryService(EmbeddingService(storage), storage, db);
  final llm = _StageLlm(answer);
  return _Harness(db, repo, llm, StoryPipelineService(repo, llm, memory, db));
}

Future<StoryProject> _studioProject(StoryRepository repo) async {
  final p = await repo.createProject(title: 'The Porch Light');
  p
    ..engineMode = StoryEngineMode.studio
    ..targetWords = 30000
    ..concept = 'A porch light that flickers messages.'
    ..reviewLane = StoryLaneChoice.chat();
  await repo.saveProject(p);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Studio bible: world, interviews, and an arc the reviewer bounces '
      'once', () async {
    final h = await _harness(
      (stage, n, prompt) => switch (stage) {
        'foundation' => _foundation(),
        'interview' => _interview(),
        'arc' => _arc(),
        'arc-review' => n == 1 ? _fail : _pass,
        _ => '',
      },
    );
    final p = await _studioProject(h.repo);
    await h.pipeline.runStoryArchitect(p);

    expect(p.statusQuo, contains('porch light'));
    expect(p.style.genreBrief, 'Small-town magic.');
    expect(p.cast.map((c) => c.name), ['Wren Hale', 'Dov Marsh']);
    expect(p.cast.first.flaw, 'Nobody will stay.');
    expect(p.cast.first.interview, contains('looks away'));
    expect(p.cast.first.details['truth'], 'She can leave.');
    expect(p.relationship('Wren', 'Dov')!.trust, 7);
    expect(p.threads.length, 2);
    expect(p.incitingIncident, contains('flickers'));
    // Only the lead is interviewed up front; Dov is Supporting.
    expect(h.llm.calls['interview'], 1);
    // The second arc attempt carried the reviewer's objection.
    expect(h.llm.calls['arc'], 2);
    expect(
      h.llm.prompts.where((t) => t.contains(StudioBiblePrompts.arcRole)).last,
      contains('Make it debatable'),
    );
    final log = await h.pipeline.store.entries(p.dbId!);
    // The bounced attempt and its review both carry FAIL; the accepted
    // attempt and its review both carry PASS.
    expect(log.where((e) => e.verdict == 'FAIL').length, 2);
    expect(log.where((e) => e.verdict == 'PASS').length, 2);
    expect(log.where((e) => e.stage == 'Story Arc').length, 2);
    await h.dispose();
  });

  test('a bible that died before its arc is finished before the acts, '
      'without redoing the world or the interviews', () async {
    var arcWorks = false;
    final h = await _harness(
      (stage, n, prompt) => switch (stage) {
        'foundation' => _foundation(),
        'interview' => _interview(),
        'arc' => arcWorks ? _arc() : '',
        'acts' => _acts(),
        'sequences' => _sequences(),
        _ => _pass,
      },
    );
    final p = await _studioProject(h.repo);
    await expectLater(h.pipeline.runStoryArchitect(p), throwsA(anything));
    expect(p.cast, isNotEmpty);
    expect(p.incitingIncident, isEmpty);

    arcWorks = true;
    await h.pipeline.runActStructurer(p);

    expect(p.incitingIncident, contains('flickers'));
    expect(p.themes, contains('refusing to live'));
    expect(p.threads.length, 2);
    expect(p.acts.length, 3);
    expect(h.llm.calls['foundation'], 1);
    expect(h.llm.calls['interview'], 1);
    final arcAt = h.llm.prompts.lastIndexWhere(
      (t) => t.contains(StudioBiblePrompts.arcRole),
    );
    final actsAt = h.llm.prompts.indexWhere(
      (t) => t.contains(StudioStructurePrompts.actsRole),
    );
    expect(arcAt, lessThan(actsAt), reason: 'acts are planned on the arc');
    await h.dispose();
  });

  test('Rewrite arc reruns the arc alone: the world, cast and interviews '
      'are kept', () async {
    var take = 1;
    final h = await _harness(
      (stage, n, prompt) => switch (stage) {
        'foundation' => _foundation(),
        'interview' => _interview(),
        'arc' =>
          take == 1 ? _arc() : _arc().replaceAll('flickers', 'goes dark with'),
        _ => _pass,
      },
    );
    final p = await _studioProject(h.repo);
    await h.pipeline.runStoryArchitect(p);
    final interview = p.cast.first.interview;
    expect(p.incitingIncident, contains('flickers'));

    take = 2;
    await h.pipeline.runStoryArc(p);

    expect(p.incitingIncident, contains('goes dark with'));
    expect(p.threads.length, 2);
    expect(p.cast.first.interview, interview);
    expect(h.llm.calls['foundation'], 1);
    expect(h.llm.calls['interview'], 1);
    await h.dispose();
  });

  test('Studio act: sequences, scenes, beats, prose with a continuity slip '
      'patched in place, and the archive', () async {
    final h = await _harness(
      (stage, n, prompt) => switch (stage) {
        'acts' => _acts(),
        'sequences' => _sequences(),
        'scenes' => _scenes(2),
        'beats' => _beats(3),
        'write' => _prose(n),
        'continuity' => n == 1 ? _continuityFail : _pass,
        'fix' => _fixFor(1),
        'archivist' => _archive,
        'summary' =>
          '<response><story_so_far>Two scenes passed.</story_so_far></response>',
        _ => _pass,
      },
    );
    final p = await _studioProject(h.repo);
    p.cast = [
      StoryCastMember(name: 'Wren Hale', role: 'Protagonist'),
      StoryCastMember(name: 'Dov Marsh', role: 'Supporting'),
    ];
    await h.pipeline.runActStructurer(p);
    expect(p.acts.length, 3);
    expect(p.sequences.map((s) => s.act), [1, 1, 2, 2, 2, 2, 3, 3]);
    expect(p.sequences[3].dramaticQuestion, 'Q4?');

    // Plan one sequence's scenes on its own, then write the whole act.
    await h.pipeline.planSequenceScenes(p, 1);
    expect(p.sceneIndexesInSequence(1).length, 2);
    final first = p.scenes[0]!.first;
    expect(first.lens, 'KINETIC_ACTION');
    expect(first.sceneType, 'action');
    expect(first.castNames, ['Wren Hale', 'Dov Marsh']);
    expect(p.sceneLabel(0, 1), '1.2');

    await h.pipeline.generateFullAct(p, 0);
    // Sequence 2 got planned by the act run; both sequences are written.
    expect(p.sceneIndexesInSequence(2).length, 2);
    expect(p.beats['0-0']!.length, 3);
    expect(p.beats['0-0']!.first.anchor, 'Fact 1.');
    expect(p.beatsWritten(0, 0), 3);
    final patched = p.prose['0-0-0']!;
    expect(patched.final_, contains('came off the step'));
    expect(patched.fix, isNotNull);
    expect(patched.fix!.reason, contains('sitting on the step'));
    expect(patched.fix!.before, contains('stood at the gate'));
    expect(p.prose['0-0-1']!.fix, isNull);
    expect(p.scenes[0]!.first.summary, 'They talked on the porch.');
    expect(p.continuity.single.key, 'The letters');
    expect(p.continuity.single.sceneId, first.id);
    expect(p.relationship('Wren', 'Dov')!.feeling, 'Wary');
    expect(p.sequenceByNumber(1)!.summary, 'Two scenes passed.');

    // Undo the fix puts the original words back.
    await h.pipeline.undoContinuityFix(p, 0, 0, 0);
    expect(p.prose['0-0-0']!.final_, contains('stood at the gate'));
    expect(p.prose['0-0-0']!.fix, isNull);
    await h.dispose();
  });

  test('a scene stopped before its archive is archived when writing '
      'resumes', () async {
    late StoryPipelineService pipeline;
    var stopOnArchive = true;
    final h = await _harness((stage, n, prompt) {
      if (stage == 'archivist' && stopOnArchive) {
        stopOnArchive = false;
        pipeline.requestStop();
        return '';
      }
      return switch (stage) {
        'acts' => _acts(),
        'sequences' => _sequences(),
        'scenes' => _scenes(2),
        'beats' => _beats(3),
        'write' => _prose(n),
        'archivist' => _archive,
        'summary' =>
          '<response><story_so_far>Two scenes passed.</story_so_far></response>',
        _ => _pass,
      };
    });
    pipeline = h.pipeline;
    final p = await _studioProject(h.repo);
    p.cast = [StoryCastMember(name: 'Wren Hale', role: 'Protagonist')];
    await h.pipeline.runActStructurer(p);
    await h.pipeline.planSequenceScenes(p, 1);

    // Stop lands on the archivist: every beat of 1.1 is written, but the
    // scene's summary and facts never were.
    await h.pipeline.writeNextScene(p);
    final first = p.scenes[0]!.first;
    expect(p.beatsWritten(0, 0), 3);
    expect(first.summary, isEmpty);

    await h.pipeline.writeNextScene(p);

    expect(first.summary, 'They talked on the porch.');
    expect(p.beatsWritten(0, 1), 3, reason: 'and writing carried on');
    await h.dispose();
  });

  test('a continuity slip is judged by Review and patched by Prose, and the '
      'run log names the job for each', () async {
    final h = await _harness(
      (stage, n, prompt) => switch (stage) {
        'acts' => _acts(),
        'sequences' => _sequences(),
        'scenes' => _scenes(2),
        'beats' => _beats(3),
        'write' => _prose(n),
        'continuity' => n == 1 ? _continuityFail : _pass,
        'fix' => _fixFor(1),
        'archivist' => _archive,
        _ => _pass,
      },
    );
    final p = await _studioProject(h.repo);
    p.cast = [StoryCastMember(name: 'Wren Hale', role: 'Protagonist')];
    await h.pipeline.runActStructurer(p);
    await h.pipeline.planSequenceScenes(p, 1);
    await h.pipeline.writeNextScene(p);

    final log = await h.pipeline.store.entries(p.dbId!);
    final check = log.firstWhere((e) => e.stage.startsWith('Continuity'));
    final fix = log.firstWhere((e) => e.stage.contains('continuity fix'));
    expect(check.role, 'review');
    expect(fix.role, 'prose');
    expect(fix.verdict, 'PASS');
    expect(p.beatText(0, 0, 0), contains('came off the step'));
    await h.dispose();
  });

  test('Stop ends the run quietly at the next model call', () async {
    late StoryPipelineService pipeline;
    final h = await _harness((stage, n, prompt) {
      if (stage == 'acts') {
        pipeline.requestStop();
        return _acts();
      }
      return _pass;
    });
    pipeline = h.pipeline;
    final p = await _studioProject(h.repo);
    await h.pipeline.runActStructurer(p);
    expect(h.pipeline.currentStep, 'Stopped');
    expect(h.pipeline.isRunning, isFalse);
    expect(h.pipeline.stopRequested, isFalse);
    expect(p.acts, isEmpty, reason: 'a stopped stage must not apply output');
    await h.dispose();
  });

  test('Director: plan with protection locks, apply, undo', () async {
    final h = await _harness(
      (stage, n, prompt) => switch (stage) {
        'director' =>
          '''<response><evaluation>Plant it.</evaluation><scope_kind>arc</scope_kind>
<actions>
<action><action_type>MODIFY_CHARACTER</action_type><character>Dov Marsh</character><summary>Dov hides the letters.</summary><details><secret>He burned the letters.</secret></details></action>
<action><action_type>EDIT_PROSE</action_type><scene>1.1</scene><summary>Wren notices soot.</summary><details><instructions>Wren notices soot on his cuff.</instructions></details></action>
<action><action_type>REWRITE_PROSE</action_type><scene>1.1</scene><summary>Rewrite 1.1</summary><details><instructions>all of it</instructions></details></action>
<action><action_type>ADD_SCENE</action_type><sequence>1</sequence><scene>1.1</scene><summary>The burning</summary><details><title>The burning</title><description>Dov burns them.</description><characters>Dov Marsh</characters></details></action>
<action><action_type>MODIFY_SCENE</action_type><scene>9.9</scene><summary>nowhere</summary></action>
</actions></response>''',
        'patch' =>
          '<edits><edit><find>The porch was dark.</find><replace>The porch was dark, and there was soot on his cuff.</replace></edit></edits>',
        'archivist' => _archive,
        _ => _pass,
      },
    );
    final p = await _studioProject(h.repo);
    p.cast = [
      StoryCastMember(name: 'Wren Hale', role: 'Protagonist'),
      StoryCastMember(name: 'Dov Marsh', role: 'Supporting'),
    ];
    p.acts = [for (var i = 1; i <= 3; i++) StoryAct(number: i, title: 'A$i')];
    p.sequences = [
      for (final s in StoryPacing.sequenceSlots)
        StorySequence(number: s.number, act: s.act, title: s.function),
    ];
    p.scenes[0] = [StoryScene(id: 's1', number: 1, title: 'Dark', sequence: 1)];
    p.beats['0-0'] = [StoryBeat(number: 1, description: 'They sit.')];
    p.prose['0-0-0'] = BeatProse(final_: 'The porch was dark. They sat.');
    await h.repo.saveProject(p);

    await h.pipeline.runDirectorPlan(
      p,
      'Dov burned the letters',
      protectWrittenProse: true,
    );
    final plan = p.directorPlan!;
    expect(plan.scope, 'arc');
    expect(plan.review, 'consistent');
    // The unresolvable scene was dropped; the rewrite is locked.
    expect(plan.actions.map((a) => a.type), [
      DirectorActionType.modifyCharacter,
      DirectorActionType.editProse,
      DirectorActionType.rewriteProse,
      DirectorActionType.addScene,
    ]);
    expect(plan.actions[2].locked, isTrue);
    expect(plan.actions[1].locked, isFalse);
    expect(plan.applicableCount, 3);

    await h.pipeline.applyDirectorPlan(p);
    expect(p.cast[1].details['secret'], 'He burned the letters.');
    expect(p.prose['0-0-0']!.final_, contains('soot on his cuff'));
    expect(p.scenes[0]!.map((s) => s.title), ['Dark', 'The burning']);
    expect(plan.actions[0].result, 'applied');
    expect(plan.actions[2].result, '', reason: 'locked actions are skipped');
    expect(p.directorApplied!.changeCount, 3);
    expect(h.llm.calls['archivist'], 1, reason: 'the patched scene is re-read');

    expect(await h.pipeline.undoDirectorPlan(p), isTrue);
    final restored = h.repo.getById(p.dbId!)!;
    expect(restored.prose['0-0-0']!.final_, 'The porch was dark. They sat.');
    expect(restored.scenes[0]!.length, 1);
    expect(restored.cast[1].details['secret'], isNull);
    expect(restored.directorApplied, isNull);
    await h.dispose();
  });
}
