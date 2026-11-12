// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit group: the character editor's four tabs (Details, Dialogue, Lorebook,
// Worlds) over a group, in the sections of docs/design/group-editor.md. The
// web twin of the desktop EditGroupPage; every setting is the group's default
// for new chats. Replaces the old Group Settings panel.

import { useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { AltGreetingsEditor } from '../components/AltGreetingsEditor';
import { CharacterStatsCard } from '../components/CharacterStatsCard';
import { EditorTabs, type EditorTab } from '../components/EditorTabs';
import { GreyedOut } from '../components/GreyedOut';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { MacroField } from '../components/MacroField';
import { feelingWord } from '../components/GroupMemberSection';
import { CharacterWorldsSection } from '../components/groupSetting/CharacterWorldsSection';
import { NO_WORLD, type WorldChoice } from '../components/groupSetting/groupWorldChoice';
import { Slider, ToggleRow, SelectRow } from '../components/realism/controls';
import { TIME_OPTIONS, titleCase, compactGreetingPairs, type GreetingSeed } from '../components/realism/realismTypes';
import { usePassageOfTime } from '../components/realism/usePassageOfTime';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';
import type { TreeWorld } from './worlds/locations';

interface Member {
  id: string;
  name: string;
  voice: string;
  prompt: string;
  note: string;
  strength: number;
}
interface RealismBlock {
  timeOfDay: string;
  dayCount: number;
  storyStartDate: string | null;
  storyStartTime: string | null;
  verificationEnabled: boolean;
  verificationStrictness: number;
  verificationMaxReprocesses: number;
  directorAuthority: boolean;
}
interface GroupDetail {
  id: string;
  name: string;
  turnOrder: string;
  autoAdvance: boolean;
  directorMode: boolean;
  personality: string;
  scenario: string;
  systemPrompt: string;
  postHistoryInstructions: string;
  mesExample: string;
  firstMessage: string;
  alternateGreetings: string[];
  greetingSeeds?: (GreetingSeed | null)[];
  tags: string[];
  chaosModeEnabled: boolean;
  inheritCharacterLorebooks: boolean;
  realism: RealismBlock;
  lorebook?: { entries: LoreEntry[] } | null;
  members: Member[];
  feelings: Record<string, Record<string, number>>;
  removedCount: number;
}

const TEXT: { key: keyof GroupDetail; label: string; rows: number }[] = [
  { key: 'personality', label: 'Personality', rows: 3 },
  { key: 'scenario', label: 'Scenario', rows: 3 },
  { key: 'systemPrompt', label: 'System Prompt', rows: 3 },
  { key: 'postHistoryInstructions', label: 'Post-History Instructions', rows: 3 },
  { key: 'firstMessage', label: 'Opening Message', rows: 4 },
  { key: 'mesExample', label: 'Example Conversations', rows: 4 },
];

export function GroupEditPage() {
  const { groupId } = useParams<{ groupId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  // Opened first (a link, a fresh tab): nothing behind it, so go Home
  // instead of leaving the app.
  const leave = () => (location.key === 'default' ? navigate('/') : navigate(-1));
  const clockOn = usePassageOfTime();
  const [g, setG] = useState<GroupDetail | null>(null);
  const [title, setTitle] = useState('');
  const [tab, setTab] = useState<EditorTab>('Details');
  const [tagText, setTagText] = useState('');
  const [alts, setAlts] = useState<string[]>([]);
  const [seeds, setSeeds] = useState<(GreetingSeed | null)[]>([]);
  const [lore, setLore] = useState<LoreEntry[]>([]);
  const [worldChoice, setWorldChoice] = useState<WorldChoice>(NO_WORLD);
  const [worldsAsLoaded, setWorldsAsLoaded] = useState('');
  const [allWorlds, setAllWorlds] = useState<TreeWorld[]>([]);
  const [candidates, setCandidates] = useState<{ id: string; name: string }[]>([]);
  const [saving, setSaving] = useState(false);
  // A second tap before the first save returns writes nothing.
  const savingNow = useRef(false);
  const [error, setError] = useState('');
  const [loaded, setLoaded] = useState<string | null>(null);

  const editable = g ? JSON.stringify({ g, alts, seeds, lore, worldChoice }) : null;
  useEffect(() => {
    if (loaded === null && editable !== null) setLoaded(editable);
  }, [loaded, editable]);
  const { prompt, leaveWithoutAsking } = useUnsavedChanges(loaded !== null && editable !== loaded);

  const load = (keepEdits = false) =>
    api
      .get<GroupDetail>(`/api/groups/${groupId}/detail`)
      .then((d) => {
        if (keepEdits) {
          setG((cur) => (cur ? { ...cur, members: d.members, removedCount: d.removedCount } : d));
          return;
        }
        setG(d);
        setTitle(d.name);
        setAlts(d.alternateGreetings ?? []);
        setSeeds(d.greetingSeeds ?? []);
        setLore(d.lorebook?.entries ?? []);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));

  useEffect(() => {
    void load();
    api
      .get<{ settingId: string | null; loreIds: string[] }>(`/api/groups/${groupId}/worlds`)
      .then((w) => {
        const c = { settingId: w.settingId ?? null, loreIds: w.loreIds ?? [] };
        setWorldChoice(c);
        setWorldsAsLoaded(JSON.stringify(c));
      })
      .catch(() => setWorldChoice(NO_WORLD));
    api
      .get<{ worlds: TreeWorld[] }>('/api/worlds')
      .then((r) => setAllWorlds(r.worlds ?? []))
      .catch(() => setAllWorlds([]));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groupId]);

  if (error && !g) return <div className="page"><p className="error">{error}</p></div>;
  if (!g) return <div className="centered"><div className="spinner" /></div>;

  const set = (p: Partial<GroupDetail>) => setG({ ...g, ...p });
  const setReal = (p: Partial<RealismBlock>) => setG({ ...g, realism: { ...g.realism, ...p } });
  const field = (key: keyof GroupDetail) => {
    const f = TEXT.find((x) => x.key === key)!;
    return (
      <MacroField
        label={f.label}
        rows={f.rows}
        value={(g[f.key] as string) ?? ''}
        onChange={(v) => set({ [f.key]: v } as Partial<GroupDetail>)}
      />
    );
  };
  const setMember = (id: string, p: Partial<Member>) =>
    set({ members: g.members.map((m) => (m.id === id ? { ...m, ...p } : m)) });
  const feeling = (from: string, to: string) => g.feelings?.[from]?.[to] ?? 0;
  const setFeeling = (from: string, to: string, n: number) =>
    set({ feelings: { ...g.feelings, [from]: { ...(g.feelings?.[from] ?? {}), [to]: n } } });

  const cast = async (body: Record<string, unknown>) => {
    try {
      await api.post(`/api/groups/${groupId}/cast`, body);
      await load(true);
      setError('');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'That cast change could not be made');
    }
  };
  const addMember = async () => {
    try {
      const list = await api.get<{ id: string; name: string }[]>('/api/characters?scope=allCharacters');
      const here = new Set(g.members.map((m) => m.name));
      setCandidates((list ?? []).filter((x) => !here.has(x.name)));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not list characters');
    }
  };

  const save = async () => {
    if (savingNow.current) return;
    savingNow.current = true;
    setSaving(true);
    setError('');
    try {
      const paired = compactGreetingPairs(alts, seeds);
      await api.post(`/api/groups/${groupId}/settings`, {
        name: g.name,
        turnOrder: g.turnOrder,
        autoAdvance: g.autoAdvance,
        directorMode: g.directorMode,
        personality: g.personality,
        scenario: g.scenario,
        systemPrompt: g.systemPrompt,
        postHistoryInstructions: g.postHistoryInstructions,
        mesExample: g.mesExample,
        firstMessage: g.firstMessage,
        alternateGreetings: paired.greetings,
        greetingSeeds: paired.seeds,
        tags: g.tags,
        chaosModeEnabled: g.chaosModeEnabled,
        inheritCharacterLorebooks: g.inheritCharacterLorebooks,
        lorebook: lore.filter((e) => e.key.trim() || e.content.trim()),
        realism: g.realism,
        characterSystemPrompts: Object.fromEntries(g.members.map((m) => [m.id, m.prompt])),
        characterAuthorNotes: Object.fromEntries(
          g.members.filter((m) => m.note.trim()).map((m) => [m.id, { note: m.note, strength: m.strength }]),
        ),
        feelings: g.feelings,
        ...(JSON.stringify(worldChoice) !== worldsAsLoaded ? { worlds: worldChoice } : {}),
      });
      setLoaded(editable);
      leaveWithoutAsking();
      leave();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save');
      savingNow.current = false;
      setSaving(false);
    }
  };

  const real = g.realism;
  return (
    <div className="page">
      {prompt}
      <div className="page-head editor-head">
        <h2>Edit {title || g.name}</h2>
        <div className="row-actions">
          <button className="ghost" onClick={leave}>Cancel</button>
          <button className="primary" onClick={save} disabled={saving || !g.name.trim()}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
      <EditorTabs tab={tab} onTab={setTab} />

      {tab === 'Details' && (
        <>
          <h3 className="section-label">Identity</h3>
          <label>
            <span>Group name</span>
            <input value={g.name} onChange={(e) => set({ name: e.target.value })} />
          </label>
          <p className="muted small">Cast</p>
          {g.members.map((m) => (
            <div key={m.id} className="row-actions" data-testid={`cast-row-${m.id}`}>
              <img
                className="cast-avatar"
                data-testid={`cast-avatar-${m.id}`}
                src={`/api/groups/${groupId}/members/${m.id}/avatar`}
                alt=""
                width={32}
                height={32}
              />
              <strong>{m.name}</strong>
              <button
                type="button"
                className="ghost"
                onClick={() => navigate(`/groups/${groupId}/members/${m.id}/edit`)}
              >
                Edit {m.name}&apos;s card
              </button>
              <button
                type="button"
                className="danger"
                onClick={() => {
                  if (window.confirm(`Remove ${m.name}? Their copy can be brought back here.`))
                    void cast({ action: 'remove', memberId: m.id });
                }}
              >
                Remove…
              </button>
            </div>
          ))}
          <div className="row-actions">
            <button type="button" className="ghost" onClick={addMember}>
              + Add a character
            </button>
            {g.removedCount > 0 ? (
              <button type="button" className="ghost" onClick={() => cast({ action: 'bringBack' })}>
                Bring back a removed member
              </button>
            ) : (
              <GreyedOut tooltip="No removed members to bring back.">
                <button type="button" className="ghost">
                  Bring back a removed member
                </button>
              </GreyedOut>
            )}
          </div>
          {candidates.length > 0 && (
            <div className="card" data-testid="cast-add-list">
              {candidates.map((x) => (
                <button
                  key={x.id}
                  type="button"
                  className="ghost"
                  onClick={() => {
                    setCandidates([]);
                    void cast({ action: 'add', characterId: x.id });
                  }}
                >
                  {x.name}
                </button>
              ))}
            </div>
          )}

          <h3 className="section-label">Turns</h3>
          <div className="tool-row">
            <span className="muted small">Turn order</span>
            <button
              className={g.turnOrder === 'roundRobin' ? 'primary small' : 'small'}
              onClick={() => set({ turnOrder: 'roundRobin' })}
            >
              Round Robin
            </button>
            <button
              className={g.turnOrder === 'random' ? 'primary small' : 'small'}
              onClick={() => set({ turnOrder: 'random' })}
            >
              Random
            </button>
          </div>
          <ToggleRow
            label="Auto-advance"
            hint="After a character finishes responding, automatically prompt the next speaker. Works with both turn orders and Director Mode."
            value={g.autoAdvance}
            onChange={(b) => set({ autoAdvance: b })}
          />
          <ToggleRow
            label="Start this group in Director Mode"
            hint="New chats open with you directing the scene instead of taking part in it."
            value={g.directorMode}
            onChange={(b) => set({ directorMode: b })}
          />

          <h3 className="section-label">Voice</h3>
          <p className="muted small" data-testid="group-voice-line">
            Each member speaks in their own text-to-speech voice, set in their card:{' '}
            {g.members.map((m) => `${m.name} · ${m.voice || 'Global voice'}`).join(', ')}
          </p>

          <h3 className="section-label">Personality &amp; World</h3>
          {field('personality')}
          {field('scenario')}

          <details className="editor-section">
            <summary>Advanced Prompts</summary>
            {field('systemPrompt')}
            {field('postHistoryInstructions')}
            <p className="muted small">Per-character, in this group only (optional)</p>
            {g.members.map((m) => (
              <div key={m.id} className="card">
                <strong>{m.name}</strong>
                <label>
                  Group-only system prompt (blank uses {m.name}&apos;s card)
                  <input value={m.prompt} onChange={(e) => setMember(m.id, { prompt: e.target.value })} />
                </label>
                <label>
                  Author&apos;s note (when {m.name} speaks)
                  <input value={m.note} onChange={(e) => setMember(m.id, { note: e.target.value })} />
                </label>
                <Slider
                  label={`Strength · ${m.strength}`}
                  min={1}
                  max={10}
                  value={m.strength}
                  onChange={(n) => setMember(m.id, { strength: n })}
                />
              </div>
            ))}
          </details>

          <h3 className="section-label">Tags</h3>
          <div className="tool-row">
            {g.tags.map((t) => (
              <button key={t} type="button" className="small" onClick={() => set({ tags: g.tags.filter((x) => x !== t) })}>
                {t} ✕
              </button>
            ))}
          </div>
          <input
            placeholder="Add a tag..."
            value={tagText}
            onChange={(e) => setTagText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && tagText.trim()) {
                const t = tagText.trim().toLowerCase();
                if (!g.tags.includes(t)) set({ tags: [...g.tags, t] });
                setTagText('');
              }
            }}
          />

          <h3 className="section-label">Realism Engine</h3>
          <p className="card muted small">These settings only affect new chats with this group.</p>
          <p className="muted small" data-testid="group-realism-intro">
            Each member&apos;s Realism, starting relationship and emotion, Needs, Afterglow and Pockets are in
            their card, exactly where a 1:1 character keeps them. The shared scene is set here:
          </p>
          <h4 className="realism-head">Time &amp; Day</h4>
          <div className="realism-grid-2">
            <SelectRow
              label="Time of Day"
              value={real.timeOfDay}
              options={TIME_OPTIONS.map((t) => ({ value: t, label: titleCase(t) }))}
              onChange={(s) => setReal({ timeOfDay: s })}
            />
            <label className="realism-field">
              <span>Day Number</span>
              <input
                type="number"
                min={1}
                value={real.dayCount}
                onChange={(e) => setReal({ dayCount: Math.max(1, parseInt(e.target.value, 10) || 1) })}
              />
            </label>
          </div>
          <div className="realism-grid-2">
            <label className="realism-field">
              <span>{real.storyStartDate ? `Story begins ${real.storyStartDate}` : 'Story begins: the day the chat starts'}</span>
              <input
                type="date"
                value={real.storyStartDate ?? ''}
                onChange={(e) => setReal({ storyStartDate: e.target.value || null })}
              />
            </label>
            <label className="realism-field">
              <span>{real.storyStartTime ? `Opens at ${real.storyStartTime}` : 'Opens at: time-of-day default'}</span>
              <input
                type="time"
                value={real.storyStartTime ?? ''}
                onChange={(e) => setReal({ storyStartTime: e.target.value || null })}
              />
            </label>
          </div>
          <ToggleRow
            label="Chaos Mode (Chance Time)"
            hint="Random narrative events during roleplay"
            value={g.chaosModeEnabled}
            onChange={(b) => set({ chaosModeEnabled: b })}
          />
          <ToggleRow
            label="Realism Verification (Director/Verifier)"
            hint="Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)"
            value={real.verificationEnabled}
            onChange={(b) => setReal({ verificationEnabled: b })}
          />
          {real.verificationEnabled && (
            <>
              <Slider
                label={`Max reprocess passes: ${real.verificationMaxReprocesses}`}
                min={1}
                max={5}
                value={real.verificationMaxReprocesses}
                onChange={(n) => setReal({ verificationMaxReprocesses: n })}
              />
              <Slider
                label={`Strictness (1=lenient … 5=strict): ${real.verificationStrictness}`}
                min={1}
                max={5}
                value={real.verificationStrictness}
                onChange={(n) => setReal({ verificationStrictness: n })}
              />
              <ToggleRow
                label="Director authority (needs)"
                hint="The director's corrections to Needs scores are the ones used."
                value={real.directorAuthority}
                onChange={(b) => setReal({ directorAuthority: b })}
              />
            </>
          )}
          {g.members.length > 1 && (
            <>
              <p>Starting feelings between members</p>
              {g.members.flatMap((from) =>
                g.members
                  .filter((to) => to.id !== from.id)
                  .map((to) => (
                    <Slider
                      key={`${from.id}-${to.id}`}
                      label={`${from.name} toward ${to.name} · ${feelingWord(feeling(from.id, to.id))}`}
                      min={-300}
                      max={300}
                      value={feeling(from.id, to.id)}
                      onChange={(n) => setFeeling(from.id, to.id, n)}
                    />
                  )),
              )}
            </>
          )}

          <CharacterStatsCard
            characterId={g.id}
            url={`/api/groups/${g.id}/stats`}
            note="From this group's chats."
          />
        </>
      )}

      {tab === 'Dialogue' && (
        <>
          <h3 className="section-label">First Message</h3>
          {field('firstMessage')}
          <h3 className="section-label">Alternate Greetings</h3>
          <AltGreetingsEditor
            greetings={alts}
            onChange={setAlts}
            seeds={seeds}
            showNeeds
            clockOn={clockOn}
            onSeedsChange={setSeeds}
          />
          <h3 className="section-label">Example Dialogue</h3>
          {field('mesExample')}
        </>
      )}

      {tab === 'Lorebook' && (
        <>
          <h3 className="section-label">Lorebook</h3>
          <LoreEntriesEditor entries={lore} onChange={setLore} />
          <ToggleRow
            label="Inherit character & world lorebooks"
            hint="When on, member cards and their attached worlds contribute lore in addition to the group lorebook above."
            value={g.inheritCharacterLorebooks}
            onChange={(b) => set({ inheritCharacterLorebooks: b })}
          />
        </>
      )}

      {tab === 'Worlds' && (
        <CharacterWorldsSection
          name={g.name}
          forGroup
          value={worldChoice}
          onChange={setWorldChoice}
          worlds={allWorlds}
        />
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
