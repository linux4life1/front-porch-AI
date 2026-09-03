// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Model transport" — the web mirror of the desktop's Generation-tab section
// (lib/ui/settings/tabs/generation_tab.dart). Moved here out of the Porch
// Life card so both surfaces keep the switch under Generation settings.
// Auto-saves like PorchLifeSettings (it once lived inside that card): the
// flip POSTs the single changed key under `realism`, which SettingsPage's big
// Save button does not own — same wire shape it rode before, so no change to
// /api/settings handling.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';

export function ModelTransportCard() {
  const [preferText, setPreferText] = useState<boolean | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    void api
      .get<{ realism?: { preferTextEvals?: boolean } }>('/api/settings')
      .then((r) => setPreferText(!!r.realism?.preferTextEvals))
      .catch(() => setPreferText(false));
  }, []);

  if (preferText === null) return null;

  const set = (v: boolean) => {
    const prev = preferText;
    setPreferText(v);
    setError('');
    api.post('/api/settings', { realism: { preferTextEvals: v } }).catch((e) => {
      setPreferText(prev);
      setError(e instanceof ApiError ? e.message : 'Could not save that change');
    });
  };

  return (
    <section className="card pl-section">
      <h3>Model transport</h3>
      <p className="muted small pl-intro">
        How the engine evaluations (Realism, Journal, Growth Rings) talk to
        the model.
      </p>
      <div className="pl-row">
        <div className="pl-row-main">
          <span className="pl-row-icon" aria-hidden="true">🔧</span>
          <div className="pl-row-body">
            <div className="pl-row-label-line">
              <span className="pl-label">Native tool calling</span>
              <span className="pl-chip pl-chip-alone">works alone</span>
            </div>
            <p className="pl-blurb">
              When on, Realism, Journal and Growth use native tool calls if
              this model supports them — cleaner structured results, and on
              the common local templates no slower than the JSON floor. When
              off, every eval uses the JSON/XML floor even if the model can
              speak tools. The sidebar pill still shows whether the model
              can. Default on.
            </p>
          </div>
          <label className="pl-switch">
            <input
              type="checkbox"
              checked={!preferText}
              onChange={(e) => set(!e.target.checked)}
              aria-label="Native tool calling"
            />
          </label>
        </div>
      </div>
      {error && <p className="muted small">{error}</p>}
    </section>
  );
}
