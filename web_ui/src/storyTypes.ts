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

export const POV_OPTIONS = [
  'First Person',
  'Third Person Limited',
  'Third Person Omniscient',
];
export const GENRES = [
  'Fantasy', 'Sci-Fi', 'Romance', 'Mystery', 'Thriller', 'Horror',
  'Adventure', 'Drama', 'Comedy', 'Historical', 'Slice of Life', 'Dystopian',
];
export const MOODS = [
  'Dark', 'Light', 'Gritty', 'Whimsical', 'Tense', 'Cozy',
  'Melancholic', 'Hopeful', 'Epic', 'Intimate',
];
export const WRITING_STYLES = ['Minimalist', 'Lyrical', 'Pulpy', 'Literary', 'Cinematic'];
export const PROSE_LENGTHS = ['Short', 'Standard', 'Epic'];
export const PACES = ['Slow Burn', 'Balanced', 'Fast-Paced'];
export const DIALOGUE = ['Sparse', 'Balanced', 'Dialogue-Heavy'];
export const MATURITY = ['Clean', 'Mature', 'Explicit'];
export const PROMPT_TIERS: { value: string; label: string }[] = [
  { value: 'frontier', label: 'Frontier (cloud APIs / large models)' },
  { value: 'largLocal', label: 'Large local (70B+)' },
  { value: 'smallLocal', label: 'Small local (7–13B)' },
];
