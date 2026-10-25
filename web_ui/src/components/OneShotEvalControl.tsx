// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-Shot Eval Auto/On/Off, directly above the tool-calling pill in the
// insight panel — desktop sidebar parity (OneShotEvalRow). It used to sit in
// the tools list's "Realism performance" fold. The mode is a global realism
// setting, so it reads and writes the unscoped tools snapshot.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { type ToolsState } from './ChatToolsShared';

type Mode = 'auto' | 'on' | 'off';

const MODES: [Mode, string][] = [
  ['auto', 'Auto'],
  ['on', 'On'],
  ['off', 'Off'],
];

/** Older facades send only the legacy bool, which tells on from not-on. */
function modeOf(t: ToolsState): Mode {
  return t.realismOneShotMode ?? (t.realismOneShotEval ? 'on' : 'auto');
}

export function OneShotEvalControl({ reloadKey }: { reloadKey: number }) {
  const [mode, setMode] = useState<Mode | null>(null);

  useEffect(() => {
    let live = true;
    api
      .get<ToolsState>('/api/chat/tools')
      .then((t) => live && setMode(modeOf(t)))
      .catch(() => {
        /* no active chat — leave hidden, as the tools list does */
      });
    return () => {
      live = false;
    };
  }, [reloadKey]);

  if (!mode) return null;

  const choose = (value: Mode) => {
    api
      .post<ToolsState>('/api/chat/tools/toggle', { name: 'oneShotMode', value })
      .then((t) => setMode(modeOf(t)))
      .catch((e: unknown) => console.warn('One-Shot Eval mode not saved', e));
  };

  return (
    <div className="one-shot-row">
      <div className="tool-toggle">
        <span>One-Shot Eval</span>
        <span className="mode-seg" role="radiogroup" aria-label="One-Shot Eval mode">
          {MODES.map(([m, name]) => (
            <button
              key={m}
              role="radio"
              aria-checked={mode === m}
              className={`mode-seg-btn${mode === m ? ' selected' : ''}`}
              onClick={() => choose(m)}
            >
              {name}
            </button>
          ))}
        </span>
      </div>
      <p className="muted small">
        Fuses the realism evals into a single LLM call for roughly double the processing speed.
        Auto uses it on remote AI services that support tool calls, and keeps the safer multi-call
        path on local models, where small models can struggle with the combined prompt.
      </p>
    </div>
  );
}
