// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group-chat creation — the web mirror of the desktop create_group_chat_page
// flow: a stepped wizard (Members → Details) where you pick ≥2 library
// characters, name the group, choose a turn order, then Create & open. Posts to
// POST /api/groups (which duplicates each character into private group members,
// matching the desktop persist) and opens the new group chat.

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import {
  FolderCharacterPicker,
  type PickerChar,
  type PickerFolder,
} from '../components/FolderCharacterPicker';
import { defaultGroupName } from '../groupName';

const STEPS = ['Members', 'Details'];

export function CreateGroupChatPage() {
  const navigate = useNavigate();
  const [chars, setChars] = useState<PickerChar[]>([]);
  const [folders, setFolders] = useState<PickerFolder[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [step, setStep] = useState(0);
  // null until the user types: the name then follows the roster.
  const [typedName, setTypedName] = useState<string | null>(null);
  const [turnOrder, setTurnOrder] = useState<'roundRobin' | 'random'>('roundRobin');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get<PickerChar[]>('/api/characters?scope=allCharacters').then(setChars).catch(() => {});
    api.get<{ folders: PickerFolder[] }>('/api/folders').then((r) => setFolders(r.folders)).catch(() => {});
  }, []);

  const toggle = (id: string) =>
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));

  const selectedChars = chars.filter((c) => selected.includes(c.id));
  // Named after every member, in the order they were picked, until the user
  // types a name of their own.
  const name =
    typedName ??
    defaultGroupName(selected.map((id) => chars.find((c) => c.id === id)?.name ?? ''));
  const canAdvance = step !== 0 || selected.length >= 2;
  const canCreate = selected.length >= 2 && name.trim().length > 0;

  const create = async () => {
    if (!canCreate || busy) return;
    setBusy(true);
    setError('');
    try {
      const r = await api.post<{ id: string; name: string }>('/api/groups', {
        name: name.trim(),
        memberIds: selected,
        turnOrder,
      });
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
      <header className="page-head">
        <button className="ghost" onClick={() => navigate('/')}>← Library</button>
        <h2>👥 New Group</h2>
      </header>

      <StepIndicator steps={STEPS} current={step} onJump={busy ? undefined : setStep} />

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
              <input value={name} onChange={(e) => setTypedName(e.target.value)} placeholder="Name this group" />
            </label>
            <label className="cg-field">
              <span className="cg-field-label">Turn order</span>
              <select value={turnOrder} onChange={(e) => setTurnOrder(e.target.value as 'roundRobin' | 'random')}>
                <option value="roundRobin">Round-robin (in order)</option>
                <option value="random">Random</option>
              </select>
            </label>
            <div className="cg-field">
              <span className="cg-field-label">Members ({selectedChars.length})</span>
              <div className="cg-chips">
                {selectedChars.map((c) => <span key={c.id} className="cg-chip on">{c.name}</span>)}
              </div>
            </div>
            <button className="primary cg-generate" disabled={!canCreate || busy} onClick={create}>
              {busy ? 'Creating…' : '👥 Create & open'}
            </button>
            {error && <p className="error">{error}</p>}
          </div>
        )}
      </div>

      <div className="wizard-nav">
        <button disabled={step === 0 || busy} onClick={() => setStep(step - 1)}>← Back</button>
        {step < STEPS.length - 1 && (
          <button className="primary" disabled={!canAdvance} onClick={() => setStep(step + 1)}>Next →</button>
        )}
      </div>
    </div>
  );
}
