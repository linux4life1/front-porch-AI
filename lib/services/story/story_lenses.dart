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

/// Narrative lenses: a per-scene writing mode, each with its own style
/// direction. The built-in set and its wording come from EllipsisProse
/// (Apache-2.0, see NOTICE); users can add their own on top.
abstract final class StoryLenses {
  static const baseline = 'BASELINE_NEUTRAL';

  static final List<StoryLens> builtIn = List.unmodifiable([
    StoryLens(
      id: 'BASELINE_NEUTRAL',
      name: 'Balanced',
      context:
          'Default writing style. Balanced pacing with natural emotional warmth and narrative clarity.',
      prompt:
          'Establish a transparent, steady narrative rhythm by balancing action, dialogue, and grounded interiority so the reader stays immersed in the core genre. Emphasize emotional authenticity and natural character chemistry. Anchor any internal thoughts to present-moment sensory details or physical actions, keeping unbroken introspection to 1-2 sentences. Filter the environment through the POV character\'s immediate goals and emotional state. Prioritize specific tactile or auditory details over broad visual descriptions, actively avoiding generic clichés. Subvert predictive text by bypassing the most statistically obvious descriptive choices in favor of precise, unexpected sensory elements. Allow minor actions and dialogue to overlap and interrupt one another naturally, creating fluid choreography.',
    ),
    StoryLens(
      id: 'KINETIC_ACTION',
      name: 'Kinetic action',
      context:
          'High-momentum physical sequences. Visceral pacing with sharp sensory focus.',
      prompt:
          'Drive visceral momentum through strict parataxis—short, severed sentences that mirror breathless urgency. Filter the environment through the body: weight, momentum, gravity, spatial awareness of threats and barriers. Prioritize kinesthesia and violent tactile friction over visual tracking, avoiding ubiquitous action clichés. Excavate precise, muscular verbs of mass and velocity. Internal thought is minimal—instinct and reaction dominate. Dialogue emerges in sharp fragments uttered mid-movement. Allow actions to overlap, interrupt, and cascade into immediate consequences rather than unfolding in rigid sequence.',
    ),
    StoryLens(
      id: 'BUILDING_ROMANCE',
      name: 'Building romance',
      context:
          'Establishing chemistry, yearning, and romantic tension. Focus on the "slow burn" and gravity between characters.',
      prompt:
          'Cultivate an atmosphere of electric tension and yearning by radically dilating narrative time so the reader feels the magnetic gravity between the characters. Filter the environment through hyper-awareness of proximity and desire. Shift sensory focus to radiant heat, the friction of breath, and the displacement of air. Push the prose past standard romantic clichés by inventing idiosyncratic, highly specific physical details that capture the terrifying vulnerability of attraction. Focus on micro-gestures: the exact mechanics of a gaze, the negative space between hands, the involuntary lean. Utilize flowing, unhurried sentence structures. Manifest attraction through concrete sensory correlatives rather than abstract emotional labels. Dialogue should be subtextual and hesitant, with overlapping, unfinished sentences serving as a proxy for physical intimacy.',
    ),
    StoryLens(
      id: 'ATMOSPHERIC_SUSPENSE',
      name: 'Suspense',
      context:
          'Stealth, hunting, creeping dread. Focus on paranoia and the dilation of time.',
      prompt:
          'Instill creeping dread and paranoia by stretching time—use long, hypotactic sentences that delay the primary verb until the end of the paragraph. Filter the environment through the character\'s fear of the unknown: the geometry of shadows, blind spots, and thresholds. Prioritize micro-acoustics and negative space over visual clarity, avoiding generic suspense clichés. Manufacture hyper-specific, mundane auditory triggers that ground the paranoia in reality. Convey fear through the physiological reality of hyper-vigilance rather than naming the emotion directly. Allow brief, anchored internal dread (1-2 sentences) that heightens the tension. Dialogue is hushed, urgent, and overlapping. Choreograph agonizingly slow movements that are abruptly interrupted by shifting environmental variables.',
    ),
    StoryLens(
      id: 'VERBAL_SPARRING',
      name: 'Verbal sparring',
      context:
          'High-stakes arguments, negotiations, or interrogations. Dialogue drives the scene.',
      prompt:
          'Treat this sequence as a high-stakes exchange fought through rhetoric and subtext. Ensure each character uses a distinct vocabulary tier, rhythm, and rhetorical strategy rooted in their personality and motivations. Filter the environment through conversational tension; describe only the physical props that characters actively wield or manipulate to punctuate a point. Elevate the dialogue through rapid-fire, overlapping exchanges with minimal dialogue tags. Manufacture idiosyncratic, multi-layered rhetorical traps, evasions, and moments of disarming honesty rather than relying on standard angry retorts. Characters test each other out loud rather than retreating into deep internal strategy. Physical micro-movements overlap with the verbal strikes to control the pacing of the argument.',
    ),
    StoryLens(
      id: 'PROCEDURAL_MYSTERY',
      name: 'Mystery',
      context:
          'Investigations, analyzing clues, logical deduction. Focus on objective reality and empirical thought.',
      prompt:
          'Adopt a cold, methodical, empirical perspective. The character experiences the scene as a process of objective logical deduction. Filter the environment as a grid of variables, spatial relationships, and forensic anomalies, ignoring details that do not serve the working hypothesis. Prioritize specific tactile weights, precise measurements, and exact olfactory clues, avoiding generic investigator clichés. Seek the most precise noun for every object. Subvert the standard investigation by inventing bizarre, hyper-specific anomalies that challenge the characters rather than obvious clues. Suppress emotional hyperbole; let the intellectual fascination carry the tension. Externalize the deductive process through collaborative, interrogative dialogue. Characters move through the space simultaneously, examining evidence and overlapping their spoken hypotheses in real time.',
    ),
    StoryLens(
      id: 'GRAND_SCALE',
      name: 'Grand scale',
      context:
          'In-the-moment macro-scale events (e.g., troop movements, docking shuttles, arriving crowds).',
      prompt:
          'Pull the narrative camera back to capture sheer magnitude. Overwhelm the reader with the logistics and choreography of macro-forces while filtering the event through the tiny, vulnerable human perspective of awe, terror, or desperate resolve. Shift the sensory focus to kinesthetic pressure: the vibration of the ground, deafening synchronous noise, and atmospheric displacement. Avoid generic disaster clichés and bombastic purple prose. Forge unexpected, hyper-specific analogies that convey scale through stark juxtaposition with the mundane. Utilize sweeping, rhythmic sentence structures that build in volume. Ground the scale by having focal characters react vocally—shouting instructions, calling out to each other, or whispering prayers over the environmental noise.',
    ),
    StoryLens(
      id: 'WORLD_BUILDING',
      name: 'World-building',
      context:
          'Zooming in to creatively invent/explain specific details about histories, cultural practices, systems, or environments.',
      prompt:
          'Expand the world\'s lore through seamless, lived-in embedding so the reader absorbs complex rules or cultural histories without feeling lectured. Filter the lore through the POV character\'s personal bias—whether reverence, annoyance, or normalized routine—so the world feels inhabited. Anchor exposition in immediate sensory experience: specific tactile interactions with a relevant artifact, tool, or environmental detail. Avoid generic genre clichés. Manufacture defamiliarized sensory details that make the lore feel profoundly real and grounded. The prosody should be conversational but richly textured. Characters actively discuss, teach, or casually reference the lore through organic dialogue. Physical manipulation of world-building artifacts overlaps naturally with the spoken explanations.',
    ),
    StoryLens(
      id: 'LIGHTHEARTED',
      name: 'Lighthearted',
      context:
          'Comedic relief, joyful banter, whimsical situations providing a breather from heavy stakes.',
      prompt:
          'Elevate the tone to feel swift, bright, and buoyant through comedic juxtaposition and bathos, providing a joyful or absurd reprieve from heavier stakes. Filter the environment through buoyancy: absurdities, colorful contrasts, and whimsical inconveniences. Shift sensory focus toward quirky, unexpected inputs—a bizarre texture, an oddly pitched sound, a clumsy kinesthetic interaction. Avoid forced jokes, generic slapstick, or obvious witty clichés. Manufacture highly specific situational irony and understatements that rely on the characters\' contrasting worldviews. The prose should have a swift, bouncy prosody with sharp comedic pauses and overlapping dialogue. Allow characters to connect externally through warmth, banter, and genuine affection. Choreograph physical comedy and synchronized action: clumsy mistakes and environmental interactions happen simultaneously with the dialogue.',
    ),
    StoryLens(
      id: 'ORGANIC_EXPOSITION',
      name: 'Exposition',
      context:
          'Characters organically explaining context, plot, or plans to one another (e.g., heist planning).',
      prompt:
          'Transfer vital plot information without resorting to authorial info-dumping by treating the exposition as an active, character-driven event where the act of explaining is itself dramatic. Filter the environment through the interpersonal dynamics of the conversation; describe only the props, maps, or evidence the characters are actively using. Shift sensory focus to the tactile friction of these objects. Avoid dry recitations of facts. Invent idiosyncratic metaphors and analogies that characters use to explain complex plans. The prosody should shift dynamically based on who holds the conversational initiative. Characters challenge the information out loud, voicing skepticism, excitement, or trust through heated dialogue rather than summarizing internally. The environment is alive with pacing, interruptions, and the physical manipulation of evidence.',
    ),
    StoryLens(
      id: 'REVELATION',
      name: 'Revelation',
      context:
          'Major plot twists or the climax of a character arc where the truth shatters established reality.',
      prompt:
          'Deliver a narrative-shattering realization by structuring the scene around the moment of recognition—the instant the character\'s worldview cracks open. Filter the environment through this shattering: all broad descriptions vanish, replaced by hyper-fixation on a single, perfectly observed micro-detail that symbolically reflects the new reality. Shift the sensory hierarchy drastically: focus on the sudden kinesthetic sensation of vertigo, a precipitous temperature shift, or a single hyper-specific sound. Push the prose past standard epiphany markers; invent a deeply unsettling, specific physical response to the shock. Swell the prosody musically, beginning with tight, fragmented sentences that expand into breathless syntax. The epiphany overlaps directly with a raw, unfiltered vocal or physical reaction—dialogue stripped of all rhetorical polish.',
    ),
    StoryLens(
      id: 'UNCERTAINTY',
      name: 'Uncertainty',
      context:
          'Facing the terrifying unknown, groping in the dark, trying to understand a completely alien situation.',
      prompt:
          'Plunge the narrative into deep disorientation so the reader shares the character\'s terrifying inability to comprehend their situation. Filter the environment through a complete lack of context: describe common objects and environments as if encountered for the first time, stripping them of normal linguistic labels. Prioritize bizarre, unidentifiable textures, muffled acoustics, and disorienting kinesthetic feedback over visual clarity. Avoid generic clichés of darkness or cold. Forge unexpected, hyper-specific phrasing for mundane sensations that reflects the character\'s fractured comprehension. Utilize hesitant, fragmented prosody with frequent pauses. The character externalizes panic through questioning, unconfident dialogue—calling out to the void or to each other. Choreograph stumbling, hesitant physical reactions as they try to physically map an incomprehensible space.',
    ),
    StoryLens(
      id: 'REFLECTION',
      name: 'Reflection',
      context:
          'The aftermath of an event. Processing grief, trauma, or complex emotions in a grounded, embodied way.',
      prompt:
          'Guide the character through the aftermath of trauma or complex emotion using meandering, recursive sentence structures that mirror the nature of human memory. Filter the external world through the character\'s internal landscape: the environment mirrors or starkly contrasts their grief. Shift sensory focus to deeply specific, mundane tactile sensations that anchor their wandering mind. Convey emotion through precise physiological detail rather than naming it directly. Manufacture deeply personal, mundane symbolic actions that externalize the pain instead of relying on obvious grief tropes. Keep the character physically grounded—engaged in a repetitive task or moving through a familiar space—so their processing never becomes untethered rumination. Bring other characters into the space through quiet, deeply vulnerable dialogue that interrupts the physical rhythm.',
    ),
    StoryLens(
      id: 'RELATIONAL',
      name: 'Relational',
      context:
          'Non-romantic dialogue sequences deepening platonic, familial, or allied bonds; revealing backstory.',
      prompt:
          'Deepen the emotional connective tissue and shared history between characters by illustrating the unspoken rules and deep trust that govern their bond. Filter the physical space through safety, warmth, or shared history—the acoustic resonance of a familiar room, comfortable tactile interactions. Prioritize proximity and familiar friction. Avoid generic markers of friendship. Invent highly idiosyncratic micro-habits, shared shorthand, or nostalgic physical props that prove their long-term bond without explicitly explaining it. The prosody should be relaxed, with empathetic pacing and an easy rhythm. Allow characters to unspool their fears, affections, and vulnerabilities through organic, revealing dialogue. Choreograph seamless, synchronized collaborative tasks where their physical movements and casual interruptions overlap naturally.',
    ),
    StoryLens(
      id: 'ENVIRONMENTAL_IMMERSION',
      name: 'Immersion',
      context:
          'Sensory immersion in setting and atmosphere; exploring a new environment to ground the reader in place.',
      prompt:
          'Establish a profound sense of place and atmosphere by focusing on sensory immersion rather than immediate plot momentum, grounding the reader in the setting. Filter the architecture, weather, and ambient life through the character\'s initial emotional reaction to the space (alienation, wonder, claustrophobia), ensuring the environment is never described objectively. Utilize a sweeping, rhythmic prosody with rich sensory layering that slows the reader\'s pace to match the character\'s observation. Zoom in on highly specific, idiosyncratic micro-interactions rather than broad establishing shots. Avoid generic establishing clichés. Manufacture hyper-specific, localized textures and ambient noises that prove the world is deeply lived-in. Keep the character moving physically through the environment, brushing against the local texture and reacting to the sounds in real time. Brief anchored internal impressions (1-2 sentences) deepen the sense of place.',
    ),
    StoryLens(
      id: 'MORAL_DILEMMA',
      name: 'Moral dilemma',
      context:
          'The agonizing weight of an imminent, high-stakes decision; internal fracture and psychological pressure.',
      prompt:
          'Plunge the narrative into the agonizing weight of an imminent, high-stakes decision by actively wrestling with the thesis and antithesis of the character\'s choice so the reader feels the psychological pressure. Filter the environment through contrasts that mirror the fracturing of the character\'s resolve—light versus shadow, warmth versus cold, open spaces versus constraints. Use jagged, fragmented syntax and rhetorical questions that alternate between opposing justifications and terrifying consequences. Push the prose past standard physical markers of stress; invent idiosyncratic physical micro-tics or fixations on mundane objects that externalize the internal fracture. Keep the character physically engaged—interacting with a symbolic object, pacing, or gripping something—while their fractured rationalizations or fragmented dialogue overlap with these actions.',
    ),
    StoryLens(
      id: 'CATHARTIC_INTIMACY',
      name: 'Intimacy',
      context:
          'Transitioning from tension into profound emotional and physical vulnerability, raw intimacy, and dissolved boundaries.',
      prompt:
          'Dissolve the boundaries between characters, transitioning from tension into profound emotional and physical vulnerability by prioritizing raw intimacy over rhetorical defense. The outside world ceases to exist, leaving only the immediate, hyper-focused geography of the other person and the profound safety of the connection. Utilize breathless, flowing syntax that mimics the overwhelming sensory flood of the moment. Shift sensory focus entirely from visuals to the exact friction of skin, the displacement of weight, and the synchronization of breath. Push past generic romantic clichés; invent highly idiosyncratic, tactile micro-details that capture the unique physical reality of their specific bond. Strip dialogue of all rhetorical defense, reducing it to raw whispers or profound silence. Choreograph the scene so verbal confessions overlap seamlessly with synchronous physical micro-movements.',
    ),
  ]);

  static const Map<String, String> _glyphs = {
    'BASELINE_NEUTRAL': '◇',
    'KINETIC_ACTION': '➶',
    'BUILDING_ROMANCE': '♡',
    'ATMOSPHERIC_SUSPENSE': '◐',
    'VERBAL_SPARRING': '⚔',
    'PROCEDURAL_MYSTERY': '⌕',
    'GRAND_SCALE': '▲',
    'WORLD_BUILDING': '✦',
    'LIGHTHEARTED': '☀',
    'ORGANIC_EXPOSITION': '❝',
    'REVELATION': '✧',
    'UNCERTAINTY': '?',
    'REFLECTION': '☾',
    'RELATIONAL': '∞',
    'ENVIRONMENTAL_IMMERSION': '❖',
    'MORAL_DILEMMA': '⚖',
    'CATHARTIC_INTIMACY': '❦',
  };

  /// One-character mark for a lens, shared by desktop and web.
  static String glyph(String id) => _glyphs[id] ?? '✎';

  /// Built-ins plus the story's own lenses; a custom lens with a built-in id
  /// overrides it.
  static List<StoryLens> forProject(StoryProject project) {
    final custom = {for (final l in project.customLenses) l.id: l};
    return [
      for (final l in builtIn) custom.remove(l.id) ?? l,
      ...custom.values,
    ];
  }

  static StoryLens resolve(StoryProject project, String id) {
    final wanted = normalizeId(id);
    for (final l in forProject(project)) {
      if (l.id == wanted) return l;
    }
    return builtIn.first;
  }

  /// Models write lens ids loosely ("kinetic action", "Kinetic_Action").
  static String normalizeId(String raw) {
    final id = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    return id.isEmpty ? baseline : id;
  }

  /// The lens list as the planner sees it.
  static String catalog(StoryProject project) =>
      forProject(project).map((l) => '- ${l.id}: ${l.context}').join('\n');

  /// Scene intensity (-2..+2) said in words. A bare number means nothing to
  /// a model; a sentence does.
  static String tensionInstruction(int tension) {
    if (tension >= 2) {
      return 'This scene operates at maximum dramatic intensity. The narrative should feel breathless, visceral, and urgent. Focus on crisis, immediate physical or emotional conflict, and explosive momentum.';
    }
    if (tension == 1) {
      return 'This scene operates at a moderate tension. The narrative should feel active and driving. Focus on tactical maneuvering, rising complications, and escalating stakes.';
    }
    if (tension == -1) {
      return 'This scene operates at a low intensity. The narrative should feel transitional and interactive. Focus on negotiations, travel, regrouping, and simmering subtext rather than overt conflict.';
    }
    if (tension <= -2) {
      return 'This scene operates at minimum intensity. The narrative should feel calm, reflective, and decompression-focused. Focus on character interiority, quiet contemplation, and tender or vulnerable bonding.';
    }
    return '';
  }

  /// Filled bars (1–4) for the tension meter.
  static int tensionBars(int tension) => switch (tension) {
    <= -2 => 1,
    -1 => 2,
    0 => 2,
    1 => 3,
    _ => 4,
  };
}
