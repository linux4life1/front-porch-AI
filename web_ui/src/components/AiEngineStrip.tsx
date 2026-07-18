// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Compact "can the AI generate right now?" strip for the Porch Stories
// surfaces — the web mirror of the desktop AiEngineStatusCard. Stories need a
// running, model-loaded backend; before this, kicking off a stage with the
// engine down just failed. Reads /api/backend/status and links to the Models
// page (local engine) or Settings (remote API); a not-running local engine
// gets a one-tap Start that reuses the Models page's restart endpoint.

import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client';
import type { BackendStatus } from './models/types';

export function AiEngineStrip() {
  const [status, setStatus] = useState<BackendStatus | null>(null);
  const [starting, setStarting] = useState(false);

  const load = useCallback(
    () => api.get<BackendStatus>('/api/backend/status').then(setStatus).catch(() => {}),
    [],
  );

  useEffect(() => {
    void load();
    const t = setInterval(load, 5000);
    return () => clearInterval(t);
  }, [load]);

  if (!status) return null;

  const start = async () => {
    setStarting(true);
    try {
      await api.post('/api/backend/restart');
    } catch {
      /* the strip keeps polling; state will reflect reality */
    }
    await load();
    setStarting(false);
  };

  let tone: 'ok' | 'busy' | 'down';
  let text: string;
  let action: React.ReactNode;

  if (!status.isLocal) {
    // Remote API — readiness is config-based and not fully visible here; show
    // a neutral pointer to Settings instead of guessing.
    tone = 'ok';
    text = 'AI engine: Remote API — stories use the same backend as chat.';
    action = <Link to="/settings">Settings</Link>;
  } else if (status.running && status.modelReady) {
    tone = 'ok';
    text = `AI engine ready · ${status.loadedModel}`;
    action = <Link to="/models">Change</Link>;
  } else if (status.starting || status.running) {
    tone = 'busy';
    text = status.starting
      ? 'AI engine starting…'
      : `AI engine loading model… ${status.statusMessage || ''}`.trim();
    action = <Link to="/models">Models</Link>;
  } else {
    tone = 'down';
    text = 'AI engine not running — stories use the same AI backend as chat.';
    action = (
      <>
        <button className="ghost small" onClick={start} disabled={starting}>
          {starting ? 'Starting…' : 'Start'}
        </button>
        <Link to="/models">Models</Link>
      </>
    );
  }

  return (
    <div className={`engine-strip engine-strip-${tone}`} aria-live="polite">
      <span className="engine-dot" />
      <span className="engine-text">{text}</span>
      <span className="engine-actions">{action}</span>
    </div>
  );
}
