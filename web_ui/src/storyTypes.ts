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
  // Older enriched fields; the shelf reads `shelf` and `genreLine` below.
  genre: string;
  mood: string;
  tier: string;
  engine?: string;
  sceneCount: number;
  proseCount: number;
  hasConcept: boolean;
  // The shelf (desktop sketch H): one wording for both surfaces. The relay
  // computes these through the same Dart helpers the desktop shelf calls, so
  // the page shows `shelf.status` and `genreLine` verbatim.
  setupStep?: number | null;
  wordCount: number;
  targetWords: number;
  genreLine: string;
  shelf: StoryShelfState;
}

/** Where a story stands on the shelf: status line, bar fraction, finished, still in setup. */
export interface StoryShelfState {
  status: string;
  fraction: number;
  done: boolean;
  setup: boolean;
}

/** Which model runs a job: the chat model, the worker model, or another host. */
export type StoryLaneKind = 'main' | 'worker' | 'host';

/** One job's model. `backend`/`url`/`model`/`kcpps` only matter for `lane: 'host'`. */
export interface StoryLaneChoice {
  lane: StoryLaneKind;
  backend: string;
  url: string;
  model: string;
  kcpps: string;
}

/** A lane as stored under `model_lanes`: host details only ride along for `lane: 'host'`. */
export interface StoryLaneJson {
  lane: StoryLaneKind;
  backend?: string;
  url?: string;
  model?: string;
  kcpps?: string;
}

/** The three jobs a story assigns a model to (`model_lanes` keys). */
export type StoryJob = 'planning' | 'prose' | 'review';

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
  chat_history_session_ids?: string[];
  faithful_mode?: boolean;
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
  // Each lane is an object; projects saved before the model picker hold a bare
  // lane name ('main' | 'worker') instead.
  model_lanes?: Partial<Record<StoryJob, StoryLaneJson | string>>;
  /** Set while New Story is unfinished (the step to resume at); null/absent once done. */
  setup_step?: number | null;
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
  /** What was typed in the Director's box, kept when you leave the section. */
  director_draft?: string;
  /** "Protect written prose": absent means on. */
  director_protect?: boolean;
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
  /** The prose the model has produced so far for the beat being written (the Write screen streams it in place). */
  streamingText?: string;
}

/** Target length choices (stored key → label), same words as the desktop. */
export const TARGET_LENGTHS: { key: string; label: string; words: number }[] = [
  { key: 'Short', label: 'Novella · 30k', words: 30000 },
  { key: 'Standard', label: 'Novel · 80k', words: 80000 },
  { key: 'Epic', label: 'Epic · 120k', words: 120000 },
];

// ── Option lists (1:1 with the desktop story_setup_draft.dart) ──
// Stored values are what the prompts read; the labels are what the user sees.
/** Told-from choices (stored value → label). */
export const POV_LABELS: Record<string, string> = {
  'First Person': 'First person',
  'Third Person Limited': 'Third person, close',
  'Third Person Omniscient': 'Third person, wide',
};

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

export const PACE_LABELS: Record<string, string> = {
  'Slow Burn': 'Slow',
  Balanced: 'Even',
  'Fast-Paced': 'Fast',
};
export const DIALOGUE_LABELS: Record<string, string> = {
  Sparse: 'Sparse',
  Balanced: 'Balanced',
  'Dialogue-Heavy': 'Heavy',
};
export const MATURITY_LABELS: Record<string, string> = {
  Clean: 'All ages',
  Mature: 'Mature',
  Explicit: '18+',
};

export const PROMPT_TIERS: { value: string; label: string }[] = [
  { value: 'frontier', label: 'Full detail' },
  { value: 'largLocal', label: 'Rich' },
  { value: 'smallLocal', label: 'Simplified' },
];

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
