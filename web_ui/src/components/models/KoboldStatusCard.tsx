// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "Local model" card (the desktop's KoboldStatusCard): how the
// local model runs on the host, in plain words, and the one thing to set
// in auto mode, the context, with the same verdicts as the desktop. With a
// preset in use it says what the preset does. And, apart from it, the
// KoboldCpp preset chat uses, picked from the host's presets.

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import type { KoboldPhase } from './types';

export type KoboldVerdict = { outcome: string; title: string; text: string };

export type LocalModel = {
  model: string;
  modelName: string | null;
  running: boolean;
  phase: KoboldPhase;
  preset: { path: string; name: string; words: string } | null;
  auto: {
    lines: string[];
    context: number;
    choices: number[];
    largestGood: number | null;
    verdicts: Record<string, KoboldVerdict>;
  } | null;
  presets: { path: string; name: string; line: string }[];
  /** A model is chosen and its file could not be read (additive). */
  modelUnreadable?: boolean;
};

const tokens = (n: number) => n.toLocaleString('en-US');

// The desktop card's pill for each phase (unloaded: the model is out of
// memory for being idle; the next request loads it back).
const PILLS: Record<KoboldPhase, { cls: string; label: string }> = {
  ready: { cls: 'ready', label: 'Ready' },
  unloaded: { cls: 'unloaded', label: 'Unloaded' },
  loading: { cls: 'loading', label: 'Loading…' },
  starting: { cls: 'loading', label: 'Loading…' },
  stopped: { cls: 'stopped', label: 'Stopped' },
};

function message(e: unknown) {
  return e instanceof ApiError || e instanceof Error ? e.message : String(e);
}

export function KoboldStatusCard({ onError }: { onError: (m: string) => void }) {
  const [card, setCard] = useState<LocalModel | null>(null);
  // A context too big for the host, waiting for "keep anyway".
  const [pending, setPending] = useState<number | null>(null);
  const [asking, setAsking] = useState(false);

  const load = useCallback(
    () =>
      api
        .get<LocalModel>('/api/backend/local-model')
        .then(setCard)
        .catch((e) => onError(message(e))),
    [onError],
  );
  useEffect(() => {
    void load();
    // Running and ready change on the host; a slow refresh is enough.
    const t = setInterval(() => void load(), 10000);
    return () => clearInterval(t);
  }, [load]);

  const setContext = async (context: number) => {
    setPending(null);
    setAsking(false);
    try {
      setCard(await api.post<LocalModel>('/api/backend/local-model/context', { context }));
    } catch (e) {
      onError(message(e));
    }
  };

  const setPreset = async (path: string | null) => {
    try {
      setCard(await api.post<LocalModel>('/api/backend/local-model/preset', { path }));
    } catch (e) {
      onError(message(e));
    }
  };

  if (!card) return null;
  const pill = PILLS[card.phase];
  const auto = card.auto;
  const picked = pending ?? auto?.context ?? 0;
  const verdict = auto?.verdicts[String(picked)];
  const kind =
    verdict?.outcome === 'tooBig' ? 'bad' : verdict?.outcome === 'tooSmall' ? 'warn' : 'ok';

  return (
    <>
      <section className="kc-card" aria-labelledby="kc-local-h" data-testid="local-model-card">
        <div className="kc-head">
          <div>
            <h3 id="kc-local-h">Local model</h3>
            <div className="kc-sub">
              {card.modelName ?? 'No model chosen'} · {card.running ? 'running' : 'not running'}
            </div>
          </div>
          <span className={`kc-pill ${pill.cls}`}>{pill.label}</span>
        </div>

        {card.preset ? (
          <>
            <ul className="kc-lines">
              <li>
                <span className="kc-dot" aria-hidden="true" />
                <span>Uses your preset “{card.preset.name}”.</span>
              </li>
            </ul>
            <p className="kc-words">{card.preset.words}</p>
          </>
        ) : !auto ? (
          <ul className="kc-lines">
            <li>
              <span className="kc-dot" aria-hidden="true" />
              <span>
                {!card.model
                  ? 'Choose a model below to see how it runs here.'
                  : card.modelUnreadable
                    ? 'The model file could not be read. Is it still in its folder? You can choose another model below.'
                    : 'Still finding out what this computer can do…'}
              </span>
            </li>
          </ul>
        ) : (
          <>
            <ul className="kc-lines">
              {auto.lines.map((line) => (
                <li key={line}>
                  <span className="kc-dot" aria-hidden="true" />
                  <span>{line}</span>
                </li>
              ))}
            </ul>
            <div className="kc-context">
              <span className="kc-context-label" id="kc-ctx-l">
                Context: how much chat history the character remembers
              </span>
              <div className="kc-chips" role="group" aria-labelledby="kc-ctx-l">
                {auto.choices.map((c) => (
                  <button
                    key={c}
                    type="button"
                    className="kc-chip"
                    aria-pressed={c === picked}
                    onClick={() => {
                      if (auto.verdicts[String(c)]?.outcome === 'tooBig') {
                        setPending(c);
                        setAsking(false);
                      } else {
                        void setContext(c);
                      }
                    }}
                  >
                    {tokens(c)}
                  </button>
                ))}
              </div>
              {verdict && (
                <div className={`kc-verdict ${kind}`} data-testid="local-model-verdict">
                  <span className="kc-mark" aria-hidden="true" />
                  <p>
                    <b>{verdict.title}</b> {verdict.text}
                  </p>
                </div>
              )}
              {pending !== null && !asking && (
                <div className="kc-row">
                  {auto.largestGood !== null && (
                    <button type="button" className="kc-btn solid" onClick={() => void setContext(auto.largestGood!)}>
                      Use {tokens(auto.largestGood)} tokens
                    </button>
                  )}
                  <button type="button" className="kc-btn" onClick={() => setAsking(true)}>
                    Keep {tokens(pending)} anyway…
                  </button>
                </div>
              )}
              {pending !== null && asking && (
                <div className="kc-row" role="group" aria-label={`Keep ${tokens(pending)} tokens?`}>
                  <span>Keep {tokens(pending)} tokens?</span>
                  <button type="button" className="kc-btn solid" onClick={() => void setContext(pending)}>
                    Keep it
                  </button>
                  <button type="button" className="kc-btn" onClick={() => setAsking(false)}>
                    Cancel
                  </button>
                </div>
              )}
            </div>
          </>
        )}
      </section>

      <section className="kc-card" aria-labelledby="kc-preset-h" data-testid="kobold-preset-card">
        <h3 id="kc-preset-h" style={{ margin: 0, fontSize: 18, fontWeight: 650 }}>
          KoboldCpp preset
        </h3>
        <label className="kc-label" htmlFor="kc-preset">
          Chat uses
        </label>
        <select
          id="kc-preset"
          className="kc-select"
          value={card.preset?.path ?? ''}
          onChange={(e) => void setPreset(e.target.value || null)}
        >
          <option value="">The app's own settings (automatic)</option>
          {card.presets.map((p) => (
            <option key={p.path} value={p.path}>
              {p.name} — {p.line}
            </option>
          ))}
        </select>
        {card.preset && (
          <div className="kc-plain">
            <span className="kc-plain-head">In plain words</span>
            <p className="kc-words">{card.preset.words}</p>
          </div>
        )}
      </section>
    </>
  );
}
