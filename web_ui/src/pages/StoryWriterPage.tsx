// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Beat-by-beat prose writer for one scene inside the studio shell: quality
// chips per beat (computed by the server), the continuity fix shown as a
// strike-through diff with Undo, the rolling banned-phrase list, a lens
// picker, and Rewrite / Write next beat. Mirrors the desktop StoryWriterPage.

import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import { SpeakButton } from '../components/VoiceControls';
import { downloadBlob } from './story/storyUtil';
import { BEAT_TYPE_CLASS, PACING_GLYPH, PACING_LABEL, type QualityChip, type StoryProject } from '../storyTypes';
import { Chip, StudioShell } from './story/StudioShell';
import { LensMark, useLenses } from './StoryStructurePage';
import { beatsWritten, nextUnfinished, orderedScenes, sceneLabel } from './story/storyShape';
import '../styles/ws-j.css';

function QualityChips({ text, banned }: { text: string; banned: string[] }) {
  const [chips, setChips] = useState<QualityChip[]>([]);
  useEffect(() => {
    let live = true;
    api.post<{ chips: QualityChip[] }>('/api/stories/quality', { text, banned })
      .then((r) => { if (live) setChips(r.chips); })
      .catch(() => {});
    return () => { live = false; };
  }, [text, banned]);
  if (chips.length === 0) return null;
  return <div className="s-chips">{chips.map((c, i) => <Chip key={i} tone={c.tone}>{c.label}</Chip>)}</div>;
}

export function StoryWriterPage() {
  const { id = '', act, scene } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run, stop, save, reload } = useStory(id);
  const lenses = useLenses();
  const [copied, setCopied] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);
  const [lensOpen, setLensOpen] = useState(false);
  const [bannedOpen, setBannedOpen] = useState(false);
  const [bannedText, setBannedText] = useState('');

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }

  // No scene in the URL: the next unfinished scene, else the last one.
  const all = orderedScenes(p);
  const fallback = nextUnfinished(p) ?? all[all.length - 1];
  const ai = act !== undefined ? Number(act) : (fallback?.act ?? 0);
  const si = scene !== undefined ? Number(scene) : (fallback?.index ?? 0);
  const busy = status?.running ?? false;
  const sc = p.scenes[String(ai)]?.[si];
  const beats = p.beats[`${ai}-${si}`] ?? [];
  const studio = p.engine_mode === 'studio';
  const written = beatsWritten(p, ai, si);
  const banned = [...(p.banned_phrases ?? []), ...(p.auto_banned_phrases ?? [])];

  if (!sc) {
    return (
      <StudioShell id={id} project={p} section="write" status={status} error={error} onStop={stop}>
        <section className="card">
          <h3>Nothing to write yet</h3>
          <p className="muted">Build the structure first; the Write screen follows the scene you pick there.</p>
          <button className="s-btn-primary" onClick={() => navigate(`/stories/${id}/structure`)}>Go to Structure</button>
        </section>
      </StudioShell>
    );
  }

  const beatText = (bi: number) => p.prose[`${ai}-${si}-${bi}`]?.final || '';
  const sceneText = beats.map((_, bi) => beatText(bi)).filter(Boolean).join('\n\n');
  const lens = lenses.find((l) => l.id === (sc.lens || 'BASELINE_NEUTRAL'));

  const copy = async (text: string, tag: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(tag);
      setTimeout(() => setCopied(''), 1500);
    } catch { /* clipboard blocked — silent */ }
  };
  const exportScene = () => {
    const name = (sc.title || `scene_${si + 1}`).replace(/[^\w.-]+/g, '_');
    downloadBlob(new Blob([sceneText], { type: 'text/plain' }), `${name}.txt`);
    setMenuOpen(false);
  };
  const setLens = async (lensId: string) => {
    const scenes = { ...p.scenes, [String(ai)]: p.scenes[String(ai)].map((s, i) => (i === si ? { ...s, lens: lensId } : s)) };
    setLensOpen(false);
    await save({ scenes } as Partial<StoryProject>);
  };
  const undoFix = async (bi: number) => {
    await api.post(`/api/stories/${id}/undo-fix`, { actIndex: ai, sceneIndex: si, beatIndex: bi });
    reload();
  };
  const saveBanned = async () => {
    setBannedOpen(false);
    await save({ banned_phrases: bannedText.split('\n').map((s) => s.trim()).filter(Boolean) });
  };

  return (
    <StudioShell id={id} project={p} section="write" status={status} error={error} onStop={stop}>
      <div className="s-row" style={{ marginBottom: 10 }}>
        <div className="s-grow">
          <div className="s-row">
            <strong style={{ fontSize: '1.05rem' }}>{sceneLabel(p, ai, si)} · {sc.title}</strong>
            <select className="s-field" value={`${ai}-${si}`} aria-label="Another scene"
              onChange={(e) => { const [a, s] = e.target.value.split('-'); navigate(`/stories/${id}/write/${a}/${s}`); }}>
              {orderedScenes(p).map((r) => (
                <option key={r.scene.id ?? `${r.act}-${r.index}`} value={`${r.act}-${r.index}`}>
                  {sceneLabel(p, r.act, r.index)} {r.scene.title}
                </option>
              ))}
            </select>
          </div>
          <div className="muted small">
            {beats.length ? `Beat ${Math.min(written + 1, beats.length)} of ${beats.length}` : 'No beats yet'}
            {studio && p.lenses_enabled !== false && lens ? ` · Lens: ${lens.name}` : ''}
            {sc.location ? ` · ${sc.location}` : ''}
          </div>
        </div>
        {beats.length === 0 ? (
          <button className="s-btn-primary" disabled={busy} onClick={() => run('beat-director', { actIndex: ai, sceneIndex: si })}>Generate Beats</button>
        ) : (
          <button className="s-btn-quiet" disabled={busy} onClick={() => run('auto-write-scene', { actIndex: ai, sceneIndex: si })}>Auto-Write</button>
        )}
        <div className="scene-menu">
          <button className="ghost small" onClick={() => setMenuOpen(!menuOpen)}>⋯</button>
          {menuOpen && (
            <div className="export-menu">
              <button onClick={() => { copy(sceneText, 'scene'); setMenuOpen(false); }}>Copy scene text</button>
              <button onClick={exportScene}>Export scene (.txt)</button>
            </div>
          )}
        </div>
      </div>

      {studio && banned.length > 0 && (
        <section className="s-card" style={{ marginBottom: 12 }}>
          <div className="s-row">
            <span className="s-key s-grow">Banned this chapter (repeated too often lately)</span>
            <button className="s-btn-ghost" onClick={() => { setBannedText((p.banned_phrases ?? []).join('\n')); setBannedOpen(true); }}>Edit list</button>
          </div>
          <div className="s-chips">
            {banned.slice(0, 10).map((b, i) => <Chip key={i}>“{b}”</Chip>)}
            {banned.length > 10 && <Chip>+ {banned.length - 10} more</Chip>}
          </div>
          {bannedOpen && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <span className="muted small">One per line. The engine adds its own as it notices repeats; yours stay for the whole story.</span>
              <textarea className="s-textarea" value={bannedText} onChange={(e) => setBannedText(e.target.value)} />
              <div className="s-row"><button className="s-btn-primary" onClick={saveBanned}>Save</button>
                <button className="s-btn-ghost" onClick={() => setBannedOpen(false)}>Cancel</button></div>
            </div>
          )}
        </section>
      )}

      {beats.length === 0 && <p className="muted">Generate beats to break this scene into narrative units.</p>}

      {beats.map((b, bi) => {
        const text = beatText(bi);
        const fix = p.prose[`${ai}-${si}-${bi}`]?.fix;
        const typeClass = BEAT_TYPE_CLASS[b.type] || '';
        return (
          <section key={bi} className="card beat-card">
            <div className="page-head">
              <div className="beat-badges">
                <span className={`beat-type s-beat-type ${typeClass}`}>{b.type}</span>
                <span className="beat-meta">
                  <span title={`Pacing: ${PACING_LABEL[b.pacing] ?? 'Balanced'}`}>{PACING_GLYPH[b.pacing] ?? '➖'}</span>
                  {!studio && <span className={`valence v${b.valence >= 0 ? 'pos' : 'neg'}`}>{b.valence > 0 ? `+${b.valence}` : b.valence}</span>}
                </span>
              </div>
              <button className="ghost small" disabled={busy}
                onClick={() => run(text ? 'rewrite-beat' : 'draft-edit', { actIndex: ai, sceneIndex: si, beatIndex: bi })}>
                {text ? 'Rewrite' : 'Write'}
              </button>
            </div>
            <p className="muted small">
              Beat {b.number}{b.initiator ? ` · ${b.initiator}${b.reactor ? ` → ${b.reactor}` : ''}` : ''}: {b.description}
              {b.anchor ? <> <em>Anchor: {b.anchor}</em></> : null}
            </p>
            {text && <QualityChips text={text} banned={banned} />}
            {fix && (
              <div className="s-fix">
                <div className="s-row">
                  <Chip tone="bad">Continuity: fixed</Chip>
                  <span className="s-grow muted small">{fix.reason}</span>
                  <button className="s-btn-ghost" disabled={busy} onClick={() => undoFix(bi)}>Undo fix</button>
                </div>
                {fix.edits.map((e, i) => (
                  <p key={i} className="s-prose" style={{ margin: 0 }}>
                    <span className="s-del">{e.find}</span> <span className="s-ins">{e.replace}</span>
                  </p>
                ))}
              </div>
            )}
            {text ? (
              <div className="beat-prose">
                <p>{text}</p>
                <div className="beat-actions">
                  <button className="icon-btn" title="Copy beat" onClick={() => copy(text, `b${bi}`)}>
                    {copied === `b${bi}` ? '✓' : '📋'}
                  </button>
                  <SpeakButton text={text} />
                </div>
              </div>
            ) : (
              <p className="muted small">No prose yet.</p>
            )}
          </section>
        );
      })}
      {copied === 'scene' && <p className="muted small">Scene text copied.</p>}

      {beats.length > 0 && !busy && (
        <div className="s-bottom">
          <button className="s-btn-quiet" disabled={written === 0}
            onClick={() => run('rewrite-beat', { actIndex: ai, sceneIndex: si, beatIndex: written - 1 })}>↻ Rewrite beat</button>
          {studio && p.lenses_enabled !== false && (
            <button className="s-btn-quiet" onClick={() => setLensOpen(!lensOpen)}>Change lens</button>
          )}
          <span className="s-grow" />
          <button className="s-btn-primary" disabled={written >= beats.length} data-testid="story-write-next"
            onClick={() => run('draft-edit', { actIndex: ai, sceneIndex: si, beatIndex: written })}>✎ Write next beat</button>
        </div>
      )}
      {lensOpen && (
        <section className="s-card" style={{ marginTop: 10 }}>
          <span className="s-key">Writing lens for this scene</span>
          {lenses.map((l) => (
            <button key={l.id} className={`s-btn-ghost${l.id === (sc.lens || 'BASELINE_NEUTRAL') ? ' on' : ''}`}
              style={{ textAlign: 'left', display: 'flex', gap: 10, alignItems: 'center' }} onClick={() => setLens(l.id)}>
              <LensMark lensId={l.id} lenses={lenses} />
              <span><strong>{l.name}</strong> <span className="muted small">{l.context}</span></span>
            </button>
          ))}
        </section>
      )}
    </StudioShell>
  );
}
