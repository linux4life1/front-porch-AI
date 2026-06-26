// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { AvatarManager } from '../components/AvatarManager';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';

interface RawLore {
  name?: string;
  key?: string;
  content?: string;
  constant?: boolean;
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
  lorebook?: { entries: RawLore[] } | null;
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
  const [lore, setLore] = useState<LoreEntry[]>([]);
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
        setLore(
          (d.lorebook?.entries ?? []).map((e) => ({
            name: e.name ?? '',
            key: e.key ?? '',
            content: e.content ?? '',
            constant: e.constant ?? false,
          })),
        );
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
  }, [id]);

  if (error && !c) return <div className="page"><p className="error">{error}</p></div>;
  if (!c) return <div className="centered"><div className="spinner" /></div>;

  const setField = (key: keyof CharDetail, value: string) => setC({ ...c, [key]: value });

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
        lorebook: lore.filter((e) => e.key.trim() || e.content.trim()),
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
        <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
      </div>
      <label>
        Name
        <input value={c.name} onChange={(e) => setField('name', e.target.value)} />
      </label>
      {FIELDS.map((f) => (
        <label key={f.key}>
          {f.label}
          <textarea
            value={(c[f.key] as string) ?? ''}
            rows={f.rows}
            onChange={(e) => setField(f.key, e.target.value)}
          />
        </label>
      ))}
      <label>
        Tags (comma-separated)
        <input value={tags} onChange={(e) => setTags(e.target.value)} />
      </label>

      <h3 className="section-label">Lorebook</h3>
      <LoreEntriesEditor entries={lore} onChange={setLore} />

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
