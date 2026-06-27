// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit an existing character — the web mirror of the Flutter character editor.
// Round-trips the core text fields, tags, alternate greetings, the full
// lorebook (enabled + sticky depth), linked worlds, and the Realism Engine +
// Needs Simulation seeds (via /detail's `realism` block ↔ the shared
// realism_extensions_json helper). Posts to /api/characters/<id>.

import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { AvatarManager } from '../components/AvatarManager';
import { AltGreetingsEditor } from '../components/AltGreetingsEditor';
import { MacroField } from '../components/MacroField';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { RealismFormSection } from '../components/realism/RealismFormSection';
import { NeedsFormSection } from '../components/realism/NeedsFormSection';
import { TokenBadge } from '../components/realism/controls';
import { type RealismValues, realismFromDetail } from '../components/realism/realismTypes';

interface RawLore {
  name?: string;
  key?: string;
  content?: string;
  enabled?: boolean;
  constant?: boolean;
  stickyDepth?: number;
}
interface CharDetail {
  id: string;
  name: string;
  description: string;
  personality: string;
  scenario: string;
  firstMessage: string;
  mesExample: string;
  systemPrompt: string;
  postHistoryInstructions: string;
  tags: string[];
  alternateGreetings: string[];
  worldNames: string[];
  lorebook?: { entries: RawLore[] } | null;
  realism?: Partial<RealismValues> | null;
}

const FIELDS: { key: keyof CharDetail; label: string; rows: number }[] = [
  { key: 'description', label: 'Description', rows: 5 },
  { key: 'personality', label: 'Personality', rows: 3 },
  { key: 'scenario', label: 'Scenario', rows: 3 },
  { key: 'firstMessage', label: 'First message', rows: 4 },
  { key: 'mesExample', label: 'Example dialogue', rows: 4 },
  { key: 'systemPrompt', label: 'System prompt', rows: 3 },
  { key: 'postHistoryInstructions', label: 'Post-history instructions', rows: 3 },
];

export function CharacterEditPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [c, setC] = useState<CharDetail | null>(null);
  const [tags, setTags] = useState('');
  const [greetings, setGreetings] = useState<string[]>([]);
  const [lore, setLore] = useState<LoreEntry[]>([]);
  const [rv, setRv] = useState<RealismValues | null>(null);
  const [worldNames, setWorldNames] = useState<string[]>([]);
  const [allWorlds, setAllWorlds] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!id) return;
    api
      .get<CharDetail>(`/api/characters/${id}/detail`)
      .then((d) => {
        setC(d);
        setTags((d.tags ?? []).join(', '));
        setGreetings(d.alternateGreetings ?? []);
        setWorldNames(d.worldNames ?? []);
        setRv(realismFromDetail(d.realism));
        setLore(
          (d.lorebook?.entries ?? []).map((e) => ({
            name: e.name ?? '',
            key: e.key ?? '',
            content: e.content ?? '',
            enabled: e.enabled ?? true,
            constant: e.constant ?? false,
            stickyDepth: e.stickyDepth ?? 1,
          })),
        );
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
    api
      .get<{ worlds: { name: string }[] }>('/api/worlds')
      .then((r) => setAllWorlds((r.worlds ?? []).map((w) => w.name)))
      .catch(() => setAllWorlds([]));
  }, [id]);

  // Mirror the desktop _updateTokenCount exactly: name + the seven text fields +
  // the alternate greetings. The lorebook is intentionally excluded (lore is
  // injected on demand, not part of the base card budget).
  const tokenChars = useMemo(() => {
    if (!c) return 0;
    const fieldText =
      c.name.length + FIELDS.reduce((sum, f) => sum + ((c[f.key] as string) ?? '').length, 0);
    const greetingText = greetings.reduce((sum, g) => sum + g.length, 0);
    return fieldText + greetingText;
  }, [c, greetings]);

  if (error && !c) return <div className="page"><p className="error">{error}</p></div>;
  if (!c || !rv) return <div className="centered"><div className="spinner" /></div>;

  const setField = (key: keyof CharDetail, value: string) => setC({ ...c, [key]: value });
  const patch = (p: Partial<RealismValues>) => setRv({ ...rv, ...p });
  const toggleWorld = (name: string) =>
    setWorldNames(worldNames.includes(name) ? worldNames.filter((w) => w !== name) : [...worldNames, name]);

  const save = async () => {
    setSaving(true);
    setError('');
    try {
      await api.post(`/api/characters/${id}`, {
        name: c.name,
        description: c.description,
        personality: c.personality,
        scenario: c.scenario,
        firstMessage: c.firstMessage,
        mesExample: c.mesExample,
        systemPrompt: c.systemPrompt,
        postHistoryInstructions: c.postHistoryInstructions,
        tags: tags.split(',').map((t) => t.trim()).filter(Boolean),
        alternateGreetings: greetings.filter((g) => g.trim()),
        worldNames,
        lorebook: lore.filter((e) => e.key.trim() || e.content.trim()),
        ...rv,
      });
      navigate(-1);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save');
      setSaving(false);
    }
  };

  const del = async () => {
    if (!window.confirm(`Delete "${c.name}"? This removes the character and its chat history.`)) return;
    setDeleting(true);
    setError('');
    try {
      await api.post(`/api/characters/${id}/delete`);
      navigate('/');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not delete');
      setDeleting(false);
    }
  };

  return (
    <div className="page">
      <div className="page-head">
        <h2>Edit character</h2>
        <div className="row-actions">
          <TokenBadge chars={tokenChars} />
          <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
        </div>
      </div>
      <label>
        Name
        <input value={c.name} onChange={(e) => setField('name', e.target.value)} />
      </label>
      {FIELDS.map((f) => (
        <MacroField
          key={f.key}
          label={f.label}
          rows={f.rows}
          value={(c[f.key] as string) ?? ''}
          onChange={(val) => setField(f.key, val)}
        />
      ))}
      <label>
        Tags (comma-separated)
        <input value={tags} onChange={(e) => setTags(e.target.value)} />
      </label>

      <h3 className="section-label">Alternate greetings</h3>
      <AltGreetingsEditor greetings={greetings} onChange={setGreetings} />

      <h3 className="section-label">Lorebook</h3>
      <LoreEntriesEditor entries={lore} onChange={setLore} />

      <h3 className="section-label">Linked worlds</h3>
      {allWorlds.length === 0 ? (
        <p className="muted small">No worlds yet. Create one from the Worlds page to link it here.</p>
      ) : (
        <div className="world-picker">
          {allWorlds.map((w) => (
            <label className="tool-toggle" key={w}>
              <span>{w}</span>
              <input type="checkbox" checked={worldNames.includes(w)} onChange={() => toggleWorld(w)} />
            </label>
          ))}
        </div>
      )}

      <h3 className="section-label">Realism Engine</h3>
      <RealismFormSection v={rv} set={patch} />

      <h3 className="section-label">Needs Simulation</h3>
      <NeedsFormSection v={rv} set={patch} />

      <h3 className="section-label">Avatars &amp; expressions</h3>
      <AvatarManager characterId={c.id} />

      {error && <p className="error">{error}</p>}
      <div className="wizard-nav">
        <button className="danger" disabled={deleting} onClick={del}>
          {deleting ? 'Deleting…' : 'Delete character'}
        </button>
        <button className="primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : 'Save character'}
        </button>
      </div>
    </div>
  );
}
