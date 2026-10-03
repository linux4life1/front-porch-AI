// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Step 3 of 4: length, format, voice, genre, mood, style, pace, dialogue,
// maturity. Web twin of lib/ui/story_setup/shape_step.dart.

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import {
  DIALOGUE_LABELS, GENRES, MATURITY_LABELS, MOODS, PACE_LABELS, POV_LABELS, TARGET_LENGTHS, WRITING_STYLES,
} from '../../../storyTypes';
import { targetWordsFor, type Draft } from './draft';
import { ChipRow, Field, Note, Segmented } from './primitives';

const LENGTHS = Object.fromEntries(TARGET_LENGTHS.map((t) => [t.key, t.label]));
const asOptions = (items: string[]) => Object.fromEntries(items.map((i) => [i, i]));
const GENRE_OPTIONS = asOptions(GENRES);
const MOOD_OPTIONS = asOptions(MOODS);
const STYLE_OPTIONS = asOptions(WRITING_STYLES);

const toggle = (list: string[], value: string, on: boolean) =>
  on ? (list.includes(value) ? list : [...list, value]) : list.filter((v) => v !== value);

export function ShapeStep({ draft, set }: { draft: Draft; set: (next: Draft) => void }) {
  const words = targetWordsFor(draft.proseLength);
  const [summary, setSummary] = useState('');
  useEffect(() => {
    let live = true;
    api.get<{ summary: string }>(`/api/stories/pacing?words=${words}`)
      .then((r) => { if (live) setSummary(r.summary); })
      .catch(() => { if (live) setSummary(''); });
    return () => { live = false; };
  }, [words]);

  return (
    <>
      <div className="s-grid2" style={{ alignItems: 'start' }}>
        <div className="s-card">
          <Field label="Length">
            <Segmented testid="story-length" options={LENGTHS} selected={draft.proseLength}
              onSelect={(v) => set({ ...draft, proseLength: v })} />
          </Field>
          {summary && <Note>{summary}</Note>}
        </div>
        <div className="s-card">
          <Field label="Format">
            <Segmented testid="story-format" options={{ novel: 'Novel', audioDrama: 'Audio drama' }}
              selected={draft.storyFormat}
              onSelect={(v) => set({ ...draft, storyFormat: v === 'audioDrama' ? 'audioDrama' : 'novel' })} />
          </Field>
          <Note>Audio drama writes a voiced script for your cast voices.</Note>
        </div>
      </div>

      <div className="s-card">
        <Field label="Told from">
          <ChipRow testid="story-pov" options={POV_LABELS} selected={[draft.pov]}
            onToggle={(v) => set({ ...draft, pov: v })} />
        </Field>
        <Field label="Genre" hint="(pick any)">
          <ChipRow testid="story-genres" options={GENRE_OPTIONS} selected={draft.genres}
            onToggle={(v, on) => set({ ...draft, genres: toggle(draft.genres, v, on) })} />
        </Field>
        <Field label="Mood" hint="(pick any)">
          <ChipRow testid="story-moods" options={MOOD_OPTIONS} selected={draft.moods}
            onToggle={(v, on) => set({ ...draft, moods: toggle(draft.moods, v, on) })} />
        </Field>
        <Field label="Writing style">
          <ChipRow testid="story-style" options={STYLE_OPTIONS} selected={[draft.writingStyle]}
            onToggle={(v, on) => set({ ...draft, writingStyle: on ? v : '' })} />
        </Field>
      </div>

      <div className="s-grid3" style={{ alignItems: 'start' }}>
        <div className="s-card">
          <Field label="Pace">
            <Segmented testid="story-pace" options={PACE_LABELS} selected={draft.pace}
              onSelect={(v) => set({ ...draft, pace: v })} />
          </Field>
        </div>
        <div className="s-card">
          <Field label="Dialogue">
            <Segmented testid="story-dialogue" options={DIALOGUE_LABELS} selected={draft.dialogue}
              onSelect={(v) => set({ ...draft, dialogue: v })} />
          </Field>
        </div>
        <div className="s-card">
          <Field label="Maturity">
            <Segmented testid="story-maturity" options={MATURITY_LABELS} selected={draft.maturity}
              onSelect={(v) => set({ ...draft, maturity: v })} />
          </Field>
        </div>
      </div>
    </>
  );
}
