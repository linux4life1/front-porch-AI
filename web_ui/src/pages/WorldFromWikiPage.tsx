// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from wiki — web twin of the desktop studio wizard. Scout proposes a
// shelf; write runs on the Dart host; save is POST /api/worlds.

import { useCallback, useEffect, useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import { StepIndicator } from '../components/StepIndicator';
import type { LoreEntry } from '../components/LoreEntriesEditor';
import {
  WORLD_FROM_WIKI_STEPS,
  canOpenWorldFromWikiPreview,
  catalogCountCopy,
  emptyScoutCopy,
  jumpWorldFromWikiStep,
  parseProposedCards,
  parseProposedPlaces,
  parseWorldToolsGate,
  scoutPartsNote,
  worldToolsAllowNext,
  shelfReviewNote,
  signedCards,
  worldToolsCanRetest,
  pushWorldProgress,
  worldElapsedLabel,
  worldScoutStageOf,
  worldWriteStageOf,
  WORLD_SCOUT_STAGES,
  WORLD_WRITE_STAGES,
  depthTimeHint,
  worldToolsCopy,
  type ProposedWorldCard,
  type ProposedWorldPlace,
  type WorldProgressLine,
  applyWorldReview,
  mergeWorldEntryNotes,
  parseWorldEntryNotes,
  worldReviewEntries,
  worldReviewFindings,
  type WorldEntryNote,
  type WorldReviewPlace,
  type WorldReviewResult,
  type WorldReviewRoot,
  WORLD_CHARACTER_SCOUT_STAGES,
  characterDepthValue,
  defaultModeFor,
  modeOptions,
  parseChatSourceRows,
  wizardSourceTitle,
  worldCharacterScoutStageOf,
  worldSourceBody,
  type ChatSourceRow,
  type WorldBuildMode,
  type WorldWizardSource,
} from './worldFromWiki';
import type { CharacterRow } from './story/setup/draft';
import { loadCharacters } from './story/setup/useSetupData';
import { WorldProgressPanel } from './WorldProgressPanel';
import { WorldBookStep } from './WorldBookStep';
import { WorldReviewStep } from './WorldReviewStep';
import {
  startingPlacePayload,
  startingPlaceProblem,
  WorldStartingPlaceField,
  type StartingPlaceDraft,
} from '../components/WorldStartingPlaceField';
import { WorldShelfStep } from './WorldShelfStep';

type Status = {
  available: boolean;
  toolsAdvertised: boolean;
  toolsGate?: string;
  savedWikis: string[];
  /** The wizard's own context pick; 0 = same as chat. Older servers omit it. */
  contextSize?: number;
  chatContextSize?: number;
  contextChoices?: number[];
  /** 0 quick, 1 full, 2 deep; older servers omit it. */
  depth?: number;
  depthChoices?: unknown;
  /** World from Character (additive): which sources the host builds from,
   * the mode tiles, and the depth tiles a chat offers. */
  sources?: string[];
  modes?: unknown;
  characterDepthChoices?: unknown;
};

/** How often the Setup step asks again while the tool check is not done. */
const TOOLS_POLL_MS = 3000;

/**
 * The wizard, from a wiki or (route `/worlds/from-character`) from a
 * character and one of their chats. Same steps either way; only the Book
 * step's second card and the words change (design §5).
 */
export function WorldFromWikiPage({ source = 'wiki' }: { source?: WorldWizardSource } = {}) {
  const navigate = useNavigate();
  const character = source === 'character';
  const [step, setStep] = useState(0);
  const [status, setStatus] = useState<Status | null>(null);
  // World from Character: the library and its 1:1 chats, the pick, how
  // far the writer may go, and the root's provenance from the done event.
  const [characters, setCharacters] = useState<CharacterRow[] | null>(null);
  const [chatRows, setChatRows] = useState<ChatSourceRow[]>([]);
  const [characterId, setCharacterId] = useState('');
  const [sessionId, setSessionIdRaw] = useState('');
  const [mode, setMode] = useState<WorldBuildMode>(defaultModeFor(false));
  const [copyCardLore, setCopyCardLore] = useState(false);
  const [provenance, setProvenance] = useState<Record<string, unknown>>({});
  const setSessionId = (id: string) => {
    setSessionIdRaw(id);
    setMode(defaultModeFor(!!id));
  };
  useEffect(() => {
    if (!character) return;
    loadCharacters()
      .then(setCharacters)
      .catch(() => setCharacters([]));
    api
      .get<unknown>('/api/stories/chat-sources')
      .then((r) => setChatRows(parseChatSourceRows(r)))
      .catch(() => setChatRows([]));
  }, [character]);
  const [name, setName] = useState('');
  const [premise, setPremise] = useState('');
  const [moment, setMoment] = useState('');
  const [wikiUrl, setWikiUrl] = useState('');
  const [climateEnabled, setClimateEnabled] = useState(false);
  const [biome, setBiome] = useState<Record<string, unknown> | null>(null);
  const [lorebooksOn, setLorebooksOn] = useState(true);
  const [proposed, setProposed] = useState<ProposedWorldCard[]>([]);
  // Slice 8: scout places (empty on an untagged wiki = flat, as ever),
  // the per-place "own weather" switches, and the written tree from
  // the done event (root book + children) that turns Save into a ladder.
  const [places, setPlaces] = useState<ProposedWorldPlace[]>([]);
  const [placeClimate, setPlaceClimate] = useState<Set<string>>(new Set());
  const [treeRoot, setTreeRoot] = useState<{
    description: string;
    entries: LoreEntry[];
    biome?: Record<string, unknown>;
  } | null>(null);
  // Where chats in the minted world start (desktop parity): a written
  // place by name, '' for a new place named here, null for none yet.
  const [startPick, setStartPick] = useState<StartingPlaceDraft>({
    startingPlaceId: null,
    startingPlaceName: '',
    startingPlaceDescription: '',
  });
  const [treePlaces, setTreePlaces] = useState<
    {
      name: string;
      parentName: string;
      description: string;
      entries: LoreEntry[];
      biome?: Record<string, unknown>;
    }[]
  >([]);
  const [signed, setSigned] = useState<Set<number>>(new Set());
  const [titleCount, setTitleCount] = useState(0);
  const [partsNote, setPartsNote] = useState('');
  const [catalogCopy, setCatalogCopy] = useState('');
  const [reviewNote, setReviewNote] = useState('');
  const [busy, setBusy] = useState(false);
  // What the host is doing now, the lines before it, and when the run began.
  const [liveStatus, setLiveStatus] = useState('');
  const [liveLog, setLiveLog] = useState<WorldProgressLine[]>([]);
  const [liveSince, setLiveSince] = useState<number | null>(null);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [stepMs, setStepMs] = useState(0);
  const liveSinceRef = useRef<number | null>(null);
  const stepSinceRef = useRef<number | null>(null);
  // The Review step: the reviewers' notes by entry, pinned cards, the
  // direction note and its scope, and the last action's one-line result.
  const [notes, setNotes] = useState<Record<string, WorldEntryNote>>({});
  const [pinned, setPinned] = useState<Set<string>>(new Set());
  const [direction, setDirection] = useState('');
  const [wholeWorld, setWholeWorld] = useState(false);
  const [reviewStatus, setReviewStatus] = useState('');
  const treeRef = useRef<{ root: WorldReviewRoot | null; places: WorldReviewPlace[] }>({ root: null, places: [] });
  const startRun = (first: string) => {
    const now = Date.now();
    liveSinceRef.current = now;
    stepSinceRef.current = now;
    setLiveSince(now);
    setElapsedMs(0);
    setStepMs(0);
    setLiveStatus(first);
    setLiveLog(pushWorldProgress([], first, 0));
  };
  const endRun = () => {
    liveSinceRef.current = null;
    setLiveSince(null);
  };
  useEffect(() => {
    if (liveSince == null) return;
    const tick = window.setInterval(() => {
      setElapsedMs(Date.now() - liveSince);
      const since = stepSinceRef.current;
      setStepMs(since == null ? 0 : Date.now() - since);
    }, 1000);
    return () => window.clearInterval(tick);
  }, [liveSince]);
  const [error, setError] = useState('');
  const [entries, setEntries] = useState<LoreEntry[]>([]);
  const [aborted, setAborted] = useState(false);
  const [description, setDescription] = useState('');
  const [bookFields, setBookFields] = useState({
    recursiveScanning: true,
    scanDepth: 10,
    tokenBudget: 2800,
  });

  const loadStatus = useCallback(
    () =>
      api
        .get<Status>('/api/worlds/from-wiki/status')
        .then((r) => {
          setStatus(r);
          setWikiUrl((cur) => cur || r.savedWikis[0] || '');
        })
        .catch(() =>
          setStatus({ available: false, toolsAdvertised: false, savedWikis: [] }),
        ),
    [],
  );

  useEffect(() => {
    void loadStatus();
  }, [loadStatus]);

  const toolsGate = parseWorldToolsGate(status?.toolsGate, status?.toolsAdvertised);
  const toolsOk = toolsGate === 'ready';
  // An unchecked model is asked by Next (the relay's scout), never by the
  // page: on oMLX or LM Studio a check is a model load.
  const nextOk = worldToolsAllowNext(toolsGate);

  // A check is running on the host (Next or Check now); follow it until it lands.
  useEffect(() => {
    if (step !== 0 || toolsGate !== 'checking' || status == null) return;
    const id = window.setTimeout(() => void loadStatus(), TOOLS_POLL_MS);
    return () => window.clearTimeout(id);
  }, [step, toolsGate, status, loadStatus]);

  const [retesting, setRetesting] = useState(false);
  const retestTools = async () => {
    setRetesting(true);
    try {
      await api.post('/api/worlds/from-wiki/tool-test');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not check the model');
    } finally {
      setRetesting(false);
      void loadStatus();
    }
  };

  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'world_wiki_status' && e.data) {
        const line = e.data;
        const since = liveSinceRef.current;
        stepSinceRef.current = Date.now();
        setStepMs(0);
        setLiveStatus(line);
        setLiveLog((log) => pushWorldProgress(log, line, since == null ? 0 : Date.now() - since));
      } else if (e.event === 'world_wiki_done') {
        setBusy(false);
        endRun();
        if (typeof e.description === 'string' && e.description) {
          setDescription(e.description);
        }
        setClimateEnabled(e.climateEnabled === true);
        if (e.biome && typeof e.biome === 'object') {
          setBiome(e.biome as Record<string, unknown>);
        } else {
          setBiome(null);
        }
        setEntries(Array.isArray(e.entries) ? (e.entries as LoreEntry[]) : []);
        // Slice 8: the tree payload (root book + children). Absent or
        // empty → flat save, exactly as today.
        setTreeRoot(
          e.root && typeof e.root === 'object'
            ? (e.root as {
                description: string;
                entries: LoreEntry[];
                biome?: Record<string, unknown>;
              })
            : null,
        );
        setTreePlaces(
          Array.isArray(e.places)
            ? (e.places as {
                name: string;
                parentName: string;
                description: string;
                entries: LoreEntry[];
                biome?: Record<string, unknown>;
              }[])
            : [],
        );
        setNotes(parseWorldEntryNotes((e as unknown as { notes?: unknown }).notes));
        {
          const raw = e as unknown as { sourceId?: unknown; placeTraits?: unknown };
          setProvenance({
            ...(typeof raw.sourceId === 'string' ? { sourceId: raw.sourceId } : {}),
            ...(raw.placeTraits && typeof raw.placeTraits === 'object' ? { placeTraits: raw.placeTraits } : {}),
          });
        }
        setPinned(new Set());
        setReviewStatus('');
        setBookFields({
          recursiveScanning: e.recursiveScanning !== false,
          scanDepth: typeof e.scanDepth === 'number' ? e.scanDepth : 10,
          tokenBudget: typeof e.tokenBudget === 'number' ? e.tokenBudget : 2800,
        });
        setAborted(false);
        setStep(3);
      } else if (e.event === 'world_wiki_abort') {
        setBusy(false);
        endRun();
        setAborted(true);
        setEntries([]);
        setLiveStatus(e.data || 'Stopped.');
      } else if (e.event === 'world_wiki_review_done') {
        setBusy(false);
        endRun();
        const result = e as unknown as WorldReviewResult & { status?: string };
        const next = applyWorldReview(treeRef.current.root, treeRef.current.places, result);
        setTreeRoot(next.root);
        setTreePlaces(next.places);
        setEntries(worldReviewEntries(next.root, next.places));
        setNotes((n) => mergeWorldEntryNotes(n, result));
        if (typeof result.status === 'string') setReviewStatus(result.status);
      } else if (e.event === 'world_wiki_error') {
        setBusy(false);
        endRun();
        setError(e.error || 'Write failed');
      }
    });
    socket.connect();
    return () => socket.close();
  }, []);

  const setContext = async (pick: { contextSize?: number; depth?: number }) => {
    try {
      const r = await api.post<Status>('/api/worlds/from-wiki/context', pick);
      setStatus((cur) => ({
        ...(cur ?? { available: false, toolsAdvertised: false, savedWikis: [] }),
        ...r,
      }));
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save the context pick');
    }
  };

  const scout = async () => {
    if (!lorebooksOn) {
      setStep(3);
      return;
    }
    if (character && !characterId) {
      setError('Pick a character first.');
      return;
    }
    setBusy(true);
    setError('');
    startRun(
      !character ? 'Rummaging through the wiki…' : sessionId ? 'Skimming the chat…' : 'Reading the card…',
    );
    try {
      const r = await api.post<{
        proposed?: unknown;
        titles?: number;
        places?: unknown;
        failure?: unknown;
        parts?: unknown;
        partsCut?: unknown;
        articles?: unknown;
        ranked?: unknown;
        revised?: unknown;
        auditNotes?: unknown;
      }>('/api/worlds/from-wiki/scout', {
        wikiUrl,
        name,
        premise,
        moment,
        ...worldSourceBody({ source, characterId, sessionId, mode, copyCardLore }),
      });
      const cards = parseProposedCards(r.proposed);
      setProposed(cards);
      const rPlaces = parseProposedPlaces(r.places);
      setPlaces(rPlaces);
      setPlaceClimate(
        new Set(
          rPlaces.filter((p) => p.climateHint).map((p) => p.name.toLowerCase()),
        ),
      );
      setTreePlaces([]);
      // Every proposed card starts signed: the Review step at the end is
      // where the user fixes what the write got wrong, so the shelf is a
      // trim, not a chore (the maintainer's ruling, 2026-10-24).
      setSigned(new Set(cards.map((_, i) => i)));
      setTitleCount(typeof r.titles === 'number' ? r.titles : 0);
      setPartsNote(scoutPartsNote(r.parts, r.partsCut));
      setCatalogCopy(catalogCountCopy(r.titles, r.articles, r.ranked));
      setReviewNote(shelfReviewNote(r.revised, r.auditNotes));
      if (!cards.length) {
        setError(emptyScoutCopy(r.failure));
        return;
      }
      setStep(1);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Scout failed');
    } finally {
      setBusy(false);
      endRun();
    }
  };

  const write = async () => {
    const picked = signedCards(proposed, signed);
    if (!picked.length) {
      setError('Sign at least one card.');
      return;
    }
    setBusy(true);
    setAborted(false);
    setError('');
    startRun('Writing…');
    setStep(2);
    try {
      await api.post('/api/worlds/from-wiki/write', {
        wikiUrl,
        cards: picked.map((c) => ({ ...c, signed: true })),
        name,
        premise,
        moment,
        climateEnabled,
        // Slice 8 (additive): an older server ignores both and writes
        // one flat world; a newer one groups the write by place.
        places,
        placeClimate: [...placeClimate],
        ...worldSourceBody({ source, characterId, sessionId, mode, copyCardLore }),
      });
    } catch (e) {
      setBusy(false);
      endRun();
      setError(e instanceof ApiError ? e.message : 'Could not start write');
    }
  };

  const abortWrite = async () => {
    try {
      await api.post('/api/worlds/from-wiki/abort');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not stop');
    }
  };

  useEffect(() => {
    treeRef.current = { root: treeRoot, places: treePlaces };
  }, [treeRoot, treePlaces]);

  /** A hand change to the tree the Review step shows; entries follow it. */
  const applyLocal = (result: WorldReviewResult) => {
    const next = applyWorldReview(treeRef.current.root, treeRef.current.places, result);
    treeRef.current = next;
    setTreeRoot(next.root);
    setTreePlaces(next.places);
    setEntries(worldReviewEntries(next.root, next.places));
  };
  const reviewEntryNamed = (name: string) =>
    worldReviewEntries(treeRef.current.root, treeRef.current.places).find(
      (x) => x.name.trim().toLowerCase() === name.trim().toLowerCase(),
    );
  const editEntry = (name: string, patch: { content?: string; key?: string }) => {
    const cur = reviewEntryNamed(name);
    if (!cur) return;
    applyLocal({ updated: [{ name, place: '', entry: { ...cur, ...patch } }] });
  };
  const dropEntry = (name: string) => {
    applyLocal({ dropped: [name] });
    setPinned((s) => {
      const n = new Set(s);
      n.delete(name.trim().toLowerCase());
      return n;
    });
  };
  const togglePin = (name: string) =>
    setPinned((s) => {
      const n = new Set(s);
      const k = name.trim().toLowerCase();
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  /** A Review action on the host; its result lands as world_wiki_review_done. */
  const reviewPost = async (path: string, first: string, body: Record<string, unknown>) => {
    setBusy(true);
    setError('');
    setReviewStatus('');
    startRun(first);
    try {
      await api.post(`/api/worlds/from-wiki/review/${path}`, body);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setBusy(false);
      endRun();
    }
  };
  const currentTexts = (names?: string[]) =>
    worldReviewEntries(treeRef.current.root, treeRef.current.places)
      .filter((x) => !names || names.includes(x.name))
      .map((x) => ({ name: x.name, content: x.content, keys: x.key }));
  const rewriteEntry = (name: string, note: string) =>
    void reviewPost('rewrite', `Rewriting ${name}…`, { name, note, entries: currentTexts([name]) });
  const sendBack = () =>
    void reviewPost('direction', 'Reading your note…', {
      note: direction,
      wholeWorld,
      pinned: [...pinned],
      entries: currentTexts(),
    });
  const addCard = (place: string, cardName: string, page: string) =>
    void reviewPost('add', `Writing ${cardName}…`, { name: cardName, place, page });

  // The pick only counts while it still names a written place (a dropped
  // place un-picks it), or '' for a new one.
  const shownStartPick = (): string | null => {
    const id = startPick.startingPlaceId;
    if (id === '' || id == null) return id;
    return treePlaces.some((p) => p.name === id) ? id : null;
  };
  const startingPlaceProblemNow = (): string | null =>
    startingPlaceProblem(
      { ...startPick, startingPlaceId: shownStartPick() },
      { isNew: treePlaces.length === 0, hasPlaces: treePlaces.length > 0 },
    );

  const save = async () => {
    if (!canOpenWorldFromWikiPreview({ lorebooksOn, aborted, entryCount: entries.length })) {
      setError('Write a signed shelf first.');
      return;
    }
    const startProblem = startingPlaceProblemNow();
    if (startProblem) {
      setError(startProblem);
      return;
    }
    const climateOn = climateEnabled && biome != null;
    setBusy(true);
    setError('');
    let ladderStep = '';
    const known = new Set<string>();
    try {
      if (treePlaces.length && !treeRoot) {
        // A tree write whose root book went missing must not silently
        // flat-save (review #608): the ladder would half-exist with a
        // fat root and the author would never know.
        setError('The written places lost their root book. Stop and Write again.');
        return;
      }
      if (!treePlaces.length || !treeRoot) {
        await api.post('/api/worlds', {
          name,
          create: true,
          description: description || premise,
          climateEnabled: climateOn,
          injectDescription: true,
          entries,
          recursiveScanning: bookFields.recursiveScanning,
          scanDepth: bookFields.scanDepth,
          tokenBudget: bookFields.tokenBudget,
          ...(climateOn ? { biomeId: 'custom', biome } : {}),
          ...provenance,
          startingPlace: startingPlacePayload({ ...startPick, startingPlaceId: null }),
        });
        navigate('/worlds');
        return;
      }
      // Slice 8 ladder: root first, then each place at its parent's id.
      // The save response echoes the whole shelf, so a created row is
      // found by what was NOT there before — exact even when the unique
      // name law appended " (2)" (desktop's saveWorld does the same).
      const shelf = await api.get<{ worlds?: { id: string }[] }>('/api/worlds');
      for (const w of shelf.worlds ?? []) known.add(w.id);
      const create = async (payload: Record<string, unknown>): Promise<string> => {
        const r = await api.post<{ worlds?: { id: string; name: string }[] }>(
          '/api/worlds',
          payload,
        );
        const fresh = (r.worlds ?? []).filter((w) => !known.has(w.id));
        const created = fresh[0];
        if (!created) throw new Error('the library did not confirm the save');
        known.add(created.id);
        return created.id;
      };
      ladderStep = `the world ${name}`;
      const rootId = await create({
        name,
        create: true,
        description: description || treeRoot.description || premise,
        climateEnabled: climateOn,
        injectDescription: true,
        entries: treeRoot.entries,
        recursiveScanning: bookFields.recursiveScanning,
        scanDepth: bookFields.scanDepth,
        tokenBudget: bookFields.tokenBudget,
        ...(climateOn ? { biomeId: 'custom', biome } : {}),
        ...provenance,
      });
      const ids = new Map<string, string>();
      for (const p of treePlaces) {
        const parentId = ids.get(p.parentName.toLowerCase()) ?? rootId;
        ladderStep = `the place ${p.name}`;
        const createdId = await create({
          name: p.name,
          create: true,
          description: p.description,
          injectDescription: true,
          parentWorldId: parentId,
          entries: p.entries,
          recursiveScanning: bookFields.recursiveScanning,
          scanDepth: bookFields.scanDepth,
          tokenBudget: bookFields.tokenBudget,
          ...(p.biome
            ? { climateEnabled: true, biomeId: 'custom', biome: p.biome }
            : { climateEnabled: false }),
        });
        ids.set(p.name.toLowerCase(), createdId);
      }
      // Where chats start: a written place by its new id, or a new place
      // made inside the root, then starred on the root.
      ladderStep = 'where chats start';
      const picked = shownStartPick();
      const startId = picked
        ? ids.get(picked.toLowerCase())
        : await create({
          name: startPick.startingPlaceName.trim(),
          create: true,
          description: startPick.startingPlaceDescription.trim(),
          injectDescription: true,
          parentWorldId: rootId,
          climateEnabled: false,
          entries: [],
        });
      if (!startId) throw new Error('the starting place was not saved');
      await api.post('/api/worlds/default-place', { worldId: rootId, placeId: startId });
      navigate('/worlds');
    } catch (e) {
      const why = e instanceof ApiError ? e.message : String(e);
      // A ladder can fail halfway (a law refuses one place). Say what
      // landed and what did not — half a tree must not look like none.
      setError(
        ladderStep && known.size > 0 && treePlaces.length
          ? `Saved part of the ladder; failed on ${ladderStep}: ${why}. `
            + 'The rest is in your library.'
          : `Save failed: ${why}`,
      );
    } finally {
      setBusy(false);
      endRun();
    }
  };

  const toolsCopy = worldToolsCopy(toolsGate);
  const available = status?.available !== false;

  return (
    <div className="page wizard">
      <header className="page-head">
        <button className="ghost" onClick={() => navigate('/worlds')}>← Places</button>
        <h2>{character ? '🎭 ' : '📖 '}{wizardSourceTitle(source)}</h2>
      </header>

      <StepIndicator
        steps={WORLD_FROM_WIKI_STEPS}
        current={step}
        onJump={busy ? undefined : (i) => setStep(jumpWorldFromWikiStep(i, step, {
          lorebooksOn,
          aborted,
          entryCount: entries.length,
          proposedCount: proposed.length,
          signedCount: signed.size,
        }))}
      />

      {!available && (
        <p className="muted">No LLM backend is ready — start or connect a model first.</p>
      )}
      {status != null && toolsCopy && (
        <div className="muted" data-testid="world-from-wiki-tools-copy">
          <p>{toolsCopy}</p>
          {worldToolsCanRetest(toolsGate) && (
            <button
              type="button"
              data-testid="world-from-wiki-tools-retest"
              disabled={retesting}
              onClick={() => void retestTools()}
            >
              {retesting ? 'Checking…' : 'Check now'}
            </button>
          )}
        </div>
      )}

      <div className="wizard-body">
        {step === 0 && (
          <div className="cg-config">
            {busy && (
              <WorldProgressPanel
                status={liveStatus}
                fallback={character && sessionId ? 'Skimming…' : 'Scouting…'}
                elapsed={worldElapsedLabel(elapsedMs)}
                stepMs={stepMs}
                subtitle={
                  character
                    ? 'Skim · one pass per 50 messages · then the scout reads the index, not the chat'
                    : 'Scout · reading the index, not the articles · the model is thinking'
                }
                stages={character ? WORLD_CHARACTER_SCOUT_STAGES : WORLD_SCOUT_STAGES}
                stage={character ? worldCharacterScoutStageOf(liveStatus) : worldScoutStageOf(liveStatus)}
                onStop={() => void abortWrite()}
              />
            )}
            <WorldBookStep
              source={source}
              characters={characters}
              chatRows={chatRows}
              characterId={characterId}
              setCharacterId={setCharacterId}
              sessionId={sessionId}
              setSessionId={setSessionId}
              mode={mode}
              setMode={setMode}
              modes={modeOptions(status?.modes)}
              copyCardLore={copyCardLore}
              setCopyCardLore={setCopyCardLore}
              characterDepthChoices={status?.characterDepthChoices}
              name={name}
              setName={setName}
              premise={premise}
              setPremise={setPremise}
              moment={moment}
              setMoment={setMoment}
              savedWikis={status?.savedWikis ?? []}
              wikiUrl={wikiUrl}
              setWikiUrl={setWikiUrl}
              titleCount={titleCount}
              ranked={catalogCopy.includes('links to most')}
              contextSize={status?.contextSize ?? 0}
              chatContextSize={status?.chatContextSize}
              contextChoices={status?.contextChoices}
              depth={character ? characterDepthValue(status?.depth ?? 1) : (status?.depth ?? 1)}
              depthChoices={status?.depthChoices}
              onContext={(pick) => void setContext(pick)}
              lorebooksOn={lorebooksOn}
              setLorebooksOn={setLorebooksOn}
              climateEnabled={climateEnabled}
              setClimateEnabled={setClimateEnabled}
              busy={busy}
            />
          </div>
        )}

        {step === 1 && (
          <WorldShelfStep
            proposed={proposed}
            places={places}
            signed={signed}
            setSigned={setSigned}
            climateEnabled={climateEnabled}
            placeClimate={placeClimate}
            setPlaceClimate={setPlaceClimate}
            reviewLine={[
              reviewNote
                ? `${reviewNote[0].toUpperCase()}${reviewNote.slice(1)}.`
                : proposed.length
                  ? 'The reviewer passed this shelf first time.'
                  : '',
              titleCount > 0 ? `${titleCount} pages read${catalogCopy.includes('links to most') ? ', the ones this wiki links to most' : ''}.` : '',
              partsNote ? `Index ${partsNote}.` : '',
            ]
              .filter(Boolean)
              .join(' ')}
            revised={reviewNote.includes('revised')}
          />
        )}

        {step === 2 && (
          <div className="cg-config">
            <WorldProgressPanel
              status={liveStatus}
              fallback="Writing lorebook cards…"
              elapsed={worldElapsedLabel(elapsedMs)}
              stepMs={stepMs}
              subtitle="Write · each book written and reviewed, three at a time on a remote model"
              stages={WORLD_WRITE_STAGES}
              stage={worldWriteStageOf(liveStatus)}
              onStop={() => void abortWrite()}
            />
            <p className="muted small">Nothing is saved until Preview.</p>
            <button type="button" disabled={!busy} onClick={() => void abortWrite()}>
              Stop
            </button>
          </div>
        )}

        {step === 3 && (
          <div className="cg-config">
            <label className="cg-field">
              <span className="cg-field-label">Name</span>
              <input value={name} onChange={(e) => setName(e.target.value)} />
            </label>
            <label className="cg-field">
              <span className="cg-field-label">Description</span>
              <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4} />
            </label>
            <WorldStartingPlaceField
              draft={{ ...startPick, startingPlaceId: shownStartPick() }}
              places={treePlaces.map((p) => ({
                id: p.name,
                label: p.parentName ? `${p.name} · inside ${p.parentName}` : p.name,
              }))}
              isNew={treePlaces.length === 0}
              error={startingPlaceProblemNow()}
              onChange={(next) => setStartPick({ ...startPick, ...next })}
            />
            <label className="cg-field cg-toggle">
              <input
                type="checkbox"
                checked={climateEnabled}
                onChange={(e) => setClimateEnabled(e.target.checked)}
              />
              <span>Climate</span>
            </label>
            <WorldReviewStep
              worldName={name}
              root={treeRoot}
              places={treePlaces}
              climateEnabled={climateEnabled}
              notes={notes}
              pinned={pinned}
              busy={busy}
              findings={worldReviewFindings(reviewNote, notes)}
              direction={direction}
              setDirection={setDirection}
              wholeWorld={wholeWorld}
              setWholeWorld={setWholeWorld}
              reviewStatus={reviewStatus}
              onSendBack={sendBack}
              onEdit={editEntry}
              onDrop={dropEntry}
              onPin={togglePin}
              onRewrite={rewriteEntry}
              onAdd={addCard}
              progress={{ status: liveStatus, log: liveLog, elapsed: worldElapsedLabel(elapsedMs), stepMs }}
            />
          </div>
        )}
        {error && <p className="error">{error}</p>}
      </div>

      <div className="wizard-nav">
        <button disabled={step === 0 || busy} onClick={() => setStep(step - 1)}>← Back</button>
        {step === 0 && (
          <span className="wfw-nav-next">
            <button
              className="primary"
              disabled={busy || !nextOk || (character ? !characterId : !wikiUrl)}
              onClick={() => void scout()}
            >
              {busy
                ? character && sessionId ? 'Skimming…' : 'Scouting…'
                : !lorebooksOn
                  ? 'Next: Review'
                  : character
                    ? sessionId ? 'Skim chat →' : 'Scout card →'
                    : 'Scout wiki →'}
            </button>
            {lorebooksOn && !busy && (
              <span className="muted small" data-testid="world-from-wiki-nav-hint">
                {character
                  ? sessionId
                    ? 'one pass per 50 messages, then the scout'
                    : 'the card goes straight onto the index, then the scout'
                  : `${depthTimeHint(status?.depth ?? 1).replace('About ', 'about ')}, with every step shown`}
              </span>
            )}
          </span>
        )}
        {step === 1 && (
          <span className="wfw-nav-next">
            <button className="primary" disabled={busy || !toolsOk || signed.size === 0} onClick={() => void write()}>
              Write {signed.size} cards →
            </button>
            <span className="muted small">a few minutes per book on a remote model</span>
          </span>
        )}
        {step === 2 && (
          <button disabled={!busy} onClick={() => void abortWrite()}>Stop</button>
        )}
        {step === 3 && (
          <button
            data-testid="world-from-wiki-send-back-nav"
            disabled={busy || !direction.trim()}
            onClick={sendBack}
          >
            Send it back around
          </button>
        )}
        {step === 3 && (
          <button
            className="primary"
            data-testid="world-from-wiki-mint"
            disabled={busy || !name.trim() || startingPlaceProblemNow() != null || !canOpenWorldFromWikiPreview({
              lorebooksOn,
              aborted,
              entryCount: entries.length,
            })}
            onClick={() => void save()}
          >
            Mint World →
          </button>
        )}
      </div>
    </div>
  );
}
