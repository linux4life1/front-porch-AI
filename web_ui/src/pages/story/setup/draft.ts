// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Everything New Story collects (Idea, Cast, Shape, Engine), held as plain
// state while the person walks the steps, and the two conversions to and from
// the project JSON. Web twin of lib/ui/story_setup/story_setup_draft.dart:
// loadFrom ↔ draftFromProject, applyTo ↔ applyDraft.

import {
  TARGET_LENGTHS,
  type StoryJob,
  type StoryLaneChoice,
  type StoryLaneJson,
  type StoryLaneKind,
  type StoryProject,
} from '../../../storyTypes';

export type EngineMode = 'quick' | 'studio';
export type StoryFormat = 'novel' | 'audioDrama';

/** The slice of `GET /api/characters` the wizard needs. */
export interface CharacterRow {
  id: string;
  name: string;
  hasAvatar?: boolean;
  avatarVersion?: number;
}

/** The chat a story starts from: one character, one session. */
export interface ChatSource {
  characterId: string;
  characterName: string;
  sessionId: string;
  messageCount: number;
  faithful: boolean;
}

export interface Draft {
  title: string;
  concept: string;
  chatSource: ChatSource | null;
  castIds: string[];
  roles: Record<string, string>;
  includePersona: boolean;
  personaRole: string;
  useChatHistory: boolean;
  proseLength: string;
  storyFormat: StoryFormat;
  pov: string;
  genres: string[];
  moods: string[];
  writingStyle: string;
  pace: string;
  dialogue: string;
  maturity: string;
  engineMode: EngineMode;
  actCount: number;
  reviewEnabled: boolean;
  lensesEnabled: boolean;
  lanes: Record<StoryJob, StoryLaneChoice>;
  tier: string;
}

/** Studio always builds three acts and eight sequences. */
export const STUDIO_ACT_COUNT = 3;
export const JOBS: { job: StoryJob; label: string }[] = [
  { job: 'planning', label: 'Planning' },
  { job: 'prose', label: 'Prose' },
  { job: 'review', label: 'Review' },
];

const blankLane = (lane: StoryLaneKind): StoryLaneChoice => ({ lane, backend: '', url: '', model: '', kcpps: '' });
export const chatLane = () => blankLane('main');
export const workerLane = () => blankLane('worker');

export function emptyDraft(): Draft {
  return {
    title: '',
    concept: '',
    chatSource: null,
    castIds: [],
    roles: {},
    includePersona: false,
    personaRole: 'Love Interest',
    useChatHistory: false,
    proseLength: 'Standard',
    storyFormat: 'novel',
    pov: 'Third Person Limited',
    genres: [],
    moods: [],
    writingStyle: '',
    pace: 'Balanced',
    dialogue: 'Balanced',
    maturity: 'Mature',
    engineMode: 'studio',
    actCount: STUDIO_ACT_COUNT,
    reviewEnabled: true,
    lensesEnabled: true,
    lanes: { planning: chatLane(), prose: chatLane(), review: workerLane() },
    tier: 'frontier',
  };
}

export function targetWordsFor(proseLength: string): number {
  return TARGET_LENGTHS.find((t) => t.key === proseLength)?.words ?? 80000;
}

// ── Lanes ────────────────────────────────────────────────────────────────

const str = (v: unknown) => (typeof v === 'string' ? v : '');
const laneKind = (v: unknown): StoryLaneKind | null => (v === 'main' || v === 'worker' || v === 'host' ? v : null);

/** A stored lane: an object, or the bare lane name older projects hold. */
export function laneFromJson(raw: unknown, fallback: StoryLaneChoice): StoryLaneChoice {
  if (typeof raw === 'string') return { ...blankLane(laneKind(raw) ?? fallback.lane) };
  if (raw && typeof raw === 'object') {
    const o = raw as Record<string, unknown>;
    return {
      lane: laneKind(o.lane) ?? fallback.lane,
      backend: str(o.backend),
      url: str(o.url),
      model: str(o.model),
      kcpps: str(o.kcpps),
    };
  }
  return { ...fallback };
}

/** A lane's label before the relay has answered: what the choice is called, without the model. */
export function fallbackLaneLabel(l: StoryLaneChoice): string {
  if (l.lane === 'host') return l.model ? `Another host · ${l.model}` : 'Another host · no model picked';
  return l.lane === 'worker' ? 'Worker model' : 'Same as chat';
}

/** What `model_lanes` and `POST /api/stories/lane-label` take. */
export function laneToJson(l: StoryLaneChoice): StoryLaneJson {
  return l.lane === 'host'
    ? { lane: 'host', backend: l.backend, url: l.url, model: l.model, kcpps: l.kcpps }
    : { lane: l.lane };
}

// ── Chat as the source ───────────────────────────────────────────────────

/** Start from a chat: the character joins the cast as protagonist, the chat becomes canon, an empty idea gets a seed. */
export function adoptChat(d: Draft, source: ChatSource, userName: string): Draft {
  const castIds = d.castIds.includes(source.characterId) ? d.castIds : [...d.castIds, source.characterId];
  const roles = source.characterId in d.roles ? d.roles : { ...d.roles, [source.characterId]: 'Protagonist' };
  const concept = d.concept.trim()
    ? d.concept
    : source.faithful
      ? `A faithful novelization of the roleplay between ${source.characterName} and ${userName}: the real events of their chat, retold as prose.`
      : `A story inspired by the roleplay between ${source.characterName} and ${userName}.`;
  // Fit the length to the chat unless one was already chosen.
  const proseLength = source.faithful && source.messageCount > 0 && d.proseLength === 'Standard'
    ? suggestedLengthForChat(source.messageCount)
    : d.proseLength;
  return { ...d, chatSource: source, useChatHistory: true, castIds, roles, concept, proseLength };
}

/** Roughly how many chat messages each length needs before a faithful retelling stops being mostly invented. Twin of kChatMessagesForLength. */
export const CHAT_MESSAGES_FOR_LENGTH: Record<string, number> = { Short: 60, Standard: 150, Epic: 400 };

/** The length a faithful retelling of a chat this size starts on. */
export function suggestedLengthForChat(messages: number): string {
  return messages < CHAT_MESSAGES_FOR_LENGTH.Standard ? 'Short' : 'Standard';
}

/** Plain words for a faithful chat too small for the chosen length, or null when it fits (0 messages = size unknown). */
export function lengthWarning(d: Draft): string | null {
  const messages = d.chatSource?.messageCount ?? 0;
  const needed = CHAT_MESSAGES_FOR_LENGTH[d.proseLength];
  if (!toneFromChat(d) || messages <= 0 || needed === undefined || messages >= needed) return null;
  const count = `${messages} message${messages === 1 ? '' : 's'}`;
  return d.proseLength === 'Short'
    ? `This chat has ${count}. Even the shortest length is a 30,000-word novella, so most of the story will be invented around the chat.`
    : `This chat has ${count}. A story this long will be mostly invented. A shorter length stays closer to the chat.`;
}

/** A faithful retelling takes its genre and mood from the chat: the Shape step hides both pickers and nothing picked earlier is saved. */
export function toneFromChat(d: Draft): boolean {
  return d.chatSource?.faithful ?? false;
}

export function dropChat(d: Draft): Draft {
  const source = d.chatSource;
  if (!source) return { ...d, useChatHistory: false };
  const roles = { ...d.roles };
  delete roles[source.characterId];
  return {
    ...d,
    chatSource: null,
    useChatHistory: false,
    castIds: d.castIds.filter((id) => id !== source.characterId),
    roles,
  };
}

// ── Project ↔ draft ──────────────────────────────────────────────────────

export function draftFromProject(p: StoryProject, chars: CharacterRow[]): Draft {
  const d = emptyDraft();
  d.title = p.title === 'Untitled Story' ? '' : p.title;
  d.concept = p.concept ?? '';
  d.tier = p.prompt_tier || d.tier;
  const fresh = !d.concept.trim() && (p.acts ?? []).length === 0;
  d.engineMode = fresh ? 'studio' : (p.engine_mode ?? 'studio');
  d.storyFormat = p.story_format === 'audioDrama' ? 'audioDrama' : 'novel';
  d.lanes = {
    planning: laneFromJson(p.model_lanes?.planning, chatLane()),
    prose: laneFromJson(p.model_lanes?.prose, chatLane()),
    review: laneFromJson(p.model_lanes?.review, workerLane()),
  };
  d.reviewEnabled = p.review_enabled !== false;
  d.lensesEnabled = p.lenses_enabled !== false;
  d.useChatHistory = !!p.use_chat_history;
  d.castIds = [...(p.chat_history_character_ids ?? [])];
  d.includePersona = !!p.include_user_persona;
  if (p.user_persona_role) d.personaRole = p.user_persona_role;
  for (const snap of p.character_card_snapshots ?? []) {
    if (snap.self_insert === 'true') continue;
    const id = d.castIds.includes(snap.id) ? snap.id : chars.find((c) => c.name === snap.name && d.castIds.includes(c.id))?.id;
    if (id) d.roles[id] = snap.role || 'Supporting';
  }
  const sessions = p.chat_history_session_ids ?? [];
  if (sessions.length > 0 && d.castIds.length > 0) {
    const id = d.castIds[0];
    d.chatSource = {
      characterId: id,
      characterName: chars.find((c) => c.id === id)?.name ?? 'the chat',
      sessionId: sessions[0],
      messageCount: 0,
      faithful: !!p.faithful_mode,
    };
  }
  d.pov = p.pov || d.pov;
  d.actCount = Math.min(5, Math.max(1, p.act_count || STUDIO_ACT_COUNT));
  d.genres = [...(p.selected_genres ?? [])];
  d.moods = [...(p.selected_moods ?? [])];
  d.writingStyle = p.writing_style ?? '';
  d.proseLength = p.prose_length || d.proseLength;
  d.pace = p.narrative_pace || d.pace;
  d.dialogue = p.dialogue_density || d.dialogue;
  d.maturity = p.maturity_rating || d.maturity;
  return d;
}

/** The card/persona snapshots the pipeline reads (roles ride along). The relay rebuilds the card text from the ids. */
function buildSnapshots(base: StoryProject, d: Draft, chars: CharacterRow[], personaName: string): Record<string, string>[] {
  const existing = base.character_card_snapshots ?? [];
  const out: Record<string, string>[] = [];
  for (const id of d.castIds) {
    const c = chars.find((x) => x.id === id);
    if (!c) continue;
    const prev = existing.find((s) => s.self_insert !== 'true' && (s.id === id || s.name === c.name));
    out.push({
      description: '', personality: '', scenario: '', first_message: '', system_prompt: '',
      ...prev, id, name: c.name, role: d.roles[id] ?? 'Supporting',
    });
  }
  if (d.includePersona) {
    const prev = existing.find((s) => s.self_insert === 'true' && s.name === personaName);
    out.push({
      personality: '', scenario: '', first_message: '', system_prompt: '',
      ...prev, name: personaName, role: d.personaRole, self_insert: 'true',
    });
  }
  return out;
}

/** Write every choice onto the project. `character_roles` is the id → role map the relay builds the snapshots from. */
export function applyDraft(base: StoryProject, d: Draft, chars: CharacterRow[], personaName: string): StoryProject {
  const roles: Record<string, string> = {};
  for (const id of d.castIds) roles[id] = d.roles[id] ?? 'Supporting';
  return {
    ...base,
    title: d.title.trim() || 'Untitled Story',
    concept: d.concept.trim(),
    prompt_tier: d.tier,
    engine_mode: d.engineMode,
    target_words: targetWordsFor(d.proseLength),
    story_format: d.storyFormat,
    model_lanes: {
      planning: laneToJson(d.lanes.planning),
      prose: laneToJson(d.lanes.prose),
      review: laneToJson(d.lanes.review),
    },
    review_enabled: d.reviewEnabled,
    lenses_enabled: d.lensesEnabled,
    use_chat_history: d.useChatHistory && d.castIds.length > 0,
    chat_history_character_ids: [...d.castIds],
    chat_history_session_ids: d.chatSource ? [d.chatSource.sessionId] : [],
    faithful_mode: d.chatSource?.faithful ?? false,
    include_user_persona: d.includePersona,
    user_persona_role: d.personaRole,
    pov: d.pov,
    act_count: d.engineMode === 'studio' ? STUDIO_ACT_COUNT : d.actCount,
    selected_genres: toneFromChat(d) ? [] : [...d.genres],
    selected_moods: toneFromChat(d) ? [] : [...d.moods],
    writing_style: d.writingStyle,
    prose_length: d.proseLength,
    narrative_pace: d.pace,
    dialogue_density: d.dialogue,
    maturity_rating: d.maturity,
    character_card_snapshots: buildSnapshots(base, d, chars, personaName),
    character_roles: roles,
  };
}
