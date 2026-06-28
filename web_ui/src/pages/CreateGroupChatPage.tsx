// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group-chat creation — the web mirror of the desktop create_group_chat_page
// flow: a stepped wizard (Members → Details) where you pick ≥2 library
// characters, name the group, choose a turn order, then Create & open. Posts to
// POST /api/groups (which duplicates each character into private group members,
// matching the desktop persist) and opens the new group chat.

import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';

interface LibChar {
  id: string;
  name: string;
  hasAvatar: boolean;
}

const STEPS = ['Members', 'Details'];

export function CreateGroupChatPage() {
  const navigate = useNavigate();
  const [chars, setChars] = useState<LibChar[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const [step, setStep] = useState(0);
  const [name, setName] = useState('');
  const [turnOrder, setTurnOrder] = useState<'roundRobin' | 'random'>('roundRobin');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get<LibChar[]>('/api/characters?scope=allCharacters').then(setChars).catch(() => {});
  }, []);

  const toggle = (id: string) =>
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? chars.filter((c) => c.name.toLowerCase().includes(q)) : chars;
  }, [chars, search]);

  const selectedChars = chars.filter((c) => selected.includes(c.id));
  const canAdvance = step !== 0 || selected.length >= 2;
  const canCreate = selected.length >= 2 && name.trim().length > 0;

  // Suggest a default name from the chosen members when reaching the Details step.
  useEffect(() => {
    if (step === 1 && !name.trim() && selectedChars.length) {
      const names = selectedChars.map((c) => c.name);
      setName(names.slice(0, 3).join(', ') + (names.length > 3 ? ' & more' : ''));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step]);

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
      await api.post('/api/chat/select-group', { groupId: r.id });
      navigate('/chat');
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
            <input
              className="grp-search"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search characters…"
            />
            <p className="muted small">Pick at least 2 characters — {selected.length} selected.</p>
            <div className="grp-grid">
              {filtered.map((c) => (
                <button
                  type="button"
                  key={c.id}
                  className={`grp-card${selected.includes(c.id) ? ' on' : ''}`}
                  onClick={() => toggle(c.id)}
                >
                  {c.hasAvatar ? (
                    <img src={`/api/characters/${c.id}/avatar`} alt={c.name} loading="lazy" />
                  ) : (
                    <span className="grp-initial">{c.name.charAt(0).toUpperCase()}</span>
                  )}
                  <span className="grp-name">{c.name}</span>
                  {selected.includes(c.id) && <span className="grp-check">✓</span>}
                </button>
              ))}
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="cg-config">
            <label className="cg-field">
              <span className="cg-field-label">Group name</span>
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Name this group" />
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
