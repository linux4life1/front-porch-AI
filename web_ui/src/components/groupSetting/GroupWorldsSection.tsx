// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings' "Where new chats meet" — the web twin of the desktop
// GroupWorldsSection. It only sets up the group's NEW chats; the open chat's
// places stay in the Places panel, and this says where that chat is.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { TreeWorld } from '../../pages/worlds/locations';
import { GroupSettingPicker } from './GroupSettingPicker';
import { NO_WORLD, settingSummary, weatherLabels, type WorldChoice } from './groupWorldChoice';

interface GroupWorlds {
  settingId: string | null;
  loreIds: string[];
  legacyWorldCount?: number;
}

interface ChatPlaces {
  primary?: { name: string; parentName?: string | null } | null;
}

export function GroupWorldsSection({ groupId }: { groupId: string }) {
  const [saveError, setSaveError] = useState('');
  const [choice, setChoice] = useState<WorldChoice>(NO_WORLD);
  const [legacyCount, setLegacyCount] = useState(0);
  const [worlds, setWorlds] = useState<TreeWorld[]>([]);
  const [climates, setClimates] = useState<{ id: string; displayName: string }[]>([]);
  const [here, setHere] = useState<ChatPlaces['primary']>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let live = true;
    // Started inside a promise so any failure, even a synchronous one, lands
    // in the catch below and the rest of Group Settings keeps working.
    Promise.resolve()
      .then(() =>
        Promise.all([
          api.get<GroupWorlds>(`/api/groups/${groupId}/worlds`),
          api.get<{ worlds?: TreeWorld[] }>('/api/worlds'),
          api.get<{ climates?: { id: string; displayName: string }[] }>('/api/worlds/climates'),
          api.get<ChatPlaces>('/api/chat/places').catch(() => ({}) as ChatPlaces),
        ]),
      )
      .then(([g, w, c, p]) => {
        if (!live) return;
        setChoice({ settingId: g.settingId ?? null, loreIds: g.loreIds ?? [] });
        setLegacyCount(g.legacyWorldCount ?? 0);
        setWorlds(Array.isArray(w?.worlds) ? w.worlds : []);
        setClimates(Array.isArray(c?.climates) ? c.climates : []);
        setHere(p?.primary ?? null);
        setLoaded(true);
      })
      .catch((e) => console.warn('[group] worlds unavailable', e));
    return () => {
      live = false;
    };
  }, [groupId]);

  const change = (next: WorldChoice) => {
    setChoice(next);
    void api
      .post(`/api/groups/${groupId}/settings`, { worlds: next })
      .then(() => setSaveError(''))
      .catch((e) => {
        console.warn('[group] worlds save failed', e);
        setSaveError('Could not save where new chats meet. Pick again to retry.');
      });
  };

  if (!loaded) return null;
  const weatherOf = weatherLabels(worlds, climates);
  return (
    <div className="gs-section" data-testid="group-worlds-section">
      <h4 className="section-label">
        Where new chats meet <span className="gs-chip">New chats</span>
      </h4>
      <p className="muted small">
        Applies to new chats of this group. Chats you've already started keep their worlds.{' '}
        {here
          ? `This chat is at ${here.parentName ? `${here.name} in ${here.parentName}` : here.name}. To move it, use Places.`
          : 'This chat has no world. Add one from Places.'}
      </p>
      {saveError && (
        <p className="error" role="alert">
          {saveError}
        </p>
      )}
      {legacyCount > 1 && (
        <div className="gs-banner" role="status" data-testid="group-worlds-split-banner">
          <strong>Worlds now have two roles.</strong>
          This group linked {legacyCount} worlds before one world set the scene and the others
          added lore. Nothing about its chats has changed, and it's filled in below as it works
          today. {settingSummary(choice, worlds, weatherOf)}
        </div>
      )}
      <GroupSettingPicker value={choice} onChange={change} worlds={worlds} weatherOf={weatherOf} />
    </div>
  );
}
