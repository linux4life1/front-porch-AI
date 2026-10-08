// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryProject } from '../../../storyTypes';
import {
  adoptChat, applyDraft, dropChat, draftFromProject, emptyDraft, laneFromJson, laneToJson,
  type CharacterRow, type ChatSource,
} from './draft';

const chars: CharacterRow[] = [
  { id: 'c1', name: 'Mara Vell' },
  { id: 'c2', name: 'Joss Harrow' },
];
const chat: ChatSource = { characterId: 'c1', characterName: 'Mara Vell', sessionId: '1700', messageCount: 12, faithful: true };
const blank = { id: 's1', title: 'Untitled Story', concept: '', acts: [], character_card_snapshots: [] } as unknown as StoryProject;

describe('New Story draft ↔ project JSON', () => {
  it('writes the snake_case fields the desktop project reads', () => {
    let d = adoptChat(emptyDraft(), chat, 'Teodor');
    d = {
      ...d, title: ' The Salt Road ', castIds: ['c1', 'c2'], roles: { c1: 'Protagonist', c2: 'Antagonist' },
      includePersona: true, personaRole: 'Mentor', proseLength: 'Epic', storyFormat: 'audioDrama',
      pov: 'First Person', genres: ['Fantasy'], moods: ['Dark'], writingStyle: 'Gothic', pace: 'Slow Burn',
      dialogue: 'Sparse', maturity: 'Explicit', engineMode: 'quick', actCount: 4, tier: 'smallLocal',
      reviewEnabled: false, lensesEnabled: false,
    };
    const p = applyDraft(blank, d, chars, 'Teodor');
    // The chat is a faithful retelling, so the picked genre and mood are not saved.
    expect(p).toMatchObject({
      title: 'The Salt Road', engine_mode: 'quick', target_words: 120000, story_format: 'audioDrama', act_count: 4,
      prompt_tier: 'smallLocal', pov: 'First Person', selected_genres: [], selected_moods: [],
      writing_style: 'Gothic', prose_length: 'Epic', narrative_pace: 'Slow Burn', dialogue_density: 'Sparse',
      maturity_rating: 'Explicit', review_enabled: false, lenses_enabled: false, include_user_persona: true,
      user_persona_role: 'Mentor', use_chat_history: true, chat_history_character_ids: ['c1', 'c2'],
      chat_history_session_ids: ['1700'], faithful_mode: true,
      character_roles: { c1: 'Protagonist', c2: 'Antagonist' },
    });
    expect(p.character_card_snapshots.map((s) => [s.name, s.role, s.self_insert])).toEqual([
      ['Mara Vell', 'Protagonist', undefined],
      ['Joss Harrow', 'Antagonist', undefined],
      ['Teodor', 'Mentor', 'true'],
    ]);
  });

  it('Studio always builds three acts, whatever the Quick act count says', () => {
    const p = applyDraft(blank, { ...emptyDraft(), engineMode: 'studio', actCount: 5 }, chars, 'User');
    expect(p.act_count).toBe(3);
  });

  it('round-trips through the project, roles and chat included', () => {
    const d = { ...adoptChat(emptyDraft(), { ...chat, faithful: false }, 'Teodor'), genres: ['Fantasy', 'Horror'], roles: { c1: 'Mentor' } };
    const back = draftFromProject(applyDraft(blank, d, chars, 'Teodor'), chars);
    expect(back).toMatchObject({
      castIds: ['c1'], roles: { c1: 'Mentor' }, genres: ['Fantasy', 'Horror'], useChatHistory: true,
      chatSource: { characterId: 'c1', sessionId: '1700', faithful: false },
    });
  });

  it('a faithful retelling saves no picked genre or mood; "Inspired by" keeps them', () => {
    const picked = { ...adoptChat(emptyDraft(), chat, 'Teodor'), genres: ['Horror'], moods: ['Dark'] };
    expect(applyDraft(blank, picked, chars, 'Teodor')).toMatchObject({ selected_genres: [], selected_moods: [] });
    const inspired = { ...picked, chatSource: { ...chat, faithful: false } };
    expect(applyDraft(blank, inspired, chars, 'Teodor')).toMatchObject({ selected_genres: ['Horror'], selected_moods: ['Dark'] });
  });

  it('removing the chat takes its character out of the cast', () => {
    const d = dropChat({ ...adoptChat(emptyDraft(), chat, 'Teodor'), castIds: ['c1', 'c2'], roles: { c1: 'Protagonist', c2: 'Supporting' } });
    expect(d).toMatchObject({ chatSource: null, useChatHistory: false, castIds: ['c2'], roles: { c2: 'Supporting' } });
  });

  it('does not overwrite an idea the person already wrote when a chat is chosen', () => {
    expect(adoptChat({ ...emptyDraft(), concept: 'My own idea' }, chat, 'Teodor').concept).toBe('My own idea');
  });

  it('reads a lane stored as an object, or as the bare name older projects hold', () => {
    const fallback = laneFromJson('main', laneFromJson(undefined, { lane: 'main', backend: '', url: '', model: '', kcpps: '' }));
    expect(laneFromJson('worker', fallback).lane).toBe('worker');
    const host = laneFromJson({ lane: 'host', backend: 'openRouter', url: 'u', model: 'm', kcpps: '' }, fallback);
    expect(laneToJson(host)).toEqual({ lane: 'host', backend: 'openRouter', url: 'u', model: 'm', kcpps: '' });
    expect(laneToJson({ ...host, lane: 'main' })).toEqual({ lane: 'main' });
  });
});
