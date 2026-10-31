// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group-chat creation — the web mirror of the desktop create_group_chat_page
// wizard, in its seven steps: Members, Details, Setting, Realism (with
// Group Dynamics), Opening, Prompts & Lore, Review. Posts the whole draft to
// POST /api/groups (which duplicates each character into private group
// members, as the desktop persist does) and opens the new group chat.

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import {
  FolderCharacterPicker,
  type PickerChar,
  type PickerFolder,
} from '../components/FolderCharacterPicker';
import { GroupSettingPicker } from '../components/groupSetting/GroupSettingPicker';
import {
  NO_WORLD,
  linkedByMembers,
  settingSummary,
  weatherLabels,
  type WorldChoice,
} from '../components/groupSetting/groupWorldChoice';
import { defaultGroupName } from '../groupName';
import type { TreeWorld } from './worlds/locations';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';
import { EMPTY_DRAFT, GROUP_STEPS, createBody, draftTouched, type GroupDraft } from './createGroup/groupDraft';
import { MemberVoicePicks } from './createGroup/MemberVoicePicks';
import { OpeningStep } from './createGroup/OpeningStep';
import { RealismStep } from './createGroup/RealismStep';
import { useMemberCardSeeds } from './createGroup/useMemberCardSeeds';
import { PromptsLoreStep } from './createGroup/PromptsLoreStep';
import { ReviewStep } from './createGroup/ReviewStep';

const REVIEW = GROUP_STEPS.length - 1;

export function CreateGroupChatPage() {
  const navigate = useNavigate();
  const [chars, setChars] = useState<(PickerChar & { worldNames?: string[] })[]>([]);
  const [worlds, setWorlds] = useState<TreeWorld[]>([]);
  const [climates, setClimates] = useState<{ id: string; displayName: string }[]>([]);
  const [clockOn, setClockOn] = useState(true);
  const [worldChoice, setWorldChoice] = useState<WorldChoice>(NO_WORLD);
  const [draft, setDraft] = useState<GroupDraft>(EMPTY_DRAFT);
  const [folders, setFolders] = useState<PickerFolder[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const cards = useMemberCardSeeds(selected);
  const [step, setStep] = useState(0);
  // null until the user types: the name then follows the roster.
  const [typedName, setTypedName] = useState<string | null>(null);
  const [turnOrder, setTurnOrder] = useState<'roundRobin' | 'random'>('roundRobin');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const { prompt, leaveWithoutAsking } = useUnsavedChanges(
    selected.length > 0 ||
      typedName !== null ||
      turnOrder !== 'roundRobin' ||
      worldChoice.settingId !== null ||
      worldChoice.loreIds.length > 0 ||
      draftTouched(draft),
  );

  useEffect(() => {
    api.get<PickerChar[]>('/api/characters?scope=allCharacters').then(setChars).catch(() => {});
    api.get<{ folders: PickerFolder[] }>('/api/folders').then((r) => setFolders(r.folders)).catch(() => {});
    api
      .get<{ worlds?: TreeWorld[] }>('/api/worlds')
      .then((r) => setWorlds(Array.isArray(r?.worlds) ? r.worlds : []))
      .catch((e) => console.warn('[create-group] worlds unavailable', e));
    api
      .get<{ climates?: { id: string; displayName: string }[] }>('/api/worlds/climates')
      .then((r) => setClimates(Array.isArray(r?.climates) ? r.climates : []))
      .catch((e) => console.warn('[create-group] climates unavailable', e));
    api
      .get<{ realism?: { passageOfTimeDefault?: boolean } }>('/api/settings')
      .then((r) => setClockOn(r?.realism?.passageOfTimeDefault !== false))
      .catch((e) => console.warn('[create-group] settings unavailable', e));
  }, []);

  const toggle = (id: string) =>
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  const set = (patch: Partial<GroupDraft>) => setDraft((d) => ({ ...d, ...patch }));

  const selectedChars = chars.filter((c) => selected.includes(c.id));
  const members = selected.map((id) => ({ id, name: chars.find((c) => c.id === id)?.name ?? '' }));
  // Named after every member, in the order they were picked, until the user
  // types a name of their own.
  const name = typedName ?? defaultGroupName(members.map((m) => m.name));
  const canAdvance = step !== 0 || selected.length >= 2;
  const canCreate = selected.length >= 2 && name.trim().length > 0;
  const weatherOf = weatherLabels(worlds, climates);
  const whereLine = settingSummary(worldChoice, worlds, weatherOf);

  const create = async (open: boolean) => {
    if (!canCreate || busy) return;
    setBusy(true);
    setError('');
    try {
      const r = await api.post<{ id: string; name: string }>(
        '/api/groups',
        createBody({ name: name.trim(), memberIds: selected, turnOrder, worlds: worldChoice, draft }),
      );
      leaveWithoutAsking();
      if (!open) {
        navigate('/');
        return;
      }
      navigate('/chat?opening=1');
      await api.post('/api/chat/select-group', { groupId: r.id });
      navigate('/chat', { replace: true });
    } catch (e) {
      setBusy(false);
      setError(e instanceof ApiError ? e.message : 'Could not create the group');
    }
  };

  return (
    <div className="page wizard">
      {prompt}
      <header className="page-head">
        <button className="ghost" onClick={() => navigate('/')}>← Library</button>
        <h2>👥 New Group</h2>
      </header>

      <StepIndicator steps={[...GROUP_STEPS]} current={step} onJump={busy ? undefined : setStep} />

      <div className="wizard-body">
        {step === 0 && (
          <div className="cg-config">
            <p className="muted small">Pick at least 2 characters — {selected.length} selected.</p>
            <FolderCharacterPicker
              chars={chars}
              folders={folders}
              selected={selected}
              onToggle={toggle}
            />
          </div>
        )}

        {step === 1 && (
          <div className="cg-config">
            <label className="cg-field">
              <span className="cg-field-label">Group name</span>
              <input
                value={name}
                // Clearing the box hands the name back to the roster.
                onChange={(e) => setTypedName(e.target.value.trim() === '' ? null : e.target.value)}
                placeholder="Name this group"
              />
            </label>
            <label className="cg-field">
              <span className="cg-field-label">Turn order</span>
              <select value={turnOrder} onChange={(e) => setTurnOrder(e.target.value as 'roundRobin' | 'random')}>
                <option value="roundRobin">Round-robin (in order)</option>
                <option value="random">Random</option>
              </select>
            </label>
            <label className="tool-toggle">
              <span>Auto-Advance (characters take turns without waiting for you)</span>
              <input
                type="checkbox"
                checked={draft.autoAdvance}
                onChange={(e) => set({ autoAdvance: e.target.checked })}
              />
            </label>
            <label className="tool-toggle">
              <span>Director Mode (you direct; the cast talks among themselves)</span>
              <input
                type="checkbox"
                checked={draft.directorMode}
                onChange={(e) => set({ directorMode: e.target.checked })}
              />
            </label>
            <div className="cg-field">
              <span className="cg-field-label">Members ({selectedChars.length})</span>
              <div className="cg-chips">
                {selectedChars.map((c) => <span key={c.id} className="cg-chip on">{c.name}</span>)}
              </div>
            </div>
            <MemberVoicePicks
              members={members}
              voices={draft.memberVoices}
              set={(memberVoices) => set({ memberVoices })}
            />
          </div>
        )}

        {step === 2 && (
          <div className="cg-config">
            <h3 className="gs-title-lg">Where does the group meet?</h3>
            <p className="muted small">
              One world sets the weather and the lore. New chats start at the place you pick inside it.
            </p>
            <GroupSettingPicker
              value={worldChoice}
              onChange={setWorldChoice}
              worlds={worlds}
              weatherOf={weatherOf}
              linkedBy={linkedByMembers(selectedChars, worlds)}
            />
          </div>
        )}

        {step === 4 && (
          <OpeningStep
            draft={draft}
            set={set}
            memberIds={selected}
            worlds={worldChoice}
            whereLine={whereLine}
            clockOn={clockOn}
          />
        )}

        {step === 3 && <RealismStep draft={draft} set={set} members={members} cards={cards} />}

        {step === 5 && <PromptsLoreStep draft={draft} set={set} members={members} />}

        {step === REVIEW && (
          <>
            <ReviewStep
              name={name.trim()}
              memberNames={members.map((m) => m.name)}
              whereLine={whereLine}
              draft={draft}
              goTo={setStep}
            />
            <div className="cg-config">
              <button className="primary cg-generate" disabled={!canCreate || busy} onClick={() => void create(true)}>
                {busy ? 'Creating…' : '👥 Create & open'}
              </button>
              <button disabled={!canCreate || busy} onClick={() => void create(false)}>
                Create only (don’t open the chat yet)
              </button>
              {error && <p className="error">{error}</p>}
            </div>
          </>
        )}
      </div>

      <div className="wizard-nav">
        <button disabled={step === 0 || busy} onClick={() => setStep(step - 1)}>← Back</button>
        {step < REVIEW && (
          <button className="primary" disabled={!canAdvance} onClick={() => setStep(step + 1)}>Next →</button>
        )}
      </div>
    </div>
  );
}
