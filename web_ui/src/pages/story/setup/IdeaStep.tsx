// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Step 1 of 4: title, the idea, sparks, and "start from a chat". Web twin of
// lib/ui/story_setup/idea_step.dart.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../../api/client';
import { adoptChat, dropChat, type CharacterRow, type ChatSource, type Draft } from './draft';
import { ChatSourcePicker } from './ChatSourcePicker';
import { Avatar, ConfirmDialog, Field, KeyLabel, Note, Segmented } from './primitives';
import { characterAvatar } from './useSetupData';

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
  const chat = draft.chatSource;

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
                <b style={{ display: 'block' }}>{chat.characterName}</b>
                <span className="s-muted s-small">{chat.messageCount > 0 ? `${chat.messageCount} messages` : 'this chat'}</span>
              </div>
              <Segmented testid="story-faithful"
                options={{ faithful: 'Faithful retelling', inspired: 'Inspired by' }}
                selected={chat.faithful ? 'faithful' : 'inspired'}
                onSelect={(v) => set({ ...draft, chatSource: { ...chat, faithful: v === 'faithful' } })} />
            </div>
            <Note>
              Faithful keeps what happened in the chat as canon for every stage. Inspired by uses it as a starting
              point only. {chat.characterName} joins the cast on the next step.
            </Note>
          </>
        ) : (
          <Note>
            The chat becomes canon: its events are distilled into a timeline the bible must respect, and its
            character joins the cast.
          </Note>
        )}
      </div>

      {picking && <ChatSourcePicker onPick={choose} onClose={() => setPicking(false)} />}
      {pendingSpark !== null && (
        <ConfirmDialog title="Replace your idea?" body="The spark replaces what you've written in the box."
          confirmLabel="Replace"
          onCancel={() => setPendingSpark(null)}
          onConfirm={() => { set({ ...draft, concept: pendingSpark }); setPendingSpark(null); }} />
      )}
    </>
  );
}
