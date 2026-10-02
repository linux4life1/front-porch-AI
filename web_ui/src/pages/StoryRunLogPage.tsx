// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Every model call made for this story, newest first: stage, model, how
// long, whether the check passed; tap one to read the prompt and the reply.
// Mirrors the desktop RunLogSection.

import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { StoryRunEntry } from '../storyTypes';
import { Chip, StudioShell } from './story/StudioShell';
import '../styles/ws-j.css';

const tone = (v: string) => ({ PASS: 'teal', FAIL: 'bad', ERROR: 'bad', INVALID: 'honey' }[v] ?? '');

export function StoryRunLogPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, stop } = useStory(id);
  const [entries, setEntries] = useState<StoryRunEntry[]>([]);
  const [open, setOpen] = useState<StoryRunEntry | null>(null);
  const [tab, setTab] = useState<'prompt' | 'response'>('prompt');

  const load = useCallback(() => {
    api.get<{ entries: StoryRunEntry[] }>(`/api/stories/${id}/log`)
      .then((r) => setEntries([...r.entries].reverse())).catch(() => {});
  }, [id]);
  useEffect(load, [load, status?.running, p?.updated_at]);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const clock = (iso: string) => new Date(iso).toLocaleTimeString([], { hour12: false });

  return (
    <StudioShell id={id} project={p} section="log" status={status} error={error} onStop={stop}>
      <div className="s-row" style={{ marginBottom: 8 }}>
        <span className="s-grow muted small">
          {entries.length === 0 ? 'No model calls yet. Every call this story makes will be listed here.'
            : `${entries.length} call${entries.length === 1 ? '' : 's'} · newest first · tap one to read it`}
        </span>
        {entries.length > 0 && (
          <button className="s-btn-ghost" onClick={async () => { await api.post(`/api/stories/${id}/log/clear`, {}); load(); }}>Clear</button>
        )}
      </div>
      {entries.map((e, i) => (
        <div key={i} className="s-card s-log-row" style={{ marginBottom: 6 }} onClick={() => { setOpen(e); setTab('prompt'); }}>
          <span className="s-mono">{clock(e.at)}</span>
          <span className="s-grow" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.stage || '(call)'}</span>
          <div className="s-chips">
            <Chip>{e.role}</Chip>
            {e.attempt > 1 && <Chip tone="honey">try {e.attempt}</Chip>}
            {e.verdict && <Chip tone={tone(e.verdict)}>{e.verdict}</Chip>}
            <span className="muted small">{(e.millis / 1000).toFixed(1)}s · {e.tokens} tok</span>
          </div>
        </div>
      ))}
      {open && (
        <div className="s-card" style={{ marginTop: 12 }}>
          <div className="s-row">
            <strong className="s-grow">{open.stage || 'Model call'}</strong>
            <button className="s-btn-ghost" onClick={() => setOpen(null)}>Close</button>
          </div>
          <div className="s-chips">
            <Chip>{open.backend}</Chip><Chip>{open.role}</Chip><Chip>try {open.attempt}</Chip>
            {open.verdict && <Chip tone={tone(open.verdict)}>{open.verdict}</Chip>}
            <Chip>{(open.millis / 1000).toFixed(1)}s</Chip><Chip>{open.tokens} tokens</Chip>
          </div>
          {open.note && <p className="muted small" style={{ margin: 0 }}>{open.note}</p>}
          <div className="s-seg">
            <button className={tab === 'prompt' ? 'on' : ''} onClick={() => setTab('prompt')}>Prompt</button>
            <button className={tab === 'response' ? 'on' : ''} onClick={() => setTab('response')}>Reply</button>
          </div>
          <pre className="s-log-text">{(tab === 'prompt' ? open.prompt : open.response) || '(empty)'}</pre>
        </div>
      )}
    </StudioShell>
  );
}
