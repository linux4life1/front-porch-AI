// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group-chat authoring wizard (create + edit). Step 1 picks ≥2 member
// characters from the library; step 2 sets group settings; step 3 reviews.
// Reuses the shared StepIndicator. On edit (/groups/edit/:id) it preloads the
// group; changing the roster replaces membership server-side.

import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';

interface Character {
  id: string;
  name: string;
  hasAvatar: boolean;
}
interface Settings {
  name: string;
  turnOrder: string;
  scenario: string;
  firstMessage: string;
  systemPrompt: string;
  autoAdvance: boolean;
  directorMode: boolean;
  chaosModeEnabled: boolean;
  inheritCharacterLorebooks: boolean;
}
interface GroupDetail extends Settings {
  members: { id: string; name: string }[];
}

const STEPS = ['Members', 'Settings', 'Review'];
const EMPTY: Settings = {
  name: '',
  turnOrder: 'roundRobin',
  scenario: '',
  firstMessage: '',
  systemPrompt: '',
  autoAdvance: false,
  directorMode: false,
  chaosModeEnabled: false,
  inheritCharacterLorebooks: true,
};

export function CreateGroupPage() {
  const { id } = useParams<{ id: string }>();
  const editing = Boolean(id);
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [chars, setChars] = useState<Character[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [rosterChanged, setRosterChanged] = useState(!editing);
  const [s, setS] = useState<Settings>(EMPTY);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get<Character[]>('/api/characters?sort=name').then(setChars).catch(() => {});
  }, []);

  // On edit, preload the group's settings (membership is shown but the roster
  // is only replaced if the user actually changes the selection).
  useEffect(() => {
    if (!id) return;
    api
      .get<GroupDetail>(`/api/groups/${id}/detail`)
      .then((g) => {
        setS({
          name: g.name,
          turnOrder: g.turnOrder,
          scenario: g.scenario,
          firstMessage: g.firstMessage,
          systemPrompt: g.systemPrompt,
          autoAdvance: g.autoAdvance,
          directorMode: g.directorMode,
          chaosModeEnabled: g.chaosModeEnabled,
          inheritCharacterLorebooks: g.inheritCharacterLorebooks,
        });
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
  }, [id]);

  const set = <K extends keyof Settings>(key: K, value: Settings[K]) => setS({ ...s, [key]: value });
  const toggle = (cid: string) => {
    setRosterChanged(true);
    setSelected((prev) => (prev.includes(cid) ? prev.filter((x) => x !== cid) : [...prev, cid]));
  };

  const selectedNames = useMemo(
    () => chars.filter((c) => selected.includes(c.id)).map((c) => c.name),
    [chars, selected],
  );
  // On create the roster must have ≥2; on edit it's optional (keep existing).
  const membersOk = editing ? !rosterChanged || selected.length >= 2 : selected.length >= 2;

  const submit = async () => {
    setBusy(true);
    setError('');
    const body: Record<string, unknown> = { ...s };
    if (!editing || rosterChanged) body.characterIds = selected;
    try {
      if (editing) {
        await api.post(`/api/groups/${id}`, body);
        navigate('/');
      } else {
        const res = await api.post<{ id: string }>('/api/groups/create', body);
        await api.post('/api/chat/select-group', { groupId: res.id });
        navigate('/chat');
      }
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save group');
      setBusy(false);
    }
  };

  return (
    <div className="page wizard">
      <div className="page-head">
        <h2>{editing ? 'Edit group' : 'Create group'}</h2>
        <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
      </div>
      <StepIndicator steps={STEPS} current={step} onJump={setStep} />

      <div className="wizard-body">
        {step === 0 && (
          <>
            <p className="muted small">
              {editing
                ? 'Pick members to replace the current roster, or leave unchanged to keep it.'
                : 'Pick at least 2 characters for this group.'}
            </p>
            <div className="char-grid">
              {chars.map((c) => (
                <button
                  key={c.id}
                  className={`char-card${selected.includes(c.id) ? ' selected' : ''}`}
                  onClick={() => toggle(c.id)}
                >
                  <div className="char-avatar">
                    {c.hasAvatar ? (
                      <img src={`/api/characters/${c.id}/avatar`} alt="" loading="lazy" />
                    ) : (
                      <span className="char-initial">{c.name.charAt(0).toUpperCase()}</span>
                    )}
                  </div>
                  <div className="char-name">{c.name}</div>
                </button>
              ))}
            </div>
          </>
        )}

        {step === 1 && (
          <>
            <label>
              Group name<span className="req"> *</span>
              <input value={s.name} onChange={(e) => set('name', e.target.value)} />
            </label>
            <label>
              Turn order
              <select value={s.turnOrder} onChange={(e) => set('turnOrder', e.target.value)}>
                <option value="roundRobin">Round robin</option>
                <option value="random">Random</option>
              </select>
            </label>
            <label>
              Scenario
              <textarea rows={3} value={s.scenario} onChange={(e) => set('scenario', e.target.value)} />
            </label>
            <label>
              Group first message
              <textarea rows={3} value={s.firstMessage} onChange={(e) => set('firstMessage', e.target.value)} />
            </label>
            <label>
              Group system prompt
              <textarea rows={3} value={s.systemPrompt} onChange={(e) => set('systemPrompt', e.target.value)} />
            </label>
            <label className="tool-toggle"><span>Auto-advance turns</span>
              <input type="checkbox" checked={s.autoAdvance} onChange={(e) => set('autoAdvance', e.target.checked)} /></label>
            <label className="tool-toggle"><span>Director mode</span>
              <input type="checkbox" checked={s.directorMode} onChange={(e) => set('directorMode', e.target.checked)} /></label>
            <label className="tool-toggle"><span>Chaos mode</span>
              <input type="checkbox" checked={s.chaosModeEnabled} onChange={(e) => set('chaosModeEnabled', e.target.checked)} /></label>
            <label className="tool-toggle"><span>Inherit character lorebooks</span>
              <input type="checkbox" checked={s.inheritCharacterLorebooks} onChange={(e) => set('inheritCharacterLorebooks', e.target.checked)} /></label>
          </>
        )}

        {step === 2 && (
          <div className="review">
            <p><strong>{s.name || '(unnamed)'}</strong></p>
            <div className="stat-line"><span className="muted">Members</span>
              <span className="review-val">{rosterChanged || !editing ? selectedNames.join(', ') || '(none)' : 'unchanged'}</span></div>
            <div className="stat-line"><span className="muted">Turn order</span><span>{s.turnOrder}</span></div>
            {s.scenario && <div className="stat-line"><span className="muted">Scenario</span><span className="review-val">{s.scenario.slice(0, 60)}</span></div>}
            {error && <p className="error">{error}</p>}
          </div>
        )}
      </div>

      <div className="wizard-nav">
        <button disabled={step === 0} onClick={() => setStep(step - 1)}>← Back</button>
        {step < STEPS.length - 1 ? (
          <button
            className="primary"
            disabled={(step === 0 && !membersOk)}
            onClick={() => setStep(step + 1)}
          >
            Next →
          </button>
        ) : (
          <button className="primary" disabled={busy || !s.name.trim() || !membersOk} onClick={submit}>
            {busy ? 'Saving…' : editing ? 'Save group' : 'Create group'}
          </button>
        )}
      </div>
    </div>
  );
}
