// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TypeScript shapes for Porch Stories. Keys are snake_case to match the Dart
// StoryProject.toJson/fromJson round-trip exactly — the client sends the whole
// project object back on save, so unknown/nested fields must survive untouched.

export interface StoryListItem {
  id: string;
  title: string;
  concept: string;
  actCount: number;
  hasProse: boolean;
  updatedAt: string;
  // Enriched fields for the library card (genre/mood line, granular status,
  // tier badge) — mirror the desktop home cards.
  genre: string;
  mood: string;
  tier: string;
  engine?: string;
  sceneCount: number;
  proseCount: number;
  hasConcept: boolean;
}

/** A quick-concept seed for the setup wizard (genre/style/concept). */
export interface StoryArchetype {
  label: string;
  value: string;
}

/** A TTS voice for the per-character read-along picker. */
export interface StoryVoice {
  id: string;
  name: string;
  engine: string;
}

export interface StoryStyle {
  genre: string;
  mood: string;
  writing_guide: string;
}

export interface StoryCastMember {
  name: string;
  role: string;
  description: string;
  voice_sample?: string;
  voice_model?: string;
  details: Record<string, string>;
  flaw?: string;
  desire?: string;
  interview?: string;
  portrait?: string;
}

/** A sequence: a run of scenes inside an act bound by one dramatic question. */
export interface StorySequence {
  number: number;
  act: number;
  title: string;
  function: string;
  dramatic_question: string;
  description: string;
  climax: string;
  ending_hook: string;
  thread_ids: string[];
  summary: string;
}

export interface RelationshipShift {
  scene_id: string;
  from: string;
  to: string;
  reason: string;
}

/** How `from` sees `to`. Directed: A→B and B→A are separate rows. */
export interface StoryRelationship {
  from: string;
  to: string;
  feeling: string;
  note: string;
  subtext: string;
  trust: number;
  history: RelationshipShift[];
}

export interface ContinuityFact {
  category: string;
  key: string;
  value: string;
  entity: string;
  scene_id: string;
  retired_scene_id?: string;
}

export interface StoryLens {
  id: string;
  name: string;
  context: string;
  glyph: string;
}

export interface ProseEdit {
  find: string;
  replace: string;
}

export interface ContinuityFix {
  reason: string;
  before: string;
  edits: ProseEdit[];
}

export interface DirectorAction {
  type: string;
  scene_id: string;
  beat: number;
  sequence: number;
  act: number;
  summary: string;
  details: Record<string, string>;
  enabled: boolean;
  locked: boolean;
  result: string;
}

export interface DirectorPlan {
  directive: string;
  evaluation: string;
  scope: 'local' | 'arc';
  consistency_notes: string;
  actions: DirectorAction[];
  review: string;
  created_at: string;
}

export interface DirectorApplied {
  directive: string;
  applied_at: string;
  change_count: number;
}

/** One quality chip the server computed for a passage. */
export interface QualityChip {
  label: string;
  tone: 'plain' | 'good' | 'warn' | 'bad';
}

/** One model call from the story's run log. */
export interface StoryRunEntry {
  at: string;
  stage: string;
  role: string;
  backend: string;
  attempt: number;
  verdict: string;
  note: string;
  millis: number;
  tokens: number;
  prompt: string;
  response: string;
}

export interface StoryThread {
  id: string;
  name: string;
  description: string;
}

export interface StoryLoreEntry {
  topic: string;
  detail: string;
  related_to: string[];
  valid_from_act: number;
  valid_from_scene: number;
}

export interface StoryAct {
  number: number;
  title: string;
  description: string;
  focus_thread_ids: string[];
  knots: { description: string; interaction: string }[];
}

export interface StoryScene {
  number: number;
  title: string;
  description: string;
  location: string;
  cast_names: string[];
  valence: number;
  id?: string;
  sequence?: number;
  scene_type?: string;
  lens?: string;
  tension?: number;
  value_from?: string;
  value_to?: string;
  objective?: string;
  pov?: string;
  commitments?: string;
  entry?: string;
  exit?: string;
  summary?: string;
}

export interface StoryBeat {
  number: number;
  type: string;
  description: string;
  emotional_shift: string;
  valence: number;
  pacing: number;
  initiator?: string;
  reactor?: string;
  subtext?: string;
  anchor?: string;
}

export interface BeatProse {
  draft?: string;
  final?: string;
  fix?: ContinuityFix;
}

// The full project. Editable fields are typed; scenes/beats/prose are kept as
// opaque maps so they round-trip untouched through a save.
export interface StoryProject {
  id: string;
  title: string;
  concept: string;
  status_quo: string;
  inciting_incident: string;
  themes: string;
  style: StoryStyle;
  prompt_tier: string;
  use_chat_history: boolean;
  chat_history_character_ids: string[];
  character_card_snapshots: Record<string, string>[];
  include_user_persona: boolean;
  user_persona_role: string;
  pov: string;
  act_count: number;
  selected_genres: string[];
  selected_moods: string[];
  writing_style: string;
  prose_length: string;
  narrative_pace: string;
  dialogue_density: string;
  maturity_rating: string;
  distilled_timeline: string;
  last_read_page_index: number;
  cast: StoryCastMember[];
  threads: StoryThread[];
  lore: StoryLoreEntry[];
  acts: StoryAct[];
  scenes: Record<string, StoryScene[]>;
  beats: Record<string, StoryBeat[]>;
  prose: Record<string, BeatProse>;
  // Studio engine (all optional on the wire; the server defaults them).
  engine_mode?: 'quick' | 'studio';
  target_words?: number;
  story_format?: 'novel' | 'audioDrama';
  model_lanes?: { planning: string; prose: string; review: string };
  review_enabled?: boolean;
  lenses_enabled?: boolean;
  sequences?: StorySequence[];
  relationships?: StoryRelationship[];
  continuity?: ContinuityFact[];
  twists?: string;
  banned_phrases?: string[];
  auto_banned_phrases?: string[];
  director_plan?: DirectorPlan | null;
  director_applied?: DirectorApplied | null;
  reader_mode?: 'book' | 'scroll';
  reader_scroll?: number;
  [key: string]: unknown;
}

export interface StoryStatus {
  running: boolean;
  stopping?: boolean;
  step: string;
  status: string;
  tokens: number;
}

/** Target length choices (stored key → label), same words as the desktop. */
export const TARGET_LENGTHS: { key: string; label: string; words: number }[] = [
  { key: 'Short', label: 'Novella · 30k', words: 30000 },
  { key: 'Standard', label: 'Novel · 80k', words: 80000 },
  { key: 'Epic', label: 'Epic · 120k', words: 120000 },
];

// ── Option lists (1:1 with the desktop StorySetupPage) ──
export const POV_OPTIONS = [
  'First Person',
  'Third Person Limited',
  'Third Person Omniscient',
];

/** Story-character roles (first selected character defaults to Protagonist). */
export const ROLE_OPTIONS = [
  'Protagonist',
  'Antagonist',
  'Supporting',
  'Love Interest',
  'Mentor',
];

export const GENRES = [
  'Fantasy', 'Sci-Fi', 'Romance', 'Thriller', 'Horror', 'Literary Fiction',
  'Mystery', 'Historical', 'Comedy', 'Drama', 'Adventure', 'Dystopian',
  'Paranormal', 'Western', 'Slice of Life',
];
export const MOODS = [
  'Dark', 'Light', 'Gritty', 'Whimsical', 'Melancholy', 'Tense', 'Hopeful',
  'Bittersweet', 'Eerie', 'Nostalgic', 'Epic', 'Intimate', 'Satirical',
];
export const WRITING_STYLES = [
  'Minimalist', 'Lyrical/Poetic', 'Pulpy/Action', 'Literary', 'Conversational',
  'Gothic', 'Hardboiled', 'Philosophical', 'Cinematic', 'Fairy-Tale',
];

// Length / pace / dialogue / maturity carry explanatory subtitles on desktop.
export const PROSE_LENGTHS: Record<string, string> = {
  Short: 'Novella (~30K words)',
  Standard: 'Novel (~80K words)',
  Epic: 'Epic (~120K words)',
};
export const PACES: Record<string, string> = {
  'Slow Burn': 'Atmospheric, detailed worldbuilding',
  Balanced: 'Mix of action and reflection',
  'Fast-Paced': 'Tight scenes, rapid plot movement',
};
export const DIALOGUE: Record<string, string> = {
  Sparse: 'Mostly narrative prose',
  Balanced: 'Even mix of dialogue and prose',
  'Dialogue-Heavy': 'Character-driven, lots of conversation',
};
export const MATURITY: Record<string, string> = {
  Clean: 'All ages, no violence or language',
  Mature: 'Adult themes, moderate violence',
  Explicit: 'Graphic content, no restrictions',
};

export const PROMPT_TIERS: { value: string; label: string }[] = [
  { value: 'frontier', label: 'Full detail — for cloud APIs' },
  { value: 'largLocal', label: 'Rich — for big local models (70B+)' },
  { value: 'smallLocal', label: 'Simplified — for small local models (7-34B)' },
];

/** Short label for a prompt tier (library card badge). */
export const TIER_LABELS: Record<string, string> = {
  frontier: 'Frontier',
  largLocal: 'Large Local',
  smallLocal: 'Small Local',
};

/** Beat-type → CSS modifier class for the colored badge in the writer. */
export const BEAT_TYPE_CLASS: Record<string, string> = {
  Action: 'action',
  Reaction: 'reaction',
  Dialogue: 'dialogue',
  Revelation: 'revelation',
  Resolution: 'resolution',
  Environment: 'environment',
  Reflection: 'reflection',
  Memory: 'reflection',
  Sensory: 'sensory',
  Transition: 'transition',
};

/** Pacing index → glyph (0 Slow, 1 Balanced, 2 Fast). */
export const PACING_GLYPH = ['🐢', '➖', '⚡'];
export const PACING_LABEL = ['Slow', 'Balanced', 'Fast'];
