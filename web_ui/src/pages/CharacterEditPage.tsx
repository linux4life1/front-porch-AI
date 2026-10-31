// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit an existing character — the web mirror of the Flutter character editor.
// Round-trips the core text fields, tags, alternate greetings, the full
// lorebook (enabled + sticky depth), linked worlds, and the Realism Engine +
// Needs Simulation seeds (via /detail's `realism` block ↔ the shared
// realism_extensions_json helper). Posts to /api/characters/<id>.
//
// At /groups/<groupId>/members/<memberId>/edit it is a group member's editor
// (the desktop member editor's twin): it edits the group's own copy through
// /api/groups/<groupId>/members/<memberId>, says so in a banner, and shows
// the member's own settings as switches and the group's as read-only lines.
// Where the member starts in the group's new chats goes back as
// `groupStart` (the group's seed for them). The library card and its other
// chats stay as they are.

import { Fragment, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { AvatarManager } from '../components/AvatarManager';
import { AltGreetingsEditor } from '../components/AltGreetingsEditor';
import { CharacterStatsCard } from '../components/CharacterStatsCard';
import { MacroField } from '../components/MacroField';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { RealismFormSection } from '../components/realism/RealismFormSection';
import { useAdultFlags } from '../components/realism/useAdultThemes';
import { usePassageOfTime } from '../components/realism/usePassageOfTime';
import { NeedsFormSection } from '../components/realism/NeedsFormSection';
import {
  type MemberStart,
  GroupLine,
  groupLineTexts,
  memberSectionNotes,
  noStartNote,
  parseGroupLines,
  parseMemberStart,
} from '../components/realism/memberGroup';
import { TokenBadge } from '../components/realism/controls';
import { type RealismValues, compactGreetingPairs, realismFromDetail } from '../components/realism/realismTypes';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';
import { type TreeWorld } from './worlds/locations';
import { CharacterWorldsSection } from '../components/groupSetting/CharacterWorldsSection';
import { NO_WORLD, type WorldChoice } from '../components/groupSetting/groupWorldChoice';

interface RawLore {
  name?: string;
  key?: string;
  content?: string;
  enabled?: boolean;
  constant?: boolean;
  stickyDepth?: number;
  /** The entry's whole stored JSON; sent back untouched on save so what
   *  the editor does not show (imported fields, the creator's fingerprint
   *  that tells its own entries from hand-edited ones) survives. */
  ext?: unknown;
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
  /** Where new chats meet (additive; absent from an older app). */
  worlds?: { settingId: string | null; loreIds: string[]; legacyWorldCount?: number };
  lorebook?: { entries: RawLore[] } | null;
  realism?: Partial<RealismValues> | null;
  ttsVoice?: string | null;
  /** The member editor's group (its detail only). */
  groupName?: string;
  /** The group's own switches, read-only (member detail; additive). */
  group?: unknown;
  /** Where the member starts in the group's new chats (member detail). */
  start?: unknown;
  /** A lite member: Realism, Needs and Afterglow start at promotion. */
  lite?: boolean;
  /** False while Porch Life does not let Realism run (absent: allowed). */
  realismAllowed?: boolean;
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
  const { adult: adultThemes, afterglow } = useAdultFlags();
  const clockOn = usePassageOfTime();
  const params = useParams<{ id: string; groupId: string; memberId: string }>();
  const member = params.groupId !== undefined && params.memberId !== undefined;
  const id = member ? params.memberId : params.id;
  const base = member
    ? `/api/groups/${params.groupId}/members/${params.memberId}`
    : `/api/characters/${params.id}`;
  const navigate = useNavigate();
  const [c, setC] = useState<CharDetail | null>(null);
  const [tags, setTags] = useState('');
  const [greetings, setGreetings] = useState<string[]>([]);
  const [lore, setLore] = useState<LoreEntry[]>([]);
  const [rv, setRv] = useState<RealismValues | null>(null);
  const [worldChoice, setWorldChoice] = useState<WorldChoice>(NO_WORLD);
  const [allWorlds, setAllWorlds] = useState<TreeWorld[]>([]);
  const [ttsVoice, setTtsVoice] = useState('');
  // The member's start as edited, and as loaded: only a moved start is sent,
  // so a page open since another device changed it does not put it back.
  const [start, setStart] = useState<MemberStart | null>(null);
  const [startAsLoaded, setStartAsLoaded] = useState('null');
  const [voiceStatus, setVoiceStatus] = useState<VoiceStatus | null>(null);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');
  // The editable state as loaded; anything else is an unsaved edit.
  const [loaded, setLoaded] = useState<string | null>(null);
  const editable =
    c && rv ? JSON.stringify({ c, tags, greetings, lore, rv, worldChoice, ttsVoice, start }) : null;
  useEffect(() => {
    if (loaded === null && editable !== null) setLoaded(editable);
  }, [loaded, editable]);
  const { prompt, leaveWithoutAsking } = useUnsavedChanges(
    loaded !== null && editable !== loaded,
  );

  useEffect(() => {
    if (!id) return;
    api
      .get<CharDetail>(`${base}/detail`)
      .then((d) => {
        setC(d);
        setTags((d.tags ?? []).join(', '));
        setGreetings(d.alternateGreetings ?? []);
        setWorldChoice({
          settingId: d.worlds?.settingId ?? null,
          loreIds: d.worlds?.loreIds ?? [],
        });
        setTtsVoice(d.ttsVoice ?? '');
        const s = parseMemberStart(d.start);
        setStart(s);
        setStartAsLoaded(JSON.stringify(s));
        setRv(realismFromDetail(d.realism));
        setLore(
          (d.lorebook?.entries ?? []).map((e) => ({
            name: e.name ?? '',
            key: e.key ?? '',
            content: e.content ?? '',
            enabled: e.enabled ?? true,
            constant: e.constant ?? false,
            stickyDepth: e.stickyDepth ?? 1,
            ...(e.ext !== undefined ? { ext: e.ext } : {}),
          })),
        );
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
    api
      .get<{ worlds: TreeWorld[] }>('/api/worlds')
      .then((r) => setAllWorlds(r.worlds ?? []))
      .catch(() => setAllWorlds([]));
    api
      .get<VoiceStatus>('/api/voice/status')
      .then(setVoiceStatus)
      .catch(() => setVoiceStatus(null));
  }, [id, base]);

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
  const group = member ? parseGroupLines(c.group) : null;
  const notes = group ? memberSectionNotes(c.name, group) : null;
  const hiddenNote = !member
    ? undefined
    : c.lite
      ? `${c.name}'s Realism, Needs and Afterglow start when they are promoted to a full member of this group.`
      : c.realismAllowed === false
        ? `Realism, Needs and Afterglow are hidden: the Realism Engine is off in Porch Life. ${c.name}'s settings are kept.`
        : undefined;
  const startMoved = member && start !== null && JSON.stringify(start) !== startAsLoaded;
  const patch = (p: Partial<RealismValues>) => setRv({ ...rv, ...p });

  const save = async () => {
    setSaving(true);
    setError('');
    try {
      await api.post(base, {
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
            // The relay keeps an untouched unsplit card's worlds as stored.
            ...(c.worlds ? { worlds: worldChoice } : {}),
            ttsVoice,
            lorebook: lore.filter((e) => e.key.trim() || e.content.trim()),
            ...rv,
            greetingSeeds: paired.seeds,
            ...(startMoved ? { groupStart: start } : {}),
          };
        })(),
      });
      setLoaded(editable);
      leaveWithoutAsking();
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
      leaveWithoutAsking();
      navigate('/');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not delete');
      setDeleting(false);
    }
  };

  return (
    <div className="page">
      {prompt}
      <div className="page-head">
        <h2>Edit character</h2>
        <div className="row-actions">
          <TokenBadge chars={tokenChars} />
          <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
        </div>
      </div>
      {member ? (
        <p className="card muted" data-testid="group-member-editor-banner">
          {c.name} in {c.groupName}. Changes apply to {c.name} in this group; the
          library card and its other chats stay as they are.
        </p>
      ) : (
        <CharacterStatsCard characterId={c.id} />
      )}
      <label>
        Name
        <input value={c.name} onChange={(e) => setField('name', e.target.value)} />
      </label>
      {FIELDS.map((f) => (
        <Fragment key={f.key}>
          <MacroField
            label={f.label}
            rows={f.rows}
            value={(c[f.key] as string) ?? ''}
            onChange={(val) => setField(f.key, val)}
          />
          {f.key === 'scenario' && notes && (
            <p className="muted small" data-testid="member-scenario-note">
              {notes.scenario}
            </p>
          )}
        </Fragment>
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
        showNeeds
        clockOn={clockOn}
        onSeedsChange={(seeds) => patch({ greetingSeeds: seeds })}
      />
      {notes && (
        <p className="muted small" data-testid="member-greeting-note">
          {notes.greeting}
        </p>
      )}

      <h3 className="section-label">Lorebook</h3>
      {notes && (
        <p className="muted small" data-testid="member-lorebook-note">
          {notes.lorebook}
        </p>
      )}
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

      {notes && (
        <p className="card muted small" data-testid="member-worlds-note">
          {notes.worlds}
        </p>
      )}
      <CharacterWorldsSection
        name={c.name}
        value={worldChoice}
        onChange={setWorldChoice}
        worlds={allWorlds}
        legacyWorldCount={c.worlds?.legacyWorldCount ?? 0}
      />

      <h3 className="section-label">Realism Engine</h3>
      <RealismFormSection
        v={rv}
        set={patch}
        showIntimate={adultThemes}
        afterglowOn={afterglow}
        member={member ? c.name : undefined}
        group={group}
        start={start}
        setStart={setStart}
        hiddenNote={hiddenNote}
        noStartNote={member ? noStartNote() : undefined}
      />

      {(member ? !hiddenNote : rv.realismEnabled) && (
        <>
          <h3 className="section-label">Needs Simulation</h3>
          <NeedsFormSection
            v={rv}
            set={patch}
            clockOn={clockOn}
            showSwitch={!member}
            groupLine={
              group ? <GroupLine line={groupLineTexts(group).needs} testId="group-line-needs" /> : undefined
            }
          />
        </>
      )}

      {!member && (
        <>
          <h3 className="section-label">Avatars &amp; expressions</h3>
          <AvatarManager characterId={c.id} />
        </>
      )}

      {error && <p className="error">{error}</p>}
      <div className="wizard-nav">
        {!member && (
          <button className="danger" disabled={deleting} onClick={del}>
            {deleting ? 'Deleting…' : 'Delete character'}
          </button>
        )}
        <button className="primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : 'Save character'}
        </button>
      </div>
    </div>
  );
}
