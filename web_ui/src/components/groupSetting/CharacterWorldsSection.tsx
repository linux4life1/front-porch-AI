// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The character editor's "Where new chats meet" — the web twin of the
// desktop EditCharacterWorldsTab. Controlled: the editor posts the choice
// with the rest of the card on Save.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { TreeWorld } from '../../pages/worlds/locations';
import { GroupSettingPicker } from './GroupSettingPicker';
import { settingSummary, weatherLabels, type WorldChoice } from './groupWorldChoice';

export function CharacterWorldsSection({
  name,
  value,
  onChange,
  worlds,
  legacyWorldCount = 0,
}: {
  name: string;
  value: WorldChoice;
  onChange: (next: WorldChoice) => void;
  /** Every world and place (/api/worlds). */
  worlds: TreeWorld[];
  /** How many worlds an unsplit card links; above one, the banner shows. */
  legacyWorldCount?: number;
}) {
  const [climates, setClimates] = useState<{ id: string; displayName: string }[]>([]);
  useEffect(() => {
    api
      .get<{ climates?: { id: string; displayName: string }[] }>('/api/worlds/climates')
      .then((c) => setClimates(Array.isArray(c?.climates) ? c.climates : []))
      .catch((e) => console.warn('[character] climates unavailable', e));
  }, []);
  const owner = name.trim() || 'this character';
  const weatherOf = weatherLabels(worlds, climates);
  return (
    <div className="gs-section" data-testid="character-worlds-section">
      <h3 className="section-label">
        Where new chats meet <span className="gs-chip">New chats</span>
      </h3>
      <p className="muted small">
        Applies to {owner}&apos;s new chats. Chats you&apos;ve already started keep their worlds.
      </p>
      {legacyWorldCount > 1 && (
        <div className="gs-banner" role="status" data-testid="character-worlds-split-banner">
          <strong>Worlds now have two roles.</strong>
          {owner} linked {legacyWorldCount} worlds before one world set the scene and the others
          added lore. Nothing about its chats has changed, and it&apos;s filled in below as it
          works today. {settingSummary(value, worlds, weatherOf)}
        </div>
      )}
      <GroupSettingPicker
        value={value}
        onChange={onChange}
        worlds={worlds}
        weatherOf={weatherOf}
        owner={owner}
      />
    </div>
  );
}
