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
import { useAdultThemes } from '../components/realism/useAdultThemes';
import { NeedsFormSection } from '../components/realism/NeedsFormSection';
import { TokenBadge } from '../components/realism/controls';
import { type RealismValues, compactGreetingPairs, realismFromDetail } from '../components/realism/realismTypes';

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
  ttsVoice?: string | null;
}

interface VoiceStatus {
  ttsEnabled?: boolean;
  globalVoice?: string;
  voices?: { id: string; name: string; gender?: string }[];
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
  const adultThemes = useAdultThemes();
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [c, setC] = useState<CharDetail | null>(null);
  const [tags, setTags] = useState('');
  const [greetings, setGreetings] = useState<string[]>([]);
  const [lore, setLore] = useState<LoreEntry[]>([]);
  const [rv, setRv] = useState<RealismValues | null>(null);
  const [worldNames, setWorldNames] = useState<string[]>([]);
  const [allWorlds, setAllWorlds] = useState<string[]>([]);
  const [ttsVoice, setTtsVoice] = useState('');
  const [voiceStatus, setVoiceStatus] = useState<VoiceStatus | null>(null);
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
        setTtsVoice(d.ttsVoice ?? '');
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
    api
      .get<VoiceStatus>('/api/voice/status')
      .then(setVoiceStatus)
      .catch(() => setVoiceStatus(null));
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
        ...(() => {
          const paired = compactGreetingPairs(greetings, rv.greetingSeeds);
          return {
            alternateGreetings: paired.greetings,
            worldNames,
            ttsVoice,
            lorebook: lore.filter((e) => e.key.trim() || e.content.trim()),
            ...rv,
            greetingSeeds: paired.seeds,
          };
        })(),
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
      <AltGreetingsEditor
        greetings={greetings}
        onChange={setGreetings}
        seeds={rv.greetingSeeds}
        showNeeds={rv.needsSimEnabled}
        onSeedsChange={(seeds) => patch({ greetingSeeds: seeds })}
      />

      <h3 className="section-label">Lorebook</h3>
      <LoreEntriesEditor entries={lore} onChange={setLore} />
      <div className="row-actions" style={{ marginTop: 8 }}>
        <button
          type="button"
          className="ghost"
          onClick={async () => {
            try {
              const list = await api.get<{ id: string; name: string }[]>(
                '/api/characters?scope=allCharacters',
              );
              const others = (list ?? []).filter((x) => x.id !== id);
              if (!others.length) {
                setError('No other characters to import lore from.');
                return;
              }
              const pick = window.prompt(
                `Import lore from which character?\n${others.map((x) => x.name).join(', ')}`,
                others[0]?.name ?? '',
              );
              if (!pick?.trim()) return;
              const match =
                others.find((x) => x.name.toLowerCase() === pick.trim().toLowerCase()) ??
                others.find((x) => x.name.toLowerCase().includes(pick.trim().toLowerCase()));
              if (!match) {
                setError(`No character named "${pick}".`);
                return;
              }
              const d = await api.get<CharDetail>(`/api/characters/${match.id}/detail`);
              const incoming = (d.lorebook?.entries ?? []).map((e) => ({
                name: e.name ?? '',
                key: e.key ?? '',
                content: e.content ?? '',
                enabled: e.enabled ?? true,
                constant: e.constant ?? false,
                stickyDepth: e.stickyDepth ?? 1,
              }));
              if (!incoming.length) {
                setError(`${match.name} has no lorebook entries.`);
                return;
              }
              setLore((prev) => [...prev, ...incoming]);
              setError('');
            } catch (e) {
              setError(e instanceof Error ? e.message : 'Import failed');
            }
          }}
        >
          From character…
        </button>
      </div>

      {/* A character voice OVERRIDES the global Settings voice, and one can
          arrive without the user picking it (imported cards carry tts_voice).
          Desktop parity: visible AND clearable here. */}
      <h3 className="section-label">Voice</h3>
      {voiceStatus === null || (voiceStatus.voices ?? []).length === 0 ? (
        <p className="muted small">
          Enable text-to-speech on the desktop app to assign this character a voice.
        </p>
      ) : (
        <>
          <select
            className="voice-select"
            value={ttsVoice}
            onChange={(e) => setTtsVoice(e.target.value)}
          >
            <option value="">
              Use the global voice
              {voiceStatus.globalVoice
                ? ` (${(voiceStatus.voices ?? []).find((v) => v.id === voiceStatus.globalVoice)?.name ?? voiceStatus.globalVoice})`
                : ' (none picked yet)'}
            </option>
            {ttsVoice && !(voiceStatus.voices ?? []).some((v) => v.id === ttsVoice) && (
              <option value={ttsVoice}>{ttsVoice} — not available on this engine</option>
            )}
            {(voiceStatus.voices ?? []).map((v) => (
              <option key={v.id} value={v.id}>
                {v.gender === 'Male' ? '♂ ' : v.gender === 'Female' ? '♀ ' : '⚬ '}
                {v.name}
              </option>
            ))}
          </select>
          <p className="muted small">
            {ttsVoice
              ? 'This character speaks in their own voice — the Settings voice does not apply to them. Choose “Use the global voice” to follow Settings again.'
              : 'Following the voice set in text-to-speech settings.'}
          </p>
        </>
      )}

      <h3 className="section-label">Linked places</h3>
      {allWorlds.length === 0 ? (
        <p className="muted small">No places yet. Create one from the Worlds page to link it here.</p>
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
      <RealismFormSection v={rv} set={patch} showIntimate={adultThemes} />

      {rv.realismEnabled && (
        <>
          <h3 className="section-label">Needs Simulation</h3>
          <NeedsFormSection v={rv} set={patch} />
        </>
      )}

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
