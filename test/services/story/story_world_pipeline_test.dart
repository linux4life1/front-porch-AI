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

// Stories set in Worlds, slice 2 (docs/design/stories-in-worlds.md §3.2):
// a real StoryPipelineService whose world is Greenhollow Estate from the
// shipped starter asset, and a scripted model. Both engines: the bible
// reads the setting brief and appends to the copied lore, the planner names
// places and the scenes keep their ids, the writer sees the place's own
// prose and that place's lore first. The Director resolves a place too.

// ignore_for_file: must_call_super

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject, World;
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
          return Directory.systemTemp.createTempSync('fpai_story_world_').path;
        }
        return null;
      });
}

/// Greenhollow Estate as the library would hold it: the root with its six
/// entries and three places with five more, the Conservatory starred.
({World root, List<World> places, StoryWorldBrief brief}) greenhollow() {
  final raw = jsonDecode(
    File('assets/worlds/starter/greenhollow.fpworld').readAsStringSync(),
  );
  final pkg = decodeFpWorld(Map<String, dynamic>.from(raw as Map));
  final root = pkg.world..biomeId = pkg.biome?['id']?.toString();
  final places = [
    for (final child in pkg.locations)
      decodeFpWorld(child).world..parentWorldId = root.id,
  ];
  final start = places.firstWhere((p) => p.id == root.defaultPlaceId);
  return (
    root: root,
    places: places,
    brief: StoryWorldBrief(chain: [start, root], places: places),
  );
}

/// Answers by what the prompt contains and keeps every prompt it saw.
class _ScriptLlm extends LLMService {
  _ScriptLlm(this.reply);
  final String Function(String prompt) reply;
  final List<String> prompts = [];

  @override
  bool get isReady => true;
  @override
  String get backendName => 'scripted-world';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    yield reply(params.prompt);
  }

  String last(String marker) => prompts.lastWhere((p) => p.contains(marker));

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

class _Harness {
  _Harness(this.db, this.repo, this.llm, this.pipeline);
  final AppDatabase db;
  final StoryRepository repo;
  final _ScriptLlm llm;
  final StoryPipelineService pipeline;
  Future<void> dispose() => db.close();
}

Future<_Harness> _harness(
  StoryWorldBrief world,
  String Function(String prompt) reply,
) async {
  final db = AppDatabase.forTesting(sameIsolate: true);
  final repo = StoryRepository(db);
  final storage = StorageService();
  final memory = MemoryService(EmbeddingService(storage), storage, db);
  final llm = _ScriptLlm(reply);
  return _Harness(
    db,
    repo,
    llm,
    StoryPipelineService(repo, llm, memory, db, worldBrief: (_) => world),
  );
}

// ── Studio script ──────────────────────────────────────────────────────

const _foundation =
    '''<response><genre_label>Cozy mystery</genre_label><mood_label>Warm</mood_label>
<genre_classification>Estate mystery.</genre_classification>
<tone_and_atmosphere>Gentle, wry.</tone_and_atmosphere>
<writing_style_description>Close third.</writing_style_description>
<status_quo>Marigold keeps the house running.</status_quo>
<character_briefs>
<brief><name>Marigold Finch</name><role>Protagonist — the housekeeper</role><description>Fifty, brisk.</description><core_flaw>Order is love.</core_flaw><core_desire>To be trusted.</core_desire><vocal_cadence>Clipped.</vocal_cadence></brief>
<brief><name>Tobias Vane</name><role>Supporting</role><description>The gardener.</description><core_flaw>x</core_flaw><core_desire>y</core_desire><vocal_cadence>z</vocal_cadence></brief>
</character_briefs>
<relationship_matrix><relationship><from>Marigold Finch</from><to>Tobias Vane</to><feeling>Wary</feeling><note>old quarrel</note><hidden_tension>The key.</hidden_tension><trust_level>4</trust_level></relationship></relationship_matrix>
<world_lore><entry><topic>The library key</topic><detail>There are two keys, not one.</detail></entry></world_lore>
</response>''';

String _interview() =>
    '<response><interview>${List.filled(40, 'Marigold talks about the bell. ').join()}</interview>'
    '<appearance>Grey, upright.</appearance><vocal_cadence>Clipped.</vocal_cadence>'
    '<core_yearning>To be trusted.</core_yearning></response>';

const _arc =
    '''<response><global_arc><core_thematic_argument>A locked door keeps nobody safe.</core_thematic_argument>
<starting_value_state>Order</starting_value_state><ending_value_state>Trust</ending_value_state>
<inciting_incident>The library stands open.</inciting_incident>
<major_surprises_and_twists>The cook has the second key.</major_surprises_and_twists></global_arc>
<narrative_threads><thread><thread_id>T1</thread_id><name>The key</name><description>Who opened it.</description></thread></narrative_threads>
<character_arcs><arc><name>Marigold Finch</name><lie_believed>Order is love.</lie_believed><truth_needed>Trust is.</truth_needed><arc_catalyst>The door.</arc_catalyst><arc_description>From order to trust.</arc_description></arc></character_arcs></response>''';

String _acts() =>
    '<response><acts>${[for (var i = 1; i <= 3; i++) '<act><number>$i</number><title>Act $i</title><act_mandate>Mandate $i.</act_mandate><threads><thread>T1</thread></threads></act>'].join()}</acts></response>';

String _sequences() =>
    '<response><sequences>${[for (var i = 1; i <= 8; i++) '<sequence><number>$i</number><title>Seq $i</title><dramatic_question>Q$i?</dramatic_question><description>D$i</description><ending_hook>H$i</ending_hook></sequence>'].join()}</sequences></response>';

String _scene(int i, String place) =>
    '<scene><title>Scene $i</title><valence_score>${i.isOdd ? 1 : -1}</valence_score><scene_type>${i.isOdd ? 'ACTION' : 'REACTION'}</scene_type>'
    '<pov_character>Marigold Finch</pov_character><characters_present><character>Marigold Finch</character></characters_present>'
    '<place>$place</place><setting>Early morning, the long table laid.</setting><scene_objective>O$i</scene_objective>'
    '<description>Things happen in scene $i.</description><value_shift><start_state>order</start_state><end_state>unease</end_state></value_shift>'
    '<plot_commitments>None</plot_commitments><entrance_conditions>E$i</entrance_conditions><exit_conditions>X$i</exit_conditions></scene>';

String _scenes() =>
    '<response><scenes>${_scene(1, 'The Kitchens')}${_scene(2, 'new: the Gatehouse')}</scenes></response>';

String _beats() =>
    '<response><beats>${[for (var i = 1; i <= 3; i++) '<beat><beat_type>${i.isOdd ? 'DIALOGUE' : 'ACTION'}</beat_type><initiator>Marigold Finch</initiator><reactor>—</reactor>'
          '<action>Beat $i happens.</action><reaction>—</reaction><tactic>probes</tactic><subtext>fear</subtext><anchor>Fact $i.</anchor></beat>'].join()}</beats></response>';

final _prose =
    '<prose_text>Marigold counted the copper pans twice before the bell, and the oven breathed its bread smell up the stair while she stood with the ledger open and would not look at the second hook where a key should not have been. ${'The morning went on. ' * 12}</prose_text>';

String _studio(String prompt) {
  if (prompt.contains(StudioBiblePrompts.foundationRole)) return _foundation;
  if (prompt.contains(StudioBiblePrompts.interviewRole)) return _interview();
  if (prompt.contains(StudioBiblePrompts.arcRole)) return _arc;
  if (prompt.contains(StudioStructurePrompts.actsRole)) return _acts();
  if (prompt.contains(StudioStructurePrompts.sequencesRole)) {
    return _sequences();
  }
  if (prompt.contains(StudioStructurePrompts.scenesRole)) return _scenes();
  if (prompt.contains(StudioProsePrompts.beatsRole)) return _beats();
  if (prompt.contains(StudioProsePrompts.writerRole)) return _prose;
  if (prompt.contains(StudioArchivePrompts.archivistRole)) {
    return '<response><scene_summary>Breakfast.</scene_summary></response>';
  }
  return '<response><status>PASS</status></response>';
}

// ── Quick script ───────────────────────────────────────────────────────

String _quick(String prompt) {
  if (prompt.contains('Input Concept:')) {
    return '<response><concept>The open library.</concept><status_quo>Marigold keeps the house.</status_quo>'
        '<inciting_incident>The library stands open.</inciting_incident><themes>Order and trust.</themes>'
        '<style><genre>Mystery</genre><mood>Warm</mood><writing_guide>Plain.</writing_guide></style>'
        '<threads><thread><id>t1</id><name>Main</name><description>The key.</description></thread></threads>'
        '<protagonist><name>Marigold Finch</name><role>Protagonist</role><description>Housekeeper.</description><voice_sample>Mind the step.</voice_sample></protagonist>'
        '<world_lore><entry><topic>The library key</topic><detail>There are two keys, not one.</detail></entry></world_lore></response>';
  }
  if (prompt.contains('Define exactly')) {
    return '<response><acts><act><number>1</number><title>One</title><description>All of it.</description><focus_thread_ids>t1</focus_thread_ids></act></acts></response>';
  }
  if (prompt.contains('creating scenes for ACT')) {
    return '<response><scenes>'
        '<scene><number>1</number><title>The bell rings early</title><description>Breakfast goes wrong.</description><active_thread_ids>t1</active_thread_ids><location>The Kitchens — morning, the bread oven lit</location><cast_names>Marigold Finch</cast_names><valence>2</valence></scene>'
        '<scene><number>2</number><title>What the gardener keeps</title><description>A visit.</description><active_thread_ids>t1</active_thread_ids><location>new: the Gatehouse — dusk</location><cast_names>Marigold Finch</cast_names><valence>-2</valence></scene>'
        '</scenes></response>';
  }
  if (prompt.contains('Break it into') ||
      prompt.contains('Break this scene into')) {
    return '<response><beats><beat><number>1</number><type>Action</type><description>She counts the pans.</description><emotional_shift>calm to unease</emotional_shift><valence>1</valence><pacing>1</pacing></beat></beats></response>';
  }
  if (prompt.contains('Return ONLY the polished prose text')) {
    return 'Polished prose.';
  }
  if (prompt.contains('Write the prose now')) return 'Draft prose.';
  return '';
}

/// The topic of each `- topic: detail` line in a lore block.
List<String> _topics(String block) => [
  for (final line in block.split('\n'))
    if (line.startsWith('- ')) line.substring(2).split(':').first.trim(),
];

String _between(String text, String open, String close) {
  final a = text.indexOf(open);
  if (a < 0) return '';
  final b = text.indexOf(close, a + open.length);
  return b < 0 ? text.substring(a) : text.substring(a + open.length, b);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final g = greenhollow();
  final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
  final kitchensTopics = kitchens.lorebook.entries.map((e) => e.name).toSet();

  test('Studio: the bible reads the world, the planner prompt lists its '
      'places and a named place resolves to its id, and the writer sees the '
      'place and its lore first', () async {
    final h = await _harness(g.brief, _studio);
    final p = await h.repo.createProject(title: 'The Locked Library');
    p
      ..engineMode = StoryEngineMode.studio
      ..targetWords = 30000
      ..reviewEnabled = false
      ..concept = 'The housekeeper finds the locked library open.'
      ..worldId = g.brief.start!.id
      ..worldName = g.root.name;
    await h.repo.saveProject(p);

    await h.pipeline.runStoryArchitect(p);
    final foundation = h.llm.last(StudioBiblePrompts.foundationRole);
    expect(foundation, contains('<setting_world>'));
    expect(foundation, contains('World: Greenhollow Estate'));
    expect(foundation, contains('- The Kitchens:'));
    expect(foundation, contains(StoryWorldContext.foundationRules.first));
    // Eleven copied entries first, then the bible's own, never replaced.
    expect(p.lore.where(isWorldLore), hasLength(11));
    expect(p.lore.last.topic, 'The library key');
    expect(p.lore.length, 12);

    await h.pipeline.runActStructurer(p);
    await h.pipeline.planSequenceScenes(p, 1);
    final planner = h.llm.last(StudioStructurePrompts.scenesRole);
    expect(planner, contains('<places>'));
    expect(planner, contains('- The Kitchens:'));
    expect(planner, contains('<place>'));
    expect(planner, contains(StoryWorldContext.newPrefix));
    final scenes = p.scenes[0]!;
    expect(scenes[0].placeId, kitchens.id);
    expect(scenes[0].location, startsWith('The Kitchens — Early morning'));
    expect(scenes[1].placeId, '');
    expect(scenes[1].location, startsWith('the Gatehouse — Early morning'));

    await h.pipeline.runBeatDirector(p, 0, 0);
    final beats = h.llm.last(StudioProsePrompts.beatsRole);
    expect(beats, contains('<setting_now>'));
    expect(beats, contains('The Kitchens: Big flagstoned kitchens'));
    expect(beats, contains('Greenhollow Estate: A rambling'));

    await h.pipeline.runDraftAndEdit(p, 0, 0, 0);
    final writer = h.llm.last(StudioProsePrompts.writerRole);
    expect(writer, contains('<setting_now>'));
    expect(writer, contains('The Kitchens: Big flagstoned kitchens'));
    final lore = _between(writer, '<relevant_lore>', '</relevant_lore>');
    final topics = _topics(lore);
    expect(topics.length, greaterThanOrEqualTo(2));
    expect(kitchensTopics, containsAll(topics.take(2)));

    // A planner-invented place gets the world at large, never another room.
    await h.pipeline.runBeatDirector(p, 0, 1);
    final gatehouse = h.llm.last(StudioProsePrompts.beatsRole);
    expect(gatehouse, contains('Greenhollow Estate: A rambling'));
    expect(gatehouse, isNot(contains('The Kitchens: Big flagstoned')));
    await h.dispose();
  });

  test(
    'Studio without a world is unchanged: no world blocks, lore as before',
    () async {
      final empty = StoryWorldBrief(chain: const [], places: const []);
      final h = await _harness(empty, _studio);
      final p = await h.repo.createProject(title: 'No World');
      p
        ..engineMode = StoryEngineMode.studio
        ..targetWords = 30000
        ..reviewEnabled = false
        ..concept = 'A house.';
      await h.repo.saveProject(p);
      await h.pipeline.runStoryArchitect(p);
      await h.pipeline.runActStructurer(p);
      await h.pipeline.planSequenceScenes(p, 1);
      expect(
        h.llm.last(StudioBiblePrompts.foundationRole),
        isNot(contains('<setting_world>')),
      );
      expect(
        h.llm.last(StudioStructurePrompts.scenesRole),
        isNot(contains('<places>')),
      );
      expect(p.lore.map((e) => e.topic), ['The library key']);
      expect(p.scenes[0]!.first.placeId, '');
      expect(
        p.scenes[0]!.first.location,
        'Early morning, the long table laid.',
      );
      await h.dispose();
    },
  );

  test('Quick: the architect reads the world, locations resolve to places, '
      'and the drafter sees where it is and the lore that applies', () async {
    final h = await _harness(g.brief, _quick);
    final p = await h.repo.createProject(title: 'The Locked Library');
    p
      ..engineMode = StoryEngineMode.quick
      ..actCount = 1
      ..concept = 'The housekeeper finds the locked library open.'
      ..worldId = g.brief.start!.id
      ..worldName = g.root.name;
    await h.repo.saveProject(p);

    await h.pipeline.runStoryArchitect(p);
    final architect = h.llm.last('Input Concept:');
    expect(architect, contains('SETTING WORLD'));
    expect(architect, contains('World: Greenhollow Estate'));
    expect(p.lore.where(isWorldLore), hasLength(11));
    expect(p.lore.last.topic, 'The library key');

    await h.pipeline.runActStructurer(p);
    await h.pipeline.runSceneWeaver(p, 0);
    expect(
      h.llm.last('creating scenes for ACT'),
      contains('PLACES IN THE WORLD'),
    );
    final scenes = p.scenes[0]!;
    expect(scenes[0].placeId, kitchens.id);
    expect(scenes[0].location, 'The Kitchens — morning, the bread oven lit');
    expect(scenes[1].placeId, '');
    expect(scenes[1].location, 'the Gatehouse — dusk');

    await h.pipeline.runBeatDirector(p, 0, 0);
    await h.pipeline.runDraftAndEdit(p, 0, 0, 0);
    final drafter = h.llm.last('Write the prose now');
    expect(drafter, contains('## Where'));
    expect(drafter, contains('The Kitchens: Big flagstoned kitchens'));
    expect(drafter, contains('## Relevant lore'));
    final topics = _topics(_between(drafter, '## Relevant lore', '## Style'));
    expect(topics.length, greaterThanOrEqualTo(2));
    expect(kitchensTopics, containsAll(topics.take(2)));
    await h.dispose();
  });

  test('the Director resolves a <place> detail onto the scene', () {
    final p = StoryProject(title: 'T', worldId: g.brief.start!.id);
    p.acts = [StoryAct(number: 1, title: 'One', description: '')];
    p.sequences = [StorySequence(number: 1, act: 1, title: 'Seq')];
    p.scenes[0] = [
      StoryScene(number: 1, id: 's1', sequence: 1, location: 'The porch'),
    ];
    final outcome = StoryDirectorApply.apply(
      p,
      DirectorAction(
        type: DirectorActionType.modifyScene,
        sceneId: 's1',
        details: {'place': 'the old orchard'},
      ),
      world: g.brief,
    );
    expect(outcome.error, isNull);
    final orchard = g.places.firstWhere((w) => w.name == 'The Old Orchard');
    expect(p.scenes[0]!.single.placeId, orchard.id);
    expect(p.scenes[0]!.single.location, 'The Old Orchard — The porch');
  });
}
