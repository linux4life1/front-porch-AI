// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Step 1 of 4: title, the idea, sparks, "start from a chat", and "where does
// it happen?" (docs/design/stories-in-worlds.md §5). Web twin of
// lib/ui/story_setup/idea_step.dart.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../../api/client';
import { adoptChat, dropChat, isGroupSource, sourceCastLine, type CharacterRow, type ChatSource, type Draft } from './draft';
import { ChatSourcePicker } from './ChatSourcePicker';
import { Avatar, ConfirmDialog, Field, KeyLabel, Note, Segmented } from './primitives';
import { characterAvatar } from './useSetupData';
import { loadWorldSummary, pickFromSummary, WORLD_GONE } from './worldPick';
import { WorldPicker } from './WorldPicker';
import { Chip } from '../StudioShell';

interface Archetype {
  label: string;
  spark?: string;
  value: string;
}

const SPARK_COUNT = 4;
const LEAD = /^An? .+? story written in an? .+? style, wherein /;

/** The premise alone, capitalised: the chip text. Older relays send only `value`. */
function sparkText(a: Archetype): string {
  if (a.spark) return a.spark;
  const premise = a.value.replace(LEAD, '').replace(/\.$/, '');
  return premise.charAt(0).toUpperCase() + premise.slice(1);
}

export function IdeaStep({ draft, set, chars, userName }: {
  draft: Draft;
  set: (next: Draft) => void;
  chars: CharacterRow[];
  userName: string;
}) {
  const [sparks, setSparks] = useState<Archetype[]>([]);
  const [pendingSpark, setPendingSpark] = useState<string | null>(null);
  const [picking, setPicking] = useState(false);
  const [pickingWorld, setPickingWorld] = useState(false);
  const chat = draft.chatSource;
  const world = draft.world;
  // The latest draft, for the two relay answers that land after a tap.
  const latest = useRef(draft);
  latest.current = draft;

  // A reopened story knows only its place id: ask the relay for the card's line.
  const needsDetail = !!world && !world.detail ? world.placeId : '';
  useEffect(() => {
    if (!needsDetail) return;
    let live = true;
    loadWorldSummary({ place: needsDetail })
      .then((s) => {
        const w = latest.current.world;
        if (!live || !w || w.placeId !== needsDetail) return;
        set({ ...latest.current, world: s.ok ? { ...pickFromSummary(s, w.fromChat) } : { ...w, detail: WORLD_GONE } });
      })
      .catch(() => { /* the name alone is shown */ });
    return () => { live = false; };
  }, [needsDetail, set]);

  const pickWorld = async (placeId: string) => {
    setPickingWorld(false);
    try {
      const s = await loadWorldSummary({ place: placeId });
      if (s.ok) set({ ...latest.current, world: pickFromSummary(s) });
    } catch { /* nothing picked */ }
  };

  /** A chat with a Setting puts the story there, unless a world was already picked by hand. */
  const adoptChatWorld = async (source: ChatSource) => {
    const current = latest.current.world;
    if (current && !current.fromChat) return;
    try {
      const s = await loadWorldSummary({ session: source.sessionId });
      if (s.ok && latest.current.chatSource?.sessionId === source.sessionId) {
        set({ ...latest.current, world: pickFromSummary(s, true) });
      }
    } catch { /* the chat alone */ }
  };

  const rollSparks = useCallback(() => {
    api.get<{ archetypes: Archetype[] }>(`/api/stories/archetypes?count=${SPARK_COUNT}`)
      .then((r) => setSparks(r.archetypes))
      .catch(() => setSparks([]));
  }, []);
  useEffect(rollSparks, [rollSparks]);

  const applySpark = (concept: string) => {
    if (draft.concept.trim()) setPendingSpark(concept);
    else set({ ...draft, concept });
  };
  const choose = (source: ChatSource) => {
    setPicking(false);
    set(adoptChat(draft, source, userName));
    void adoptChatWorld(source);
  };
  const portrait = chat ? chars.find((c) => c.id === chat.characterId) : undefined;

  return (
    <>
      <div className="s-card">
        <Field label="Title">
          <input type="text" data-testid="story-title" value={draft.title}
            placeholder="Leave blank and the bible will suggest one"
            onChange={(e) => set({ ...draft, title: e.target.value })} />
        </Field>
        <Field label="What is the story?">
          <textarea className="s-textarea" rows={4} data-testid="story-concept" value={draft.concept}
            placeholder="A courier on a drowned coast owes a smuggler forty silver by the spring caravan…"
            onChange={(e) => set({ ...draft, concept: e.target.value })} />
        </Field>
        <div className="s-row nowrap">
          <span className="s-grow"><KeyLabel>Need a spark?</KeyLabel></span>
          <button type="button" className="s-btn-ghost" data-testid="story-new-ideas" onClick={rollSparks}>↻ New ideas</button>
        </div>
        <div className="s-chips">
          {sparks.map((a, i) => (
            <button key={`${i}-${a.value}`} type="button" className="s-chip pick" onClick={() => applySpark(a.value)}>{sparkText(a)}</button>
          ))}
        </div>
        <Note>Tapping a spark fills an empty box. If you've written something, it asks before replacing it.</Note>
      </div>

      <div className="s-card">
        <div className="s-row nowrap">
          <span className="s-grow"><KeyLabel>Or start from a chat</KeyLabel></span>
          {chat
            ? <button type="button" className="s-btn-ghost" onClick={() => set(dropChat(draft))}>Remove</button>
            : <button type="button" className="s-btn-quiet" data-testid="story-choose-chat" onClick={() => setPicking(true)}>Choose a chat…</button>}
        </div>
        {chat ? (
          <>
            <div className="s-row">
              <Avatar name={chat.characterName} src={portrait ? characterAvatar(portrait) : undefined} />
              <div className="s-grow">
                <b style={{ display: 'block' }} data-testid="story-chat-name">{chat.characterName}</b>
                <span className="s-muted s-small" data-testid="story-chat-detail">
                  {[isGroupSource(chat) ? sourceCastLine(chat) : '', chat.messageCount > 0 ? `${chat.messageCount} messages` : 'this chat'].filter(Boolean).join(' · ')}
                </span>
              </div>
              <Segmented testid="story-faithful"
                options={{ faithful: 'Faithful retelling', inspired: 'Inspired by' }}
                selected={chat.faithful ? 'faithful' : 'inspired'}
                onSelect={(v) => set({ ...draft, chatSource: { ...chat, faithful: v === 'faithful' } })} />
            </div>
            <Note>
              Faithful keeps what happened in the chat as canon for every stage. Inspired by uses it as a starting
              point only. {isGroupSource(chat)
                ? `${sourceCastLine(chat)} all join the cast on the next step; the timeline names who did what.`
                : `${chat.characterName} joins the cast on the next step.`}
            </Note>
          </>
        ) : (
          <Note>
            The chat becomes canon: its events are distilled into a timeline the bible must respect, and its
            characters join the cast. A group chat brings its whole roster.
          </Note>
        )}
      </div>

      <div className="s-card" data-testid="story-world-card">
        <div className="s-row nowrap">
          <span className="s-grow"><KeyLabel>Where does it happen?</KeyLabel></span>
          {world
            ? <button type="button" className="s-btn-ghost" data-testid="story-remove-world" onClick={() => set({ ...draft, world: null })}>Remove</button>
            : <button type="button" className="s-btn-quiet" data-testid="story-choose-world" onClick={() => setPickingWorld(true)}>Choose a world…</button>}
        </div>
        {world && (
          <div className="s-row nowrap">
            <div className="s-grow">
              <b style={{ display: 'block' }} data-testid="story-world-name">{world.worldName || 'A world'}</b>
              {world.detail && <span className="s-muted s-small" data-testid="story-world-detail">{world.detail}</span>}
            </div>
            {world.fromChat && <Chip tone="amber">from the chat</Chip>}
            <button type="button" className="s-btn-quiet" data-testid="story-change-world" onClick={() => setPickingWorld(true)}>Change…</button>
          </div>
        )}
        <Note>The world's places and lore ground every stage. The story reads the world; it never changes it.</Note>
      </div>

      {picking && <ChatSourcePicker onPick={choose} onClose={() => setPicking(false)} />}
      {pickingWorld && <WorldPicker onPick={(placeId) => { void pickWorld(placeId); }} onClose={() => setPickingWorld(false)} />}
      {pendingSpark !== null && (
        <ConfirmDialog title="Replace your idea?" body="The spark replaces what you've written in the box."
          confirmLabel="Replace"
          onCancel={() => setPendingSpark(null)}
          onConfirm={() => { set({ ...draft, concept: pendingSpark }); setPendingSpark(null); }} />
      )}
    </>
  );
}
