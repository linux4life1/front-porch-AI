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

// The pure Studio leaves: tag parsing, review verdicts, pacing, prose
// quality, surgical edits, the continuity ledger and structural re-keying.
// Each pin was first run against a deliberately broken helper to see it go
// red (a tolerant parser that passes on garbage is decoration).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';

StoryProject _project() {
  final p = StoryProject(
    title: 'The Salt Road',
    engineMode: StoryEngineMode.studio,
    acts: [
      StoryAct(number: 1, title: 'Debt'),
      StoryAct(number: 2, title: 'Fire'),
      StoryAct(number: 3, title: 'Ash'),
    ],
    cast: [
      StoryCastMember(name: 'Mara Vell', role: 'Protagonist'),
      StoryCastMember(name: 'Joss Rane', role: 'Antagonist'),
      StoryCastMember(name: 'Teodor Ash', role: 'Love Interest'),
    ],
  );
  p.sequences = [
    for (final slot in StoryPacing.sequenceSlots)
      StorySequence(number: slot.number, act: slot.act, title: slot.function),
  ];
  p.scenes[0] = [
    StoryScene(id: 'a', number: 1, title: 'Ledger', sequence: 1),
    StoryScene(id: 'b', number: 2, title: 'Roof', sequence: 1),
    StoryScene(id: 'c', number: 3, title: 'Fire', sequence: 2),
  ];
  p.beats['0-1'] = [
    StoryBeat(number: 1, description: 'one'),
    StoryBeat(number: 2, description: 'two'),
  ];
  p.prose['0-1-0'] = BeatProse(final_: 'roof one');
  p.prose['0-1-1'] = BeatProse(final_: 'roof two');
  p.beats['0-2'] = [StoryBeat(number: 1, description: 'fire')];
  p.prose['0-2-0'] = BeatProse(final_: 'fire one');
  return p;
}

void main() {
  group('StoryXml', () {
    test('reads tags through fences, prose and an unclosed think block', () {
      const raw =
          '<think>let me plan\n'
          'Sure! Here you go:\n```xml\n<response>\n'
          '  <title>Night on the roof</title>\n'
          '  <scene_type>REACTION</scene_type>\n'
          '  <characters_present><character>Mara &amp; co</character>'
          '<character>Teodor</character></characters_present>\n'
          '</response>\n```';
      final text = StoryXml.clean(raw);
      expect(StoryXml.tag(text, 'title'), 'Night on the roof');
      expect(StoryXml.list(text, 'characters_present', 'character'), [
        'Mara & co',
        'Teodor',
      ]);
      expect(StoryXml.tag(text, 'missing'), '');
    });

    test('a reply cut off before its closing tag still yields the field', () {
      const raw = '<response><status_quo>The town sleeps';
      expect(StoryXml.tag(raw, 'status_quo'), 'The town sleeps');
    });

    test('nested same-name tags stay one block', () {
      const raw =
          '<scene><title>A</title><scene>inner</scene></scene>'
          '<scene><title>B</title></scene>';
      final blocks = StoryXml.all(raw, 'scene');
      expect(blocks.length, 2);
      expect(StoryXml.tag(blocks[0], 'title'), 'A');
    });
  });

  group('StoryReview', () {
    test('tag verdicts, issue severities and loose shapes', () {
      final fail = StoryReview.parse(
        '<response><issues><issue><severity>MINOR</severity>'
        '<description>nit</description></issue><issue><severity>CRITICAL'
        '</severity><description>Joss teleported</description>'
        '<location>"at the gate"</location></issue></issues>'
        '<status>FAIL</status></response>',
      );
      expect(fail.pass, isFalse);
      expect(fail.problems, ['Joss teleported']);
      expect(fail.reasons.single, contains('at the gate'));

      expect(StoryReview.parse('Status: PASS — fine.').pass, isTrue);
      expect(StoryReview.parse('{"valid": false}').pass, isFalse);
      final unreadable = StoryReview.parse('I think it reads well.');
      expect(unreadable.pass, isTrue);
      expect(unreadable.parsed, isFalse);
    });
  });

  group('StoryPacing', () {
    test('budgets land on the word target', () {
      for (final target in [30000, 80000, 120000]) {
        final pacing = StoryPacing.forTarget(target);
        final mid =
            StoryPacing.sequenceSlots.length *
            (pacing.scenesMin + pacing.scenesMax) /
            2 *
            (pacing.beatsMin + pacing.beatsMax) /
            2 *
            StoryPacing.wordsPerBeat;
        expect(mid, closeTo(target, target * 0.25), reason: '$target');
        expect(pacing.summary, contains('8 sequences'));
      }
      expect(
        StoryPacing.forTarget(80000).scenesFor(4).max,
        StoryPacing.forTarget(80000).scenesFor(1).max + 1,
      );
    });
  });

  group('StoryQuality', () {
    test('counts words, dialogue, rhythm and banned phrases', () {
      const prose =
          '"We leave at dawn," Mara said. The yard was quiet. '
          'Smoke rolled low across the broken wagons, and nobody moved to '
          'stop it. "You first," Joss said quietly. The weight of it sat '
          'between them like a third person at the table.';
      final q = StoryQuality.analyze(
        prose,
        bannedPhrases: ['the weight of it', 'jaw tightened'],
      );
      expect(q.wordCount, greaterThan(30));
      expect(q.dialogueRatio, greaterThan(0.1));
      expect(q.bannedMatches, ['the weight of it']);
      expect(q.chips.last.label, '1 banned phrase');
      expect(q.chips.last.tone, QualityTone.bad);
      expect(q.sensoryPer100, greaterThan(0));
    });

    test('overused phrases ignore names and keep the longest form', () {
      final text = List.filled(
        4,
        'Mara took a breath she did not know she was holding. ',
      ).join();
      final phrases = StoryQuality.overusedPhrases(
        text,
        exclude: ['Mara Vell'],
      );
      expect(phrases, isNotEmpty);
      expect(phrases.any((p) => p.contains('mara')), isFalse);
      expect(phrases.first.split(' ').length, 4);
    });
  });

  group('StoryEdits', () {
    test('applies find→replace through curly quotes and refuses rewrites', () {
      const prose =
          'Joss stood at the gate, already shouting her name. '
          'Mara had the ledger under her arm.';
      final edits = StoryEdits.parse(
        '<edits><edit><find>Joss stood at the gate,</find>'
        '<replace>Joss came off the wagon step in one lurch,</replace>'
        '</edit><edit><find>not in the text</find><replace>x</replace>'
        '</edit></edits>',
      );
      final report = StoryEdits.apply(prose, edits);
      expect(report.applied.length, 1);
      expect(report.failed.length, 1);
      expect(report.text, startsWith('Joss came off the wagon step'));
      expect(StoryEdits.changeRatio(prose, report.text), lessThan(0.6));

      // Typographic quotes in the prose, straight ones from the model.
      const curly = 'He said “stay” and left.';
      expect(StoryEdits.locate(curly, 'said "stay"'), isNotNull);
      expect(
        StoryEdits.changeRatio(prose, 'Entirely different words here.'),
        greaterThan(0.6),
      );
    });
  });

  group('StoryContinuity', () {
    test('facts are known after their scene and retired by a newer one', () {
      final p = _project();
      StoryContinuity.record(
        p,
        ContinuityFact(
          category: 'object',
          key: "Joss's wagon",
          value: 'intact',
          sceneId: 'a',
        ),
      );
      StoryContinuity.record(
        p,
        ContinuityFact(
          category: 'Object',
          key: "joss's wagon",
          value: 'burned to the axles',
          sceneId: 'c',
        ),
      );
      expect(p.continuity.length, 2);
      expect(p.continuity.first.isRetired, isTrue);
      expect(StoryContinuity.knownAt(p, 0, 1).map((f) => f.value), ['intact']);
      expect(StoryContinuity.knownAt(p, 0, 2).map((f) => f.value), ['intact']);
      // Scene after the fire: only the new fact.
      p.scenes[0]!.add(StoryScene(id: 'd', number: 4, sequence: 2));
      expect(StoryContinuity.knownAt(p, 0, 3).map((f) => f.value), [
        'burned to the axles',
      ]);
      expect(StoryContinuity.forPrompt(p, 0, 3), contains('[Object]'));
    });

    test('relationship shifts keep history and forgetScene undoes them', () {
      final p = _project();
      StoryContinuity.shift(
        p,
        from: 'Mara',
        to: 'Teodor',
        feeling: 'Curious',
        trust: 4,
      );
      StoryContinuity.shift(
        p,
        from: 'mara vell',
        to: 'Teodor Ash',
        feeling: 'Drawn to',
        sceneId: 'b',
        reason: 'the roof',
      );
      final rel = p.relationship('Mara Vell', 'Teodor Ash')!;
      expect(rel.feeling, 'Drawn to');
      expect(rel.history.length, 2);
      StoryContinuity.forgetScene(p, 'b');
      expect(rel.feeling, 'Curious');
      expect(StoryContinuity.tone(8), 'warm');
    });
  });

  group('StoryStructure', () {
    test('insert, remove and move re-key beats and prose', () {
      final p = _project();
      StoryStructure.insertScene(
        p,
        0,
        1,
        StoryScene(number: 0, title: 'New', sequence: 1),
      );
      expect(p.scenes[0]!.map((s) => s.title), [
        'Ledger',
        'New',
        'Roof',
        'Fire',
      ]);
      expect(p.prose['0-2-1']!.final_, 'roof two');
      expect(p.prose['0-3-0']!.final_, 'fire one');
      expect(p.beats['0-1'], isNull);

      StoryStructure.removeScene(p, 0, 0);
      expect(p.scenes[0]!.first.title, 'New');
      expect(p.prose['0-1-0']!.final_, 'roof one');

      StoryStructure.moveScene(p, 0, 2, 1);
      expect(p.scenes[0]!.map((s) => s.title), ['New', 'Fire', 'Roof']);
      expect(p.prose['0-1-0']!.final_, 'fire one');
      expect(p.prose['0-2-1']!.final_, 'roof two');
      expect(p.sceneLabel(0, 1), '2.1');
      expect(p.scenes[0]!.map((s) => s.number), [1, 2, 3]);
    });

    test('beat insert and remove shift prose keys', () {
      final p = _project();
      StoryStructure.insertBeat(
        p,
        0,
        1,
        0,
        StoryBeat(number: 0, description: 'zero'),
      );
      expect(p.beats['0-1']!.map((b) => b.number), [1, 2, 3]);
      expect(p.prose['0-1-0'], isNull);
      expect(p.prose['0-1-1']!.final_, 'roof one');
      StoryStructure.removeBeat(p, 0, 1, 1);
      expect(p.prose['0-1-1']!.final_, 'roof two');
      expect(p.prose['0-1-2'], isNull);
    });
  });

  group('StoryQuickXml', () {
    test('tags fold into the maps the Quick stages already read', () {
      final acts = StoryQuickXml.parse(
        'acts',
        '<response><acts><act><number>1</number><title>Debt</title>'
            '<description>d</description><focus_thread_ids>t1, t2</focus_thread_ids>'
            '<knots><knot><description>k</description><interaction>i</interaction>'
            '</knot></knots></act></acts></response>',
      )!;
      final act = (acts['acts'] as List).single as Map<String, dynamic>;
      expect(act['number'], 1);
      expect(act['focus_thread_ids'], ['t1', 't2']);
      expect((act['knots'] as List).single['interaction'], 'i');

      final beats = StoryQuickXml.parse(
        'beats',
        '<beats><beat><number>1</number><type>Dialogue</type>'
            '<description>x</description><valence>-3</valence><pacing>2</pacing>'
            '</beat></beats>',
      )!;
      expect((beats['beats'] as List).single['valence'], -3);

      final valid = StoryQuickXml.parse('validator', '<valid>false</valid>')!;
      expect(valid['valid'], isFalse);

      // A model that still answers in JSON is read the old way.
      final json = StoryQuickXml.parse('scenes', '{"scenes":[{"number":2}]}')!;
      expect((json['scenes'] as List).single['number'], 2);
      expect(StoryQuickXml.parse('scenes', 'nothing here'), isNull);
    });
  });

  group('StoryProject shape', () {
    test('a pre-sequence story upgrades to one sequence per act on load', () {
      final legacy = StoryProject(
        acts: [
          StoryAct(number: 1, title: 'One'),
          StoryAct(number: 2, title: 'Two'),
        ],
      );
      legacy.scenes[1] = [StoryScene(number: 1, title: 'x')];
      final reloaded = StoryProject.fromJsonString(legacy.toJsonString());
      expect(reloaded.engineMode, StoryEngineMode.quick);
      expect(reloaded.sequences.map((s) => s.act), [1, 2]);
      expect(reloaded.scenes[1]!.single.sequence, 2);
      expect(reloaded.scenes[1]!.single.id, isNotEmpty);
      expect(reloaded.sceneLabel(1, 0), '2.1');
      expect(reloaded.targetWords, 80000);
    });

    test('studio fields round-trip through JSON', () {
      final p = _project()
        ..reviewLane = StoryLaneChoice.chat()
        ..storyFormat = StoryFormat.audioDrama
        ..directorPlan = DirectorPlan(
          directive: 'd',
          actions: [
            DirectorAction(
              type: DirectorActionType.editProse,
              sceneId: 'b',
              summary: 's',
              locked: true,
            ),
          ],
        );
      final back = StoryProject.fromJsonString(p.toJsonString());
      expect(back.reviewLane.lane, StoryModelLane.main);
      expect(back.storyFormat, StoryFormat.audioDrama);
      expect(
        back.directorPlan!.actions.single.type,
        DirectorActionType.editProse,
      );
      expect(back.directorPlan!.actions.single.locked, isTrue);
      expect(back.sequences.length, 8);
      expect(
        DirectorActionType.fromWire('modify scene'),
        DirectorActionType.modifyScene,
      );
      expect(DirectorActionType.editProse.wire, 'EDIT_PROSE');
    });
  });
}
