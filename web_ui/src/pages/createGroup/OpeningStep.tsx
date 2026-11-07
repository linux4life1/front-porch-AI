// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Opening: the first message and scenario, with Generate written
// by the desktop's own generator through the relay, set where the Setting
// step put the group. Web twin of GroupOpeningStep.

import { useState } from 'react';
import { api, ApiError } from '../../api/client';
import { AltGreetingsEditor } from '../../components/AltGreetingsEditor';
import { compactGreetingPairs } from '../../components/realism/realismTypes';
import type { WorldChoice } from '../../components/groupSetting/groupWorldChoice';
import { liveRelationships, type GroupDraft } from './groupDraft';

export function OpeningStep({
  draft,
  set,
  memberIds,
  worlds,
  whereLine,
  clockOn,
}: {
  draft: GroupDraft;
  set: (patch: Partial<GroupDraft>) => void;
  memberIds: string[];
  worlds: WorldChoice;
  /** The Setting summary sentence. */
  whereLine: string;
  clockOn: boolean;
}) {
  const [busy, setBusy] = useState<'scenario' | 'first' | null>(null);
  const [error, setError] = useState('');
  const relationships = liveRelationships(draft, memberIds);
  const withDynamics = Object.keys(relationships).length > 0;
  const label = withDynamics ? 'Generate with Dynamics' : 'Generate';

  const generate = async (which: 'scenario' | 'first') => {
    setBusy(which);
    setError('');
    try {
      const r = await api.post<{ text: string }>(
        which === 'scenario' ? '/api/groups/draft/scenario' : '/api/groups/draft/first-message',
        {
          memberIds,
          worlds,
          relationships,
          directorMode: draft.directorMode,
          scenario: draft.scenario,
        },
      );
      if (r.text.trim()) set(which === 'scenario' ? { scenario: r.text } : { firstMessage: r.text });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Generation failed. Try again.');
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="cg-config">
      <h3 className="gs-title-lg">Opening Scene</h3>
      <p className="muted small" data-testid="group-opening-setting">
        {whereLine} {worlds.settingId ? 'Generate writes the scene there.' : 'Generate makes up a place.'}
      </p>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <div className="cg-field">
        <div className="gw-row">
          <span className="cg-field-label">First message (optional)</span>
          <button className="small" disabled={busy !== null} onClick={() => void generate('first')}>
            {busy === 'first' ? 'Generating…' : `✨ ${label}`}
          </button>
        </div>
        <textarea
          rows={7}
          value={draft.firstMessage}
          placeholder="The scene opens with..."
          onChange={(e) => set({ firstMessage: e.target.value })}
        />
        {draft.directorMode && (
          <p className="muted small">Director Mode: generated opening will be a self-contained group scene.</p>
        )}
      </div>
      <AltGreetingsEditor
        greetings={draft.alternateGreetings}
        seeds={draft.greetingSeeds}
        showNeeds
        clockOn={clockOn}
        onChange={(g) => {
          const paired = compactGreetingPairs(g, draft.greetingSeeds);
          set({ alternateGreetings: paired.greetings, greetingSeeds: paired.seeds });
        }}
        onSeedsChange={(s) => {
          const paired = compactGreetingPairs(draft.alternateGreetings, s);
          set({ alternateGreetings: paired.greetings, greetingSeeds: paired.seeds });
        }}
      />
      <div className="cg-field">
        <div className="gw-row">
          <span className="cg-field-label">Scenario (optional)</span>
          <button className="small" disabled={busy !== null} onClick={() => void generate('scenario')}>
            {busy === 'scenario' ? 'Generating…' : `✨ ${label}`}
          </button>
        </div>
        <textarea
          rows={3}
          value={draft.scenario}
          placeholder="Where the characters are and what is happening"
          onChange={(e) => set({ scenario: e.target.value })}
        />
      </div>
    </div>
  );
}
