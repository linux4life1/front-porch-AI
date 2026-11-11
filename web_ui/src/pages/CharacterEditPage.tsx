// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit an existing character — the web mirror of the Flutter character editor.
// Round-trips the core text fields, tags, alternate greetings, the full
// lorebook (enabled + sticky depth), linked worlds, and the Realism Engine +
// Needs Simulation seeds (via /detail's `realism` block ↔ the shared
// realism_extensions_json helper). Posts to /api/characters/<id>.
//
// At /groups/<groupId>/members/<memberId>/edit it is the same editor on a
// group member's own copy (docs/design/group-editor.md): it edits the
// group's copy through /api/groups/<groupId>/members/<memberId>, adds a
// notice and an "In <group>" section, and greys out what the group owns
// (Time & Day, Chaos Mode, Realism Verification, the Worlds tab). A 1:1
// editor says when its character is also in groups.

import { useEffect, useMemo, useRef, useState } from 'react';
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
import { EditorTabs, type EditorTab } from '../components/EditorTabs';
import { GroupMemberSection, type GroupValues, parseGroupValues } from '../components/GroupMemberSection';
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
  /** The group's shared scene, greyed in a member's Time & Day. */
  scene?: { timeOfDay?: string; dayCount?: number };
  /** The other members, for "how they start out feeling about the others". */
  others?: { id: string; name: string }[];
  /** The group's values for the member (the store Edit group shows). */
  groupValues?: unknown;
  /** A 1:1 editor: the groups the character is also in. */
  inGroups?: string[];
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
  // The page is named for the card as it opened, not as it is being typed.
  const [title, setTitle] = useState('');
  const [tags, setTags] = useState('');
  const [greetings, setGreetings] = useState<string[]>([]);
  const [lore, setLore] = useState<LoreEntry[]>([]);
  const [rv, setRv] = useState<RealismValues | null>(null);
  const [worldChoice, setWorldChoice] = useState<WorldChoice>(NO_WORLD);
  const [allWorlds, setAllWorlds] = useState<TreeWorld[]>([]);
  const [ttsVoice, setTtsVoice] = useState('');
  const [tab, setTab] = useState<EditorTab>('Details');
  // The group's values for the member as edited, and as loaded: only moved
  // values are sent, so a page open since another device changed them does
  // not put them back.
  const [gv, setGv] = useState<GroupValues | null>(null);
  const [gvAsLoaded, setGvAsLoaded] = useState('null');
  const [voiceStatus, setVoiceStatus] = useState<VoiceStatus | null>(null);
  const [saving, setSaving] = useState(false);
  // A second tap before the first save returns writes nothing.
  const savingNow = useRef(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');
  // The editable state as loaded; anything else is an unsaved edit.
  const [loaded, setLoaded] = useState<string | null>(null);
  const editable =
    c && rv ? JSON.stringify({ c, tags, greetings, lore, rv, worldChoice, ttsVoice, gv }) : null;
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
        setTitle(d.name);
        setTags((d.tags ?? []).join(', '));
        setGreetings(d.alternateGreetings ?? []);
        setWorldChoice({
          settingId: d.worlds?.settingId ?? null,
          loreIds: d.worlds?.loreIds ?? [],
        });
        setTtsVoice(d.ttsVoice ?? '');
        const g = parseGroupValues(d.groupValues);
        setGv(g);
        setGvAsLoaded(JSON.stringify(g));
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
  const hiddenNote = !member
    ? undefined
    : c.lite
      ? `${c.name}'s Realism, Needs and Afterglow start when they are promoted to a full member of this group.`
      : c.realismAllowed === false
        ? `Realism, Needs and Afterglow are hidden: the Realism Engine is off in Porch Life. ${c.name}'s settings are kept.`
        : undefined;
  const gvMoved = member && gv !== null && JSON.stringify(gv) !== gvAsLoaded;
  const patch = (p: Partial<RealismValues>) => setRv({ ...rv, ...p });

  const save = async () => {
    if (savingNow.current) return;
    savingNow.current = true;
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
            ...(gvMoved ? { groupValues: gv } : {}),
          };
        })(),
      });
      setLoaded(editable);
      leaveWithoutAsking();
      navigate(-1);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save');
      savingNow.current = false;
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

  const memberTabLocks: Partial<Record<EditorTab, string>> = member
    ? { Worlds: 'Worlds are set per group, not per character.' }
    : {};
  const TIME_DAY_LOCK = 'Time & Day is set per group, not per character.';
  const CHAOS_LOCK = 'Chaos Mode is set per group for now.';
  const VERIFICATION_LOCK = 'Realism Verification is set per group, not per character.';

  const importLore = async () => {
    try {
      const list = await api.get<{ id: string; name: string }[]>('/api/characters?scope=allCharacters');
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
  };

  const field = (key: keyof CharDetail) => {
    const f = FIELDS.find((x) => x.key === key)!;
    return (
      <MacroField
        label={f.label}
        rows={f.rows}
        value={(c[f.key] as string) ?? ''}
        onChange={(val) => setField(f.key, val)}
      />
    );
  };

  return (
    <div className="page">
      {prompt}
      <div className="page-head">
        <h2>Edit {title || c.name}</h2>
        <div className="row-actions">
          <TokenBadge chars={tokenChars} />
          <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
          <button className="primary" onClick={save} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
      <EditorTabs tab={tab} onTab={setTab} locked={memberTabLocks} />

      {tab === 'Details' && (
        <>
          {member ? (
            <div className="group-notice" data-testid="group-member-notice">
              <span aria-hidden>👥</span>
              <p>
                <strong>
                  You&apos;re editing {c.name} in {c.groupName} only.
                </strong>
                <br />
                This group keeps its own copy of {c.name}. Changes here don&apos;t affect your solo
                chats with {c.name}, and edits to {c.name}&apos;s own card don&apos;t reach this group.
              </p>
            </div>
          ) : (
            (c.inGroups ?? []).length > 0 && (
              <div className="group-notice" data-testid="character-in-groups-note">
                <span aria-hidden>👥</span>
                <p>
                  {c.name} is also in {joinNames(c.inGroups ?? [])}. Groups keep their own copy; changes
                  here don&apos;t reach them.
                </p>
              </div>
            )
          )}
          {!member && <CharacterStatsCard characterId={c.id} />}

          <h3 className="section-label">Identity</h3>
          <label>
            Name
            <input value={c.name} onChange={(e) => setField('name', e.target.value)} />
          </label>
          <label>
            Tags (comma-separated)
            <input value={tags} onChange={(e) => setTags(e.target.value)} />
          </label>

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

          <h3 className="section-label">Personality &amp; World</h3>
          {field('description')}
          {field('personality')}
          {field('scenario')}

          <details className="editor-section">
            <summary>Advanced Prompts</summary>
            {field('systemPrompt')}
            {field('postHistoryInstructions')}
          </details>

          <h3 className="section-label">Realism Engine</h3>
          <RealismFormSection
            v={rv}
            set={patch}
            showIntimate={adultThemes}
            afterglowOn={afterglow}
            hiddenNote={hiddenNote}
            scene={
              member && c.scene
                ? { timeOfDay: c.scene.timeOfDay ?? rv.timeOfDay, dayCount: c.scene.dayCount ?? rv.dayCount }
                : undefined
            }
            lockTimeDay={member ? TIME_DAY_LOCK : undefined}
            lockChaos={member ? CHAOS_LOCK : undefined}
            lockVerification={member ? VERIFICATION_LOCK : undefined}
          />

          {!hiddenNote && rv.realismEnabled && (
            <>
              <h3 className="section-label">Needs Simulation</h3>
              <NeedsFormSection v={rv} set={patch} clockOn={clockOn} />
            </>
          )}

          {member && gv && (
            <GroupMemberSection
              groupName={c.groupName ?? 'the group'}
              memberName={c.name}
              others={c.others ?? []}
              values={gv}
              onChange={setGv}
            />
          )}

          {!member && (
            <>
              <h3 className="section-label">Avatars &amp; expressions</h3>
              <AvatarManager characterId={c.id} />
            </>
          )}
        </>
      )}

      {tab === 'Dialogue' && (
        <>
          <h3 className="section-label">First Message</h3>
          {field('firstMessage')}
          <h3 className="section-label">Alternate Greetings</h3>
          <AltGreetingsEditor
            greetings={greetings}
            onChange={setGreetings}
            seeds={rv.greetingSeeds}
            showNeeds
            clockOn={clockOn}
            onSeedsChange={(seeds) => patch({ greetingSeeds: seeds })}
          />
          <h3 className="section-label">Example Dialogue</h3>
          {field('mesExample')}
        </>
      )}

      {tab === 'Lorebook' && (
        <>
          <h3 className="section-label">Lorebook</h3>
          <LoreEntriesEditor entries={lore} onChange={setLore} />
          <div className="row-actions" style={{ marginTop: 8 }}>
            <button type="button" className="ghost" onClick={importLore}>
              From character…
            </button>
          </div>
        </>
      )}

      {tab === 'Worlds' && !member && (
        <CharacterWorldsSection
          name={c.name}
          value={worldChoice}
          onChange={setWorldChoice}
          worlds={allWorlds}
          legacyWorldCount={c.worlds?.legacyWorldCount ?? 0}
        />
      )}

      {error && <p className="error">{error}</p>}
      {!member && (
        <div className="wizard-nav">
          <button className="danger" disabled={deleting} onClick={del}>
            {deleting ? 'Deleting…' : 'Delete character'}
          </button>
        </div>
      )}
    </div>
  );
}

/** "The Porch Trio and Book Club", as a sentence lists names. */
export function joinNames(names: string[]): string {
  if (names.length <= 1) return names[0] ?? '';
  if (names.length === 2) return `${names[0]} and ${names[1]}`;
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}
