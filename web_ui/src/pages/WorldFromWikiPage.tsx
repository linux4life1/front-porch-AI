// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from wiki — web twin of the desktop studio wizard. Scout proposes a
// shelf; write runs on the Dart host; save is POST /api/worlds.

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import { StepIndicator } from '../components/StepIndicator';
import type { LoreEntry } from '../components/LoreEntriesEditor';
import {
  WORLD_FROM_WIKI_STEPS,
  WORLD_FROM_WIKI_TOOLS_COPY,
  canOpenWorldFromWikiPreview,
  jumpWorldFromWikiStep,
  parseProposedCards,
  signedCards,
  type ProposedWorldCard,
} from './worldFromWiki';

type Status = {
  available: boolean;
  toolsAdvertised: boolean;
  savedWikis: string[];
};

export function WorldFromWikiPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [status, setStatus] = useState<Status | null>(null);
  const [name, setName] = useState('');
  const [premise, setPremise] = useState('');
  const [wikiUrl, setWikiUrl] = useState('');
  const [climateEnabled, setClimateEnabled] = useState(false);
  const [biome, setBiome] = useState<Record<string, unknown> | null>(null);
  const [lorebooksOn, setLorebooksOn] = useState(true);
  const [proposed, setProposed] = useState<ProposedWorldCard[]>([]);
  const [signed, setSigned] = useState<Set<number>>(new Set());
  const [titleCount, setTitleCount] = useState(0);
  const [busy, setBusy] = useState(false);
  const [writeStatus, setWriteStatus] = useState('');
  const [error, setError] = useState('');
  const [entries, setEntries] = useState<LoreEntry[]>([]);
  const [aborted, setAborted] = useState(false);
  const [description, setDescription] = useState('');
  const [bookFields, setBookFields] = useState({
    recursiveScanning: true,
    scanDepth: 10,
    tokenBudget: 2800,
  });

  useEffect(() => {
    api
      .get<Status>('/api/worlds/from-wiki/status')
      .then((r) => {
        setStatus(r);
        setWikiUrl((cur) => cur || r.savedWikis[0] || '');
      })
      .catch(() =>
        setStatus({ available: false, toolsAdvertised: false, savedWikis: [] }),
      );
  }, []);

  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'world_wiki_status' && e.data) {
        setWriteStatus(e.data);
      } else if (e.event === 'world_wiki_done') {
        setBusy(false);
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
        setBookFields({
          recursiveScanning: e.recursiveScanning !== false,
          scanDepth: typeof e.scanDepth === 'number' ? e.scanDepth : 10,
          tokenBudget: typeof e.tokenBudget === 'number' ? e.tokenBudget : 2800,
        });
        setAborted(false);
        setStep(3);
      } else if (e.event === 'world_wiki_abort') {
        setBusy(false);
        setAborted(true);
        setEntries([]);
        setWriteStatus(e.data || 'Stopped.');
      } else if (e.event === 'world_wiki_error') {
        setBusy(false);
        setError(e.error || 'Write failed');
      }
    });
    socket.connect();
    return () => socket.close();
  }, []);

  const scout = async () => {
    if (!lorebooksOn) {
      setStep(3);
      return;
    }
    setBusy(true);
    setError('');
    try {
      const r = await api.post<{
        proposed?: unknown;
        titles?: number;
      }>('/api/worlds/from-wiki/scout', { wikiUrl, name, premise });
      const cards = parseProposedCards(r.proposed);
      setProposed(cards);
      setSigned(new Set());
      setTitleCount(typeof r.titles === 'number' ? r.titles : 0);
      if (!cards.length) {
        setError('The scout returned no cards. Try a clearer premise, or another wiki.');
        return;
      }
      setStep(1);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Scout failed');
    } finally {
      setBusy(false);
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
    setWriteStatus('Writing…');
    setStep(2);
    try {
      await api.post('/api/worlds/from-wiki/write', {
        wikiUrl,
        cards: picked.map((c) => ({ ...c, signed: true })),
        name,
        premise,
        climateEnabled,
      });
    } catch (e) {
      setBusy(false);
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

  const save = async () => {
    if (!canOpenWorldFromWikiPreview({ lorebooksOn, aborted, entryCount: entries.length })) {
      setError('Write a signed shelf first.');
      return;
    }
    const climateOn = climateEnabled && biome != null;
    setBusy(true);
    setError('');
    try {
      await api.post('/api/worlds', {
        name,
        description: description || premise,
        climateEnabled: climateOn,
        injectDescription: true,
        entries,
        recursiveScanning: bookFields.recursiveScanning,
        scanDepth: bookFields.scanDepth,
        tokenBudget: bookFields.tokenBudget,
        ...(climateOn ? { biomeId: 'custom', biome } : {}),
      });
      navigate('/worlds');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Save failed');
    } finally {
      setBusy(false);
    }
  };

  const toolsOk = status?.toolsAdvertised === true;
  const available = status?.available !== false;

  return (
    <div className="page wizard">
      <header className="page-head">
        <button className="ghost" onClick={() => navigate('/worlds')}>← Places</button>
        <h2>📖 World from Wiki</h2>
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
      {!toolsOk && (
        <p className="muted" data-testid="world-from-wiki-tools-copy">{WORLD_FROM_WIKI_TOOLS_COPY}</p>
      )}

      <div className="wizard-body">
        {step === 0 && (
          <div className="cg-config">
            <p className="muted small">
              Name the place, pick a saved wiki, then Scout. Climate stays off unless you turn it on.
              They will propose a shelf of cards from the index — not one card per page.
            </p>
            <label className="cg-field">
              <span className="cg-field-label">World name</span>
              <input value={name} onChange={(e) => setName(e.target.value)} />
            </label>
            <label className="cg-field">
              <span className="cg-field-label">One-line premise</span>
              <textarea value={premise} onChange={(e) => setPremise(e.target.value)} rows={3} />
            </label>
            <fieldset className="cg-field">
              <legend className="cg-field-label">Wiki</legend>
              {(status?.savedWikis ?? []).length === 0 && (
                <p className="muted small">Save a Fandom or Tiddly URL in Porch Life first.</p>
              )}
              {(status?.savedWikis ?? []).map((url) => (
                <label key={url} className="cg-toggle">
                  <input
                    type="radio"
                    name="wiki"
                    checked={wikiUrl === url}
                    onChange={() => setWikiUrl(url)}
                  />
                  <span>{url}</span>
                </label>
              ))}
            </fieldset>
            <label className="cg-field cg-toggle">
              <input
                type="checkbox"
                checked={lorebooksOn}
                onChange={(e) => setLorebooksOn(e.target.checked)}
              />
              <span>Lorebooks — they scout a shelf; you sign which cards to write</span>
            </label>
            <label className="cg-field cg-toggle">
              <input
                type="checkbox"
                checked={climateEnabled}
                onChange={(e) => setClimateEnabled(e.target.checked)}
              />
              <span>Climate (off by default — no biome json)</span>
            </label>
          </div>
        )}

        {step === 1 && (
          <div className="cg-config" data-testid="world-from-wiki-review">
            <p className="muted small">
              Sign the cards they proposed. Default is off — no select-all.
              {' '}{signed.size} of {proposed.length} signed
              {titleCount > 0 ? ` (${titleCount} index pages).` : '.'}
            </p>
            {proposed.map((c, i) => (
              <label key={`${c.name}-${i}`} className="cg-toggle">
                <input
                  type="checkbox"
                  checked={signed.has(i)}
                  onChange={(e) => {
                    const next = new Set(signed);
                    if (e.target.checked) next.add(i);
                    else next.delete(i);
                    setSigned(next);
                  }}
                />
                <span>
                  <strong>{c.name}</strong>
                  {' '}({c.role}{c.group ? ` · ${c.group}` : ''})
                  <br />
                  <span className="muted small">{c.sourceTitles.join(', ')}</span>
                </span>
              </label>
            ))}
          </div>
        )}

        {step === 2 && (
          <div className="cg-config">
            <p>{writeStatus || 'Writing lorebook cards…'}</p>
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
            <label className="cg-field cg-toggle">
              <input
                type="checkbox"
                checked={climateEnabled}
                onChange={(e) => setClimateEnabled(e.target.checked)}
              />
              <span>Climate</span>
            </label>
            <p className="muted small">Lorebook ({entries.length})</p>
            {entries.map((e, i) => (
              <div key={`${e.name}-${i}`} className="card">
                <strong>{e.name || '(untitled)'}</strong>
                <p className="muted small">{e.content}</p>
              </div>
            ))}
          </div>
        )}
        {error && <p className="error">{error}</p>}
      </div>

      <div className="wizard-nav">
        <button disabled={step === 0 || busy} onClick={() => setStep(step - 1)}>← Back</button>
        {step === 0 && (
          <button className="primary" disabled={busy || !toolsOk || !wikiUrl} onClick={() => void scout()}>
            {busy ? 'Scouting…' : lorebooksOn ? 'Scout wiki' : 'Next: Preview'}
          </button>
        )}
        {step === 1 && (
          <button className="primary" disabled={busy || !toolsOk || signed.size === 0} onClick={() => void write()}>
            Write {signed.size} cards
          </button>
        )}
        {step === 2 && (
          <button disabled={!busy} onClick={() => void abortWrite()}>Stop</button>
        )}
        {step === 3 && (
          <button
            className="primary"
            disabled={busy || !name.trim() || !canOpenWorldFromWikiPreview({
              lorebooksOn,
              aborted,
              entryCount: entries.length,
            })}
            onClick={() => void save()}
          >
            Save World
          </button>
        )}
      </div>
    </div>
  );
}
