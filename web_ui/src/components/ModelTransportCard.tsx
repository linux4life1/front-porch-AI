// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Engine & Display Options" — the web mirror of Desktop's Category 5
// Generation card (Model transport + Display Output). Auto-saves independently
// via /api/settings, matching Desktop's immediate storage writes.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { SliderField } from './StudioSliderField';

interface EngineDisplayResponse {
  realism?: { preferTextEvals?: boolean };
  displayBufferEnabled?: boolean;
  targetDisplayTps?: number;
  bufferDurationSeconds?: number;
}

export function ModelTransportCard() {
  const [preferText, setPreferText] = useState<boolean | null>(null);
  const [displayBufferEnabled, setDisplayBufferEnabled] = useState(false);
  const [targetDisplayTps, setTargetDisplayTps] = useState(30);
  const [bufferDurationSeconds, setBufferDurationSeconds] = useState(3);
  const [error, setError] = useState('');

  useEffect(() => {
    void api
      .get<EngineDisplayResponse>('/api/settings')
      .then((r) => {
        setPreferText(!!r.realism?.preferTextEvals);
        if (typeof r.displayBufferEnabled === 'boolean') {
          setDisplayBufferEnabled(r.displayBufferEnabled);
        }
        if (typeof r.targetDisplayTps === 'number') {
          setTargetDisplayTps(r.targetDisplayTps);
        }
        if (typeof r.bufferDurationSeconds === 'number') {
          setBufferDurationSeconds(r.bufferDurationSeconds);
        }
      })
      .catch(() => setPreferText(false));
  }, []);

  if (preferText === null) return null;

  const setPreferTextEval = (v: boolean) => {
    const prev = preferText;
    setPreferText(v);
    setError('');
    api.post('/api/settings', { realism: { preferTextEvals: v } }).catch((e) => {
      setPreferText(prev);
      setError(e instanceof ApiError ? e.message : 'Could not save that change');
    });
  };

  const setDisplayBuffer = (v: boolean) => {
    const prev = displayBufferEnabled;
    setDisplayBufferEnabled(v);
    setError('');
    api.post('/api/settings', { displayBufferEnabled: v }).catch((e) => {
      setDisplayBufferEnabled(prev);
      setError(e instanceof ApiError ? e.message : 'Could not save that change');
    });
  };

  const setTargetTps = (v: number) => {
    const rounded = Math.round(Math.max(5, Math.min(60, v)));
    const prev = targetDisplayTps;
    setTargetDisplayTps(rounded);
    setError('');
    api.post('/api/settings', { targetDisplayTps: rounded }).catch((e) => {
      setTargetDisplayTps(prev);
      setError(e instanceof ApiError ? e.message : 'Could not save that change');
    });
  };

  const setBufferDuration = (v: number) => {
    const rounded = Math.round(Math.max(1, Math.min(10, v)));
    const prev = bufferDurationSeconds;
    setBufferDurationSeconds(rounded);
    setError('');
    api.post('/api/settings', { bufferDurationSeconds: rounded }).catch((e) => {
      setBufferDurationSeconds(prev);
      setError(e instanceof ApiError ? e.message : 'Could not save that change');
    });
  };

  return (
    <section className="card gen-section-card" data-testid="model-transport-card">
      <h3 className="gen-section-title">Engine &amp; Display Options</h3>
      <div className="gen-engine-grid">
        <div className="gen-engine-tile">
          <h4 className="gen-subsection-heading">Model transport</h4>
          <p className="muted small" style={{ margin: '0 0 8px' }}>
            How the engine evaluations (Realism, Journal, Growth Rings) talk to
            the model.
          </p>
          <div className="gen-engine-row">
            <span className="gen-engine-row-title">
              <span>Native tool calling</span>
              <span className="pl-chip pl-chip-alone">works alone</span>
            </span>
            <input
              type="checkbox"
              className="switch"
              checked={!preferText}
              onChange={(e) => setPreferTextEval(!e.target.checked)}
              aria-label="Native tool calling"
            />
          </div>
          <p className="pl-blurb" style={{ marginTop: 6 }}>
            When on, Realism, Journal and Growth use native tool calls if
            this model supports them — cleaner structured results, and on
            the common local templates no slower than the JSON floor. When
            off, every eval uses the JSON/XML floor even if the model can
            speak tools. The sidebar pill still shows whether the model
            can. Default on.
          </p>
        </div>

        <div className="gen-engine-tile">
          <h4 className="gen-subsection-heading">Display Output</h4>
          <div className="gen-engine-row">
            <span className="gen-engine-row-title">Smooth Output Buffer</span>
            <input
              type="checkbox"
              className="switch"
              checked={displayBufferEnabled}
              onChange={(e) => setDisplayBuffer(e.target.checked)}
              aria-label="Smooth Output Buffer"
            />
          </div>
          {displayBufferEnabled && (
            <div style={{ marginTop: 8 }}>
              <SliderField
                label="Target Display Speed (t/s)"
                value={targetDisplayTps}
                min={5}
                max={60}
                step={1}
                onChange={setTargetTps}
              />
              <SliderField
                label="Buffer Duration (seconds)"
                value={bufferDurationSeconds}
                min={1}
                max={10}
                step={1}
                onChange={setBufferDuration}
              />
            </div>
          )}
        </div>
      </div>
      {error && <p className="muted small">{error}</p>}
    </section>
  );
}
