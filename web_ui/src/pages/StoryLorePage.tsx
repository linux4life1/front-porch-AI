// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The facts the story must keep straight, the lore behind it, and the story
// so far — with lore file uploads and a search tester. Mirrors the desktop
// LoreSection.

import { useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import { Chip, StudioShell } from './story/StudioShell';
import { sceneIndexesInSequence, sceneLabel, sceneLabelById } from './story/storyShape';
import '../styles/ws-j.css';

type Hit = { score: number; topic: string; detail: string; semantic: boolean };

export function StoryLorePage() {
  const { id = '' } = useParams();
  const { project: p, status, error, stop, save, reload } = useStory(id);
  const [tab, setTab] = useState<'continuity' | 'lore' | 'sofar'>('continuity');
  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<Hit[] | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const facts = p.continuity ?? [];
  const files = new Set(p.lore.flatMap((l) => l.related_to.filter((r) => r.startsWith('file:'))));
  const subtitle = `${facts.length} fact${facts.length === 1 ? '' : 's'} · ${p.lore.length} lore entr${p.lore.length === 1 ? 'y' : 'ies'} · ${files.size} file${files.size === 1 ? '' : 's'}`;

  const upload = async (list: FileList | null) => {
    if (!list) return;
    let added = 0;
    for (const f of Array.from(list)) {
      const text = await f.text();
      const r = await api.post<{ added: number }>(`/api/stories/${id}/lore`, { name: f.name, text });
      added += r.added;
    }
    reload();
    setTab('lore');
    void added;
  };
  const search = async () => {
    const r = await api.post<{ hits: Hit[] }>(`/api/stories/${id}/lore/search`, { query });
    setHits(r.hits);
  };
  const forgetFact = (i: number) => save({ continuity: facts.filter((_, k) => k !== i) });
  const removeLore = (i: number) => save({ lore: p.lore.filter((_, k) => k !== i) });

  return (
    <StudioShell id={id} project={p} section="lore" status={status} error={error} onStop={stop}>
      <div className="muted small">{subtitle}</div>
      <div className="s-row" style={{ margin: '10px 0 12px' }}>
        <div className="s-seg">
          {(['continuity', 'lore', 'sofar'] as const).map((t) => (
            <button key={t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>
              {t === 'continuity' ? 'Continuity' : t === 'lore' ? 'Lore' : 'Story so far'}
            </button>
          ))}
        </div>
        <button className="s-btn-quiet" onClick={() => fileRef.current?.click()}>⤒ Add lore file</button>
        <input ref={fileRef} type="file" accept=".txt,.md,text/plain" multiple hidden onChange={(e) => upload(e.target.files)} />
        <button className="s-btn-quiet" disabled={p.lore.length === 0} onClick={() => setSearchOpen(!searchOpen)}>⌕ Test search</button>
      </div>

      {searchOpen && (
        <section className="s-card" style={{ marginBottom: 12 }}>
          <span className="s-key">What would the writer see?</span>
          <textarea className="s-textarea" value={query} placeholder='Describe a beat, e.g. "Mara haggles at the salt market"'
            onChange={(e) => setQuery(e.target.value)} />
          <div className="s-row">
            <button className="s-btn-primary" disabled={!query.trim()} onClick={search}>Search</button>
            {hits && <span className="muted small">{hits[0]?.semantic ? 'by meaning (embeddings)' : 'by word overlap (embedding model not set up)'}</span>}
          </div>
          {hits?.map((h, i) => <p key={i} className="s-small" style={{ margin: 0 }}>{Math.round(h.score * 100)}%  <strong>{h.topic}</strong>: {h.detail}</p>)}
          {hits && hits.length === 0 && <span className="muted small">Nothing close enough.</span>}
        </section>
      )}

      <section className="s-card">
        {tab === 'continuity' && (facts.length === 0
          ? <span className="muted small">{p.engine_mode === 'studio' ? 'Facts are added automatically after each scene is written.' : 'The Quick engine does not keep a continuity ledger. Switch the story to Studio to get one.'}</span>
          : [...facts.filter((f) => !f.retired_scene_id), ...facts.filter((f) => f.retired_scene_id)].map((f) => {
            const i = facts.indexOf(f);
            const retired = !!f.retired_scene_id;
            const from = f.scene_id ? sceneLabelById(p, f.scene_id) : '';
            return (
              <div key={i} className={`s-fact${retired ? ' retired' : ''}`}>
                <Chip tone={retired ? '' : 'honey'}>{retired ? 'Retired' : f.category}</Chip>
                <span className="s-grow v"><strong>{f.key}</strong> · {f.value}{f.entity && <span className="muted"> ({f.entity})</span>}</span>
                <span className="s-mono">{retired ? `${from} → ${sceneLabelById(p, f.retired_scene_id!)}` : (from ? `from ${from}` : 'always')}</span>
                <button className="s-btn-ghost" title="Forget this fact" onClick={() => forgetFact(i)}>✕</button>
              </div>
            );
          }))}

        {tab === 'lore' && (p.lore.length === 0
          ? <span className="muted small">No lore yet. Add a file or let the story bible create some.</span>
          : p.lore.map((l, i) => (
            <div key={i} className="s-fact" style={{ alignItems: 'flex-start' }}>
              <div className="s-grow">
                <div className="s-row">
                  <strong>{l.topic}</strong>
                  {l.related_to.filter((r) => r.startsWith('file:')).map((r) => <Chip key={r}>📄 {r.slice(5)}</Chip>)}
                  {(l.valid_from_act > 1 || l.valid_from_scene > 1) && <span className="muted small">from act {l.valid_from_act}, scene {l.valid_from_scene}</span>}
                </div>
                <div className="s-small s-muted">{l.detail}</div>
              </div>
              <button className="s-btn-ghost" title="Remove" onClick={() => removeLore(i)}>✕</button>
            </div>
          )))}

        {tab === 'sofar' && (() => {
          const rows: JSX.Element[] = [];
          for (const seq of p.sequences ?? []) {
            const act = p.acts.findIndex((a) => a.number === seq.act);
            const indexes = sceneIndexesInSequence(p, act, seq.number);
            if (indexes.length === 0) continue;
            rows.push(<div key={`s${seq.number}`} style={{ color: 'var(--studio-honey)', fontWeight: 600, marginTop: 8 }}>Sequence {seq.number} · {seq.title}</div>);
            if (seq.summary) rows.push(<p key={`sum${seq.number}`} className="s-small" style={{ margin: '2px 0' }}>{seq.summary}</p>);
            for (const i of indexes) {
              const s = p.scenes[String(act)][i];
              if (s.summary) rows.push(<p key={`sc${act}-${i}`} className="muted small" style={{ margin: '2px 0' }}>{sceneLabel(p, act, i)} {s.title}: {s.summary}</p>);
            }
          }
          return rows.length ? rows : <span className="muted small">Nothing written yet.</span>;
        })()}
      </section>
    </StudioShell>
  );
}
