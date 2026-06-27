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
  voice_model?: string;
  details: Record<string, string>;
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
}

export interface StoryBeat {
  number: number;
  type: string;
  description: string;
  emotional_shift: string;
  valence: number;
  pacing: number;
}

export interface BeatProse {
  draft?: string;
  final?: string;
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
  [key: string]: unknown;
}

export interface StoryStatus {
  running: boolean;
  step: string;
  status: string;
  tokens: number;
}

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
  Short: 'Novella (~20K words)',
  Standard: 'Novel (~50K words)',
  Epic: 'Long novel (~80K+ words)',
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
  { value: 'frontier', label: 'Frontier (cloud APIs / large models)' },
  { value: 'largLocal', label: 'Large local (70B+)' },
  { value: 'smallLocal', label: 'Small local (7–13B)' },
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
};

/** Pacing index → glyph (0 Slow, 1 Balanced, 2 Fast). */
export const PACING_GLYPH = ['🐢', '➖', '⚡'];
export const PACING_LABEL = ['Slow', 'Balanced', 'Fast'];
