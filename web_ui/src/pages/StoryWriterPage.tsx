// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Beat-by-beat prose writer for one scene: each beat shows a colored type badge,
// pacing + valence, and its draft/final prose with Copy + Speak. Generate beats,
// auto-write the scene, regenerate a single beat, copy the whole scene, or export
// it as .txt. Mirrors the desktop StoryWriterPage.

import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { SpeakButton } from '../components/VoiceControls';
import { downloadBlob } from './story/storyUtil';
import { BEAT_TYPE_CLASS, PACING_GLYPH, PACING_LABEL } from '../storyTypes';
import '../styles/ws-j.css';

export function StoryWriterPage() {
  const { id = '', act = '0', scene = '0' } = useParams();
  const ai = Number(act);
  const si = Number(scene);
  const navigate = useNavigate();
  const { project: p, status, error, run } = useStory(id);
  const [copied, setCopied] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const busy = status?.running ?? false;
  const sc = p.scenes[String(ai)]?.[si];
  const beats = p.beats[`${ai}-${si}`] ?? [];

  const beatText = (bi: number) => {
    const pr = p.prose[`${ai}-${si}-${bi}`];
    return pr?.final || pr?.draft || '';
  };
  const sceneText = beats.map((_, bi) => beatText(bi)).filter(Boolean).join('\n\n');

  const copy = async (text: string, tag: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(tag);
      setTimeout(() => setCopied(''), 1500);
    } catch {
      // Clipboard blocked (insecure context) — silent; the buttons stay usable.
    }
  };
  const exportScene = () => {
    const name = (sc?.title || `scene_${si + 1}`).replace(/[^\w.-]+/g, '_');
    downloadBlob(new Blob([sceneText], { type: 'text/plain' }), `${name}.txt`);
    setMenuOpen(false);
  };

  return (
    <div className="page">
      <div className="page-head">
        <button className="ghost" onClick={() => navigate(`/stories/${id}/structure`)}>← Structure</button>
        <h2>{sc ? `Scene ${sc.number}: ${sc.title}` : 'Scene'}</h2>
        {sceneText && (
          <div className="scene-menu">
            <button className="ghost small" onClick={() => setMenuOpen(!menuOpen)}>⋯</button>
            {menuOpen && (
              <div className="export-menu">
                <button onClick={() => { copy(sceneText, 'scene'); setMenuOpen(false); }}>Copy scene text</button>
                <button onClick={exportScene}>Export scene (.txt)</button>
              </div>
            )}
          </div>
        )}
      </div>

      {busy && (
        <div className="card story-progress" aria-live="polite">
          <div className="spinner small" />
          <div><strong>{status?.step || 'Working'}</strong>
            <p className="muted small">{status?.status}{status?.tokens ? ` · ${status.tokens} tokens` : ''}</p></div>
        </div>
      )}
      {error && <p className="error">{error}</p>}

      <div className="btn-row" style={{ marginBottom: 12 }}>
        {beats.length === 0 ? (
          <button className="primary" disabled={busy} onClick={() => run('beat-director', { actIndex: ai, sceneIndex: si })}>
            Generate beats
          </button>
        ) : (
          <button className="primary" disabled={busy} onClick={() => run('auto-write-scene', { actIndex: ai, sceneIndex: si })}>
            Auto-write all beats
          </button>
        )}
      </div>

      {beats.map((b, bi) => {
        const text = beatText(bi);
        const typeClass = BEAT_TYPE_CLASS[b.type] || '';
        return (
          <section key={bi} className="card beat-card">
            <div className="page-head">
              <div className="beat-badges">
                <span className={`beat-type ${typeClass}`}>{b.type}</span>
                <span className="beat-meta">
                  <span title={`Pacing: ${PACING_LABEL[b.pacing] ?? 'Balanced'}`}>{PACING_GLYPH[b.pacing] ?? '➖'}</span>
                  <span className={`valence v${b.valence >= 0 ? 'pos' : 'neg'}`}>{b.valence > 0 ? `+${b.valence}` : b.valence}</span>
                </span>
              </div>
              <button className="ghost small" disabled={busy} onClick={() => run('draft-edit', { actIndex: ai, sceneIndex: si, beatIndex: bi })}>
                {text ? 'Regenerate' : 'Write'}
              </button>
            </div>
            <p className="muted small">Beat {b.number}: {b.description}{b.emotional_shift ? ` — ${b.emotional_shift}` : ''}</p>
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
    </div>
  );
}
