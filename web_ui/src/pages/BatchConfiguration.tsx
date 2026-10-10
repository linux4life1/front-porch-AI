// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { StudioDesk } from '../components/models/StudioDesk';
import type { ImageConfig } from '../components/models/studio/types';

export function BatchConfiguration(props: { expressions: boolean; edit: boolean; busy: boolean }) {
  const [cfg, setCfg] = useState<ImageConfig>();
  const [totpEnabled, setTotpEnabled] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    let live = true;
    void api.get<ImageConfig>('/api/image/config')
      .then((next) => { if (live) setCfg(next); })
      .catch(() => { if (live) setError('Could not load generation settings.'); });
    void api.get<{totpEnabled?: boolean}>('/api/auth/state')
      .then((next) => { if (live) setTotpEnabled(!!next.totpEnabled); })
      .catch(() => {});
    return () => { live = false; };
  }, []);
  const save = async (patch: Record<string, unknown>) => {
    if (props.busy) return false;
    setError('');
    try {
      setCfg(await api.post<ImageConfig>('/api/image/config', patch));
      return true;
    } catch (e) {
      if (e instanceof ApiError && e.payload.totpRequired === true) setTotpEnabled(true);
      setError(e instanceof ApiError ? e.message : 'Could not save generation settings.');
      return false;
    }
  };
  const mode = props.expressions
    ? cfg?.packConfigMode ?? (cfg?.backend === 'a1111' ? 'create' : 'edit')
    : props.edit ? 'edit' : 'create';
  return <details className="batch-configuration">
    <summary>Generation settings · {mode === 'edit' ? 'Edit graph and model' : 'Create graph and model'}</summary>
    {error ? <p role="alert">{error}</p> : null}
    {cfg ? <StudioDesk cfg={cfg} onConfig={setCfg} save={save} totpEnabled={totpEnabled}
      configurationOnly configurationMode={mode} busy={props.busy}
      prompt="" onPrompt={() => {}} onGenerate={() => {}} /> : <p>Loading generation settings…</p>}
  </details>;
}
