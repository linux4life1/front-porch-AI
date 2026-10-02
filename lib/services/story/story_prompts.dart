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

import 'package:front_porch_ai/models/models.dart';

/// Prompt templates for every Porch Stories pipeline stage. Extracted
/// verbatim from `story_pipeline_service.dart` (Cluster D of the god-file
/// split) — pure, static, zero pipeline state; each builder takes only the
/// [StoryProject]/[PromptTier] data it needs.
///
/// **Do not reflow these string literals.** `integration_test/support/
/// fake_backend.dart` sniffs their exact opening sentences to route stages
/// to the right canned reply — a reformatted prompt breaks E2E silently.
abstract final class StoryPrompts {
  /// Planning stages answer in tags: a small model that drops a comma
  /// ruins a whole JSON reply, while a tag reply degrades one field at a
  /// time. A model that answers in JSON anyway is still read
  /// (StoryQuickXml falls back to the JSON parser).
  static String _jsonInstruction(PromptTier tier) {
    switch (tier) {
      case PromptTier.frontier:
        return 'Answer with the tags below and nothing else — no markdown fences, no commentary before or after. Wrap the whole answer in <response>…</response>.';
      case PromptTier.largLocal:
        return 'IMPORTANT: Answer ONLY with the tags below, wrapped in <response>…</response>. No other text.';
      case PromptTier.smallLocal:
        return 'ANSWER WITH THE TAGS BELOW ONLY, INSIDE <response>…</response>. NO OTHER TEXT.';
    }
  }

  /// Build a compact block of user preferences to inject into prompts.
  static String _userPrefsBlock(StoryProject project) {
    final parts = <String>[];
    parts.add('POV: ${project.pov}');
    if (project.selectedGenres.isNotEmpty) {
      parts.add('Genre: ${project.selectedGenres.join(", ")}');
    }
    if (project.selectedMoods.isNotEmpty) {
      parts.add('Mood: ${project.selectedMoods.join(", ")}');
    }
    if (project.writingStyle.isNotEmpty) {
      parts.add('Writing Style: ${project.writingStyle}');
    }
    parts.add('Prose Length: ${project.proseLength}');
    parts.add('Narrative Pace: ${project.narrativePace}');
    parts.add('Dialogue Density: ${project.dialogueDensity}');
    parts.add('Maturity Rating: ${project.maturityRating}');
    parts.add('Number of Acts: ${project.actCount}');
    return 'USER PREFERENCES:\n${parts.join("\n")}';
  }

  static String storyArchitect(StoryProject project) {
    final tier = project.promptTier;
    final prefs = _userPrefsBlock(project);
    if (tier == PromptTier.smallLocal) {
      return '''Create a story bible from the concept. Match the user's preferences.

$prefs

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <concept>refined summary</concept>
  <status_quo>the normal world before the plot begins</status_quo>
  <inciting_incident>the event that breaks the status quo</inciting_incident>
  <themes>core ideas explored</themes>
  <style><genre>...</genre><mood>...</mood><writing_guide>tone instructions</writing_guide></style>
  <threads><thread><id>t1</id><name>Main Arc</name><description>...</description></thread></threads>
  <protagonist><name>...</name><role>Protagonist</role><description>...</description><voice_sample>sample dialogue</voice_sample><details><history>...</history><goals>...</goals><evolution>...</evolution></details></protagonist>
  <world_lore><entry><topic>Setting</topic><detail>...</detail><related_to>related topic, another</related_to></entry></world_lore>
</response>''';
    }
    return '''You are a Lead Narrative Designer. Input: A concept. Task: Deconstruct this into a rich Story Bible.

$prefs

REQUIREMENTS:
1. STATUS QUO: Define the "Normal World" before the plot begins.
2. INCITING INCIDENT: Define the specific event that breaks the status quo.
3. PROTAGONIST: Deep dive into personality, flaws, and specific voice.
4. THEMES: What philosophical or emotional questions are being explored?
5. STYLE: Match the user's requested genre, mood, and writing style preferences listed above.
6. POV: Use the POV specified above (${project.pov}).

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <concept>Refined summary</concept>
  <status_quo>Description of the normal world...</status_quo>
  <inciting_incident>The specific event...</inciting_incident>
  <themes>The core ideas being explored...</themes>
  <style>
    <genre>...</genre>
    <mood>...</mood>
    <writing_guide>Instructions for the writer on tone and voice</writing_guide>
  </style>
  <threads>
    <thread><id>t1</id><name>Main Arc</name><description>...</description></thread>
    <thread><id>t2</id><name>Relationship Arc</name><description>...</description></thread>
    <thread><id>t3</id><name>Subplot Arc</name><description>...</description></thread>
  </threads>
  <protagonist>
    <name>Name</name>
    <role>Protagonist</role>
    <description>Physical and personality</description>
    <voice_sample>Dialogue sample</voice_sample>
    <details><history>Backstory...</history><story_events>Start...</story_events><goals>...</goals><evolution>...</evolution></details>
  </protagonist>
  <world_lore>
    <entry><topic>Setting</topic><detail>...</detail><related_to>Related topic</related_to></entry>
  </world_lore>
</response>''';
  }

  static String actStructure(int actCount, PromptTier tier) {
    final actExamples = List.generate(actCount, (i) {
      final n = i + 1;
      return '    <act><number>$n</number><title>...</title><description>full act description</description><focus_thread_ids>t1</focus_thread_ids><knots><knot><description>event</description><interaction>how threads interact</interaction></knot></knots></act>';
    }).join('\n');

    if (tier == PromptTier.smallLocal) {
      return '''Create a $actCount-act story structure.
The first act is setup, the last act is resolution. Middle acts are confrontation and rising action.

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <acts>
$actExamples
  </acts>
</response>''';
    }

    String actGuidance;
    if (actCount == 1) {
      actGuidance =
          'Act 1: Complete arc -- setup, confrontation, and resolution in a single act.';
    } else if (actCount == 2) {
      actGuidance =
          'Act 1 (Setup): Establish the world and characters, end with the inciting crisis.\nAct 2 (Resolution): Confrontation, climax, and resolution.';
    } else if (actCount == 3) {
      actGuidance =
          'Act I (The Thesis): The Status Quo. Must end with a one-way door decision.\nAct II (The Antithesis): The Crucible. Must have a midpoint shift and end at "All Hope Is Lost."\nAct III (The Synthesis): The protagonist proves they have changed. Climax where external and internal goals collide.';
    } else if (actCount == 4) {
      actGuidance =
          'Act 1 (Setup): Establish the world and characters.\nAct 2 (Rising Action): Complications mount, alliances shift.\nAct 3 (Crisis): Everything falls apart, darkest hour.\nAct 4 (Resolution): The protagonist transforms and resolves the conflict.';
    } else {
      actGuidance =
          'Act 1 (Setup): Establish the world and characters.\nAct 2 (Complication): Initial obstacles and discoveries.\nAct 3 (Midpoint Shift): Everything changes, new stakes.\nAct 4 (Crisis): Darkest hour, all seems lost.\nAct 5 (Resolution): Transformation, climax, and resolution.';
    }

    return '''You are an author developing story structure. Define exactly $actCount Acts.

$actGuidance

THREAD REQUIREMENT: Define 2-3 "Convergence Events" (Knots) per act where threads intersect.

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <acts>
$actExamples
  </acts>
</response>''';
  }

  static String sceneWeaver(int actNumber, PromptTier tier) {
    final sceneCount = actNumber == 2
        ? '4-6'
        : (actNumber == 1 ? '3-5' : '3-4');

    if (tier == PromptTier.smallLocal) {
      return '''Create $sceneCount scenes for Act $actNumber. Each scene needs: number, title, description, location, cast, and a valence score (-10 to +10).

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <scenes>
    <scene><number>1</number><title>...</title><description>what happens</description><active_thread_ids>t1</active_thread_ids><location>...</location><cast_names>Hero, Friend</cast_names><valence>0</valence><causality><interaction_type>Isolation</interaction_type><description>...</description></causality></scene>
  </scenes>
  <new_characters><character><name>...</name><role>...</role><description>...</description></character></new_characters>
</response>''';
    }
    return '''You are an author creating scenes for ACT $actNumber.

Generate $sceneCount scenes. Each scene must:
- Have a clear purpose (advance plot, reveal character, or both)
- Follow causality: each scene occurs because of the previous one
- Manage tension: oscillate between high/low intensity, with rising overall trend
- Be clear about location, setting, and characters present
${actNumber == 1 ? '- Scene 1 MUST introduce the protagonist and the world to the reader. Ground the reader in who, where, and what.\n- Early scenes should establish characters before throwing them into conflict.' : ''}

THREAD INTERACTION:
- Isolation: Only advances one thread
- Collision: Two threads conflict
- Resonance: Two threads thematically align

Assign valence (-10 to +10) to each scene for emotional charge.

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <scenes>
    <scene>
      <number>1</number>
      <title>Scene Title</title>
      <description>detailed plot events and authorial intent</description>
      <active_thread_ids>t1</active_thread_ids>
      <location>Setting</location>
      <cast_names>Hero, Friend</cast_names>
      <valence>0</valence>
      <causality><interaction_type>Isolation</interaction_type><description>Establishes Hero's situation.</description></causality>
    </scene>
  </scenes>
  <new_characters><character><name>...</name><role>...</role><description>...</description></character></new_characters>
</response>''';
  }

  static String beatDirector(PromptTier tier) {
    if (tier == PromptTier.smallLocal) {
      return '''Break this scene into 6-8 beats. Each beat is a small narrative unit with action and emotional change.

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <beats>
    <beat><number>1</number><type>Action</type><description>what happens and why</description><emotional_shift>how mood changes</emotional_shift><valence>0</valence><pacing>1</pacing></beat>
  </beats>
</response>''';
    }
    return '''You are the architect of a single narrative scene. Break it into 6-10 distinct beats.

For each beat consider:
- Someone wants something. Someone opposes it. Something changes.
- Assign a tactic (active verb) so characters are active, not passive
- Create a gap between expectation and reality
- Ensure emotional change within each beat
- Vary types: Action, Reaction, Dialogue, Revelation, Resolution

PACING: 0=Slow (atmospheric), 1=Balanced (dialogue-heavy), 2=Fast (action/conflict)
VALENCE: -10 to +10, oscillating to maintain tension

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <beats>
    <beat><number>1</number><type>Action</type><description>what happens, who is involved, authorial intent</description><emotional_shift>How the mood changes</emotional_shift><valence>4</valence><pacing>1</pacing></beat>
  </beats>
</response>''';
  }

  static String drafter(StoryProject project) {
    final pov = project.pov;
    final tier = project.promptTier;
    final pace = project.narrativePace;
    final dialogue = project.dialogueDensity;
    final style = project.writingStyle.isNotEmpty
        ? '\n- Match the "${project.writingStyle}" writing style.'
        : '';
    if (tier == PromptTier.smallLocal) {
      return '''Write 400-600 words of prose for the current beat. Use $pov POV consistently. Use short paragraphs (2-4 sentences each). Include dialogue where characters are present. Flow from the previous beat and end naturally before the next beat.''';
    }
    return '''You are an award-winning author working on your next novel. Write the prose for the CURRENT BEAT in 400-600 words.

CRITICAL RULES:
- Use $pov point of view consistently. NEVER switch POV mid-scene.
- Use SHORT PARAGRAPHS -- 2-4 sentences maximum per paragraph. Insert blank lines between paragraphs.
- Dialogue density: $dialogue. ${dialogue == 'Dialogue-Heavy'
        ? 'Most of the prose should be character dialogue.'
        : dialogue == 'Sparse'
        ? 'Use dialogue sparingly; focus on internal narrative and description.'
        : 'Balance dialogue with narration.'}
- Narrative pace: $pace. ${pace == 'Slow Burn'
        ? 'Linger on atmosphere and sensory details.'
        : pace == 'Fast-Paced'
        ? 'Keep sentences tight. Favor action verbs. No lingering.'
        : 'Mix reflection with forward momentum.'}$style
- The text must flow smoothly from the previous beat
- End just before the next beat begins
- Show, don't tell -- use vivid sensory details
- Each character must have a distinct voice in dialogue
- Characters must be actively pursuing their goals''';
  }

  static String editor(StoryProject project) {
    final pov = project.pov;
    final tier = project.promptTier;
    final povCheck = pov == 'First Person'
        ? 'ENFORCE FIRST PERSON POV. If any text uses third person for the narrator, rewrite it to first person.'
        : 'ENFORCE ${pov.toUpperCase()} POV. If any text uses first person ("I", "my", "me") for narration, rewrite it to third person.';
    if (tier == PromptTier.smallLocal) {
      return '''Polish this prose draft. Fix any POV shifts (must be $pov). Break long paragraphs. Fix weak verbs, cut exposition, ensure distinct character voices. Return ONLY the polished prose text.''';
    }
    return '''You are a Ruthless Editor. Polish the following draft.

Rules:
1. $povCheck
2. BREAK UP WALL-OF-TEXT. No paragraph should exceed 4 sentences. Insert paragraph breaks.
3. Cut exposition. Show through action and dialogue.
4. Strengthen verbs -- replace passive voice and weak verbs.
5. Ensure character voice matches their personality.
6. Fix filter words (e.g., "He saw the box" -> "The box sat on the table").
7. Check continuity: no references to future events.
8. Give each character a distinct voice.
9. Ensure characters actively pursue goals.
10. Remove repetition and crutch words (e.g., "the particular", "the specific", "the weight of").
11. Ensure clear cause and effect with emotional state shifts.
12. Character reactions: visceral -> emotional -> intellectual -> action/speech.
13. ELIMINATE REPETITION: Flag and rewrite any repeated phrases, metaphors, adjectives, or sentence patterns. Each paragraph must feel fresh.

Return ONLY the polished prose text, nothing else.''';
  }

  static String archivist(PromptTier tier) {
    if (tier == PromptTier.smallLocal) {
      return '''Analyze the text. Return JSON with cast_updates (history/goals changes) and lore_updates (new facts about the world). Max 4 lore items.

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <cast_updates><update><name>...</name><append_history>...</append_history><append_story_events>...</append_story_events><update_goals>...</update_goals></update></cast_updates>
  <lore_updates><entry><topic>...</topic><detail>...</detail><related_to>...</related_to></entry></lore_updates>
</response>''';
    }
    return '''You are the Story Archivist. Analyze the just-written text and return UPDATES.

1. CAST UPDATES:
- Did a character reveal new backstory?
- Did a major event happen to them?
- Did their goal change?

2. LORE UPDATES:
- New location or object described in detail?
- Max 1-4 items. Do NOT duplicate existing lore.

${_jsonInstruction(tier)}

Answer in this shape:
<response>
  <cast_updates>
    <update><name>Hero</name><append_history>...</append_history><append_story_events>...</append_story_events><update_goals>...</update_goals></update>
  </cast_updates>
  <lore_updates>
    <entry><topic>...</topic><detail>...</detail><related_to>...</related_to></entry>
  </lore_updates>
</response>''';
  }

  static String beatValidator(PromptTier tier) {
    return '''You are a Script Doctor. Check if the written prose allows the next planned beat to happen.

If YES: <response><valid>true</valid><reason></reason><rectified_beats></rectified_beats></response>
If NO: <response><valid>false</valid><reason>why it's invalid</reason><rectified_beats><beat><number>2</number><type>Action</type><description>rewritten future beat</description><emotional_shift>...</emotional_shift><valence>0</valence><pacing>1</pacing></beat></rectified_beats></response>

${_jsonInstruction(tier)}''';
  }
}
