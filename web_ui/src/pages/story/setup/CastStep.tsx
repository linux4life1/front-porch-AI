// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Step 2 of 4: characters from the library with a role chip row each, "You in
// the story", and whether the chat is canon. Web twin of
// lib/ui/story_setup/cast_step.dart.

import { useState } from 'react';
import { ROLE_OPTIONS } from '../../../storyTypes';
import { dropChat, type CharacterRow, type Draft } from './draft';
import { Avatar, ChipRow, Dialog, KeyLabel, Note, ToggleRow } from './primitives';
import { characterAvatar } from './useSetupData';

const ROLES = Object.fromEntries(ROLE_OPTIONS.map((r) => [r, r]));

export function CastStep({ draft, set, chars, personaName }: {
  draft: Draft;
  set: (next: Draft) => void;
  chars: CharacterRow[];
  personaName: string;
}) {
  const [adding, setAdding] = useState(false);
  const chat = draft.chatSource;
  const picked = draft.castIds.flatMap((id) => chars.find((c) => c.id === id) ?? []);
  const available = chars.filter((c) => !draft.castIds.includes(c.id));

  const setRole = (id: string, role: string) => set({ ...draft, roles: { ...draft.roles, [id]: role } });
  const remove = (id: string) => {
    if (chat?.characterId === id) {
      set(dropChat(draft));
      return;
    }
    const roles = { ...draft.roles };
    delete roles[id];
    set({ ...draft, castIds: draft.castIds.filter((x) => x !== id), roles });
  };
  const add = (c: CharacterRow) => {
    const hasProtagonist = Object.values(draft.roles).includes('Protagonist');
    set({
      ...draft,
      castIds: [...draft.castIds, c.id],
      roles: { ...draft.roles, [c.id]: hasProtagonist ? 'Supporting' : 'Protagonist' },
    });
    setAdding(false);
  };

  return (
    <>
      <div className="s-card">
        <div className="s-row nowrap">
          <span className="s-grow"><KeyLabel>From your characters</KeyLabel></span>
          <button type="button" className="s-btn-quiet" data-testid="story-add-cast" onClick={() => setAdding(true)}>+ Add from library</button>
        </div>
        {picked.length === 0 && <Note>No one yet. Anyone you don't add here, the bible writes for you.</Note>}
        {picked.map((c) => (
          <div key={c.id} className="s-row nowrap" style={{ alignItems: 'flex-start' }} data-testid={`story-cast-${c.id}`}>
            <Avatar name={c.name} src={characterAvatar(c)} />
            <div className="s-col s-grow" style={{ gap: 2 }}>
              <b>{c.name}</b>
              <Note>{chat?.characterId === c.id ? 'From the chat · the card and the chat are canon' : 'Library card'}</Note>
              <div style={{ marginTop: 4 }}>
                <ChipRow options={ROLES} selected={[draft.roles[c.id] ?? 'Supporting']} onToggle={(role) => setRole(c.id, role)} />
              </div>
            </div>
            <button type="button" className="s-btn-ico ghost" aria-label="Remove" title="Remove" onClick={() => remove(c.id)}>✕</button>
          </div>
        ))}
      </div>

      <div className="s-card">
        <ToggleRow testid="story-persona" on={draft.includePersona} label="You in the story"
          detail={`as your persona, ${personaName}`}
          onChange={(on) => set({ ...draft, includePersona: on })} />
        {draft.includePersona && (
          <ChipRow options={ROLES} selected={[draft.personaRole]} onToggle={(role) => set({ ...draft, personaRole: role })} />
        )}
      </div>

      {chat && (
        <div className="s-card">
          <ToggleRow on={draft.useChatHistory} label="Use the chat as canon"
            detail={`The chat with ${chat.characterName} is distilled into a timeline the bible must respect`}
            onChange={(on) => set({ ...draft, useChatHistory: on })} />
        </div>
      )}

      <Note>You can add or remove cast later from the Cast screen.</Note>

      {adding && (
        <Dialog title="Add from library" wide onClose={() => setAdding(false)}
          actions={<button type="button" className="s-btn-ghost" onClick={() => setAdding(false)}>Cancel</button>}>
          {available.length === 0
            ? <div className="body">Every character is already in the cast.</div>
            : (
              <div className="s-col" style={{ gap: 2 }}>
                {available.map((c) => (
                  <button key={c.id} type="button" className="s-listrow" data-testid={`story-library-${c.id}`} onClick={() => add(c)}>
                    <Avatar name={c.name} src={characterAvatar(c)} />
                    <b className="s-grow s-ell">{c.name}</b>
                  </button>
                ))}
              </div>
            )}
        </Dialog>
      )}
    </>
  );
}
