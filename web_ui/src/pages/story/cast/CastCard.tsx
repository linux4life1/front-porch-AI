// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One dossier on the Cast screen (sketch R): portrait, name and what drives
// them, the ⋯ menu, their interview in their own voice, the voice and secret
// chips, and the voice they read aloud with. Web twin of CastSection._card.

import type { StoryCastMember, StoryVoice } from '../../../storyTypes';
import { Avatar, MenuButton } from '../setup/primitives';
import { Chip } from '../StudioShell';
import { firstName, interviewExcerpt, memberMeta, shortText } from './castEdits';

export interface CastCardActions {
  interview: () => void;
  paint: () => void;
  edit: () => void;
  remove: () => void;
  readInterview: () => void;
  pickVoice: () => void;
}

export function CastCard({ member: m, portrait, studio, running, painting, canPaint, voices, actions }: {
  member: StoryCastMember;
  /** The portrait's address: the story's own, else the library card's art, else nothing (initials). */
  portrait?: string;
  studio: boolean;
  running: boolean;
  painting: boolean;
  canPaint: boolean;
  voices: StoryVoice[];
  actions: CastCardActions;
}) {
  const meta = memberMeta(m);
  const interview = m.interview ?? '';
  const secret = m.details?.secret ?? '';
  const voice = voices.find((v) => v.id === m.voice_model);
  const paintingChip = <Chip tone="amber">● painting portrait</Chip>;
  // With no interview row to carry it (a Quick story), the chip rides with the voice and secret.
  const chipPainting = painting && (!!interview || !studio);
  return (
    <section className="s-card" data-testid={`cast-${m.name}`}>
      <div className="s-row top nowrap">
        <Avatar name={m.name} src={portrait} large />
        <div className="s-grow">
          <div className="s-bold">{m.name}</div>
          {meta && <div className="s-muted s-small">{meta}</div>}
          {m.description && <div className="s-body">{m.description}</div>}
        </div>
        <MenuButton label={`More for ${m.name}`} testid={`cast-menu-${m.name}`} entries={[
          { label: interview ? 'Interview again…' : 'Interview', disabled: !studio || running, onSelect: actions.interview },
          { label: 'Generate portrait', disabled: !canPaint || painting, onSelect: actions.paint },
          { label: 'Edit…', onSelect: actions.edit },
          { label: 'Remove from cast…', danger: true, divider: true, onSelect: actions.remove },
        ]} />
      </div>

      {interview ? (
        <>
          <span className="s-key">From their interview</span>
          <p className="s-prose sm">“{interviewExcerpt(interview)}”</p>
          <button type="button" className="s-btn-ghost" onClick={actions.readInterview}>Read the whole interview</button>
        </>
      ) : studio && (
        <div className="s-row">
          <button type="button" className="s-btn-quiet" data-testid={`cast-interview-${m.name}`} disabled={running}
            onClick={actions.interview}>Interview {firstName(m.name)}</button>
          {canPaint && !m.portrait && (
            <button type="button" className="s-btn-ghost" disabled={painting} onClick={actions.paint}>Generate portrait</button>
          )}
          {painting && paintingChip}
        </div>
      )}

      {(m.voice_sample || secret || chipPainting) && (
        <div className="s-chips">
          {m.voice_sample && <Chip>Voice: {shortText(m.voice_sample)}</Chip>}
          {secret && <Chip tone="honey">Secret: {shortText(secret)}</Chip>}
          {chipPainting && paintingChip}
        </div>
      )}

      {voices.length > 0 && (
        <div className="s-row">
          <span className="s-muted s-small">Reads aloud as</span>
          <button type="button" className="s-chip pick" data-testid={`cast-voice-${m.name}`} onClick={actions.pickVoice}>
            {voice ? voice.name : 'Default narrator'}
          </button>
        </div>
      )}
    </section>
  );
}
