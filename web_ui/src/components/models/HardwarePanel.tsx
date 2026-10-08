// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Detected GPU/VRAM/RAM + VRAM-appropriate model search suggestions. Hidden
// entirely when the host doesn't expose hardware info (older server / 404).

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { type Hardware, fmtGb, graphicsMemoryLine, retiredLayersNote } from './types';

export function HardwarePanel({ onPickQuery }: { onPickQuery: (q: string) => void }) {
  const [hw, setHw] = useState<Hardware | null>(null);
  const [recs, setRecs] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [hidden, setHidden] = useState(false);

  useEffect(() => {
    api.get<Hardware>('/api/backend/hardware').then(setHw).catch(() => setHidden(true));
    api.get<{ queries: string[] }>('/api/backend/recommendations').then((r) => setRecs(r.queries)).catch(() => {});
  }, []);

  const redetect = async () => {
    setBusy(true);
    try {
      setHw(await api.post<Hardware>('/api/backend/hardware/redetect'));
    } catch {
      /* keep prior info */
    } finally {
      setBusy(false);
    }
  };

  const dismissRetired = async () => {
    try {
      await api.post('/api/settings', { gpuLayersNoteSeen: true });
      setHw((h) => (h ? { ...h, gpuLayersRetired: null } : h));
    } catch {
      /* the note stays; tapping again retries */
    }
  };

  if (hidden || !hw) return null;
  const retired = retiredLayersNote(hw);
  const accel = [hw.hasCuda && 'CUDA', hw.hasRocm && 'ROCm', hw.hasMetal && 'Metal'].filter(Boolean).join(' · ');

  return (
    <section className="card">
      <h3>Hardware</h3>
      <div className="hw-grid">
        <div className="hw-cell"><span className="muted small">GPU</span><strong>{hw.gpuName}</strong></div>
        <div className="hw-cell">
          <span className="muted small">VRAM</span>
          <strong>{fmtGb(hw.vramMb)}{hw.isSharedMemory ? ' (shared)' : ''}</strong>
        </div>
        <div className="hw-cell"><span className="muted small">RAM</span><strong>{fmtGb(hw.ramMb)}</strong></div>
        {accel && <div className="hw-cell"><span className="muted small">Acceleration</span><strong>{accel}</strong></div>}
        <div className="hw-cell" data-testid="hw-graphics-memory">
          <span className="muted small">Graphics memory</span><strong>{graphicsMemoryLine(hw)}</strong>
        </div>
      </div>
      {retired && (
        <p className="muted small" data-testid="hw-layers-retired">
          {retired}{' '}
          <button type="button" className="ghost" onClick={dismissRetired}>Got it</button>
        </p>
      )}
      <div className="tool-row">
        <button className="ghost" disabled={busy} onClick={redetect}>{busy ? 'Detecting…' : 'Re-detect'}</button>
      </div>
      {recs.length > 0 && (
        <>
          <p className="muted small">Recommended for your VRAM — tap to search:</p>
          <div className="rec-chips">
            {recs.map((q) => (
              <button key={q} type="button" className="rec-chip" onClick={() => onPickQuery(q)}>{q}</button>
            ))}
          </div>
        </>
      )}
    </section>
  );
}
