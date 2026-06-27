// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web book reader: a paper, two-margin, CSS-columns paginated book with
// prev/next, keyboard flips, a Table of Contents, reading-progress persistence
// (last_read_page_index), continuous "Read to me" scene narration, and optional
// ambient + page-turn audio (gracefully omitted if the assets aren't served).
// A clean web reader — it does not pixel-match the Flutter CustomPageFlip.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../../api/client';
import type { StoryProject } from '../../storyTypes';
import { useBookPages } from './useBookPages';
import { useSceneNarration } from './useSceneNarration';
import { TocDrawer } from './TocDrawer';

export function BookReader({ id, project }: { id: string; project: StoryProject }) {
  const navigate = useNavigate();
  const flowRef = useRef<HTMLDivElement | null>(null);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const [page, setPage] = useState(0);
  const [tocOpen, setTocOpen] = useState(false);
  const [ambientOn, setAmbientOn] = useState(false);
  const [ambientOk, setAmbientOk] = useState(true);
  const ambientRef = useRef<HTMLAudioElement | null>(null);
  const restoredRef = useRef(false);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const sceneProse = useCallback((ai: number, si: number): string => {
    const beats = project.beats[`${ai}-${si}`] ?? [];
    return beats
      .map((_, bi) => project.prose[`${ai}-${si}-${bi}`]?.final || project.prose[`${ai}-${si}-${bi}`]?.draft || '')
      .filter(Boolean)
      .join('\n\n');
  }, [project]);

  const proseScenes = useMemo(() => {
    const out: { ai: number; si: number }[] = [];
    project.acts.forEach((_, ai) => {
      (project.scenes[String(ai)] ?? []).forEach((_, si) => {
        if (sceneProse(ai, si)) out.push({ ai, si });
      });
    });
    return out;
  }, [project, sceneProse]);

  const signature = `${id}:${project.updated_at}:${proseScenes.length}`;
  const { totalPages, stride, anchors } = useBookPages(flowRef, viewportRef, signature);

  // Keep latest anchors for the narration jump callback (stable identity).
  const anchorsRef = useRef(anchors);
  anchorsRef.current = anchors;

  const playPageTurn = () => {
    try {
      const a = new Audio('/audio/page_turn.wav');
      a.volume = 0.5;
      void a.play().catch(() => {});
    } catch { /* asset not served — silent */ }
  };

  const goTo = useCallback((p: number) => {
    setPage((cur) => {
      const next = Math.max(0, Math.min(p, Math.max(0, totalPages - 1)));
      if (next !== cur) playPageTurn();
      return next;
    });
  }, [totalPages]);

  const jumpToScene = useCallback((ai: number, si: number) => {
    const pg = anchorsRef.current[`scene:${ai}-${si}`];
    if (pg !== undefined) goTo(pg);
  }, [goTo]);

  const narration = useSceneNarration(id, proseScenes, jumpToScene);

  // Restore saved reading position once the layout is known.
  useEffect(() => {
    if (restoredRef.current || totalPages <= 1) return;
    restoredRef.current = true;
    const saved = project.last_read_page_index || 0;
    if (saved > 0) setPage(Math.min(saved, totalPages - 1));
  }, [totalPages, project.last_read_page_index]);

  // Clamp if the page count shrank (resize / content change).
  useEffect(() => {
    setPage((p) => Math.min(p, Math.max(0, totalPages - 1)));
  }, [totalPages]);

  // Persist reading progress (debounced, fire-and-forget — no reload).
  useEffect(() => {
    if (!restoredRef.current) return;
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      api.post(`/api/stories/${id}`, { ...project, last_read_page_index: page }).catch(() => {});
    }, 900);
    return () => { if (saveTimer.current) clearTimeout(saveTimer.current); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, id]);

  // Keyboard flips.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') goTo(page + 1);
      else if (e.key === 'ArrowLeft') goTo(page - 1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [page, goTo]);

  const toggleAmbient = () => {
    const next = !ambientOn;
    setAmbientOn(next);
    const a = ambientRef.current;
    if (!a) return;
    if (next) { a.volume = 0.3; void a.play().catch(() => setAmbientOk(false)); }
    else a.pause();
  };

  return (
    <div className="story-reader">
      <div className="reader-bar">
        <button className="ghost" onClick={() => navigate(`/stories/${id}`)}>← {project.title}</button>
        <h2>{project.title}</h2>
        {proseScenes.length > 0 && (
          narration.reading ? (
            <button className="icon-btn on" title="Stop reading" onClick={narration.stop}>⏹</button>
          ) : (
            <button className="icon-btn" title="Read to me" onClick={() => narration.start(0)}>🔊</button>
          )
        )}
        {ambientOk && (
          <button className={`icon-btn${ambientOn ? ' on' : ''}`} title="Ambient sound"
            onClick={toggleAmbient}>{ambientOn ? '🎵' : '🔇'}</button>
        )}
        <button className="icon-btn" title="Contents" onClick={() => setTocOpen(true)}>☰</button>
      </div>

      {narration.reading && (
        <div className="read-status">
          <span>Reading scene {narration.current + 1} of {narration.total}</span>
          {narration.buffering && <span className="read-buf">buffering…</span>}
        </div>
      )}

      <div className="book-wrap">
        <div className="book-page" ref={viewportRef}>
          <div className="book-flow" ref={flowRef}
            style={{ transform: `translateX(-${page * stride}px)` }}>
            <div className="book-cover" data-anchor="title">
              <h1>{project.title}</h1>
              <p className="byline">A story by Front Porch AI</p>
              {project.concept && <p className="concept">{project.concept}</p>}
            </div>

            {project.acts.map((act, ai) => {
              const scenes = project.scenes[String(ai)] ?? [];
              return (
                <div key={ai} style={{ display: 'contents' }}>
                  <div className="book-act" data-anchor={`act:${ai}`}>
                    <span className="act-kicker">Act {act.number}</span>
                    {act.title && <h2>{act.title}</h2>}
                    {act.description && <p className="act-desc">{act.description}</p>}
                  </div>
                  {scenes.map((sc, si) => {
                    const text = sceneProse(ai, si);
                    if (!text) return null;
                    return (
                      <div key={si} className="book-scene" data-anchor={`scene:${ai}-${si}`}>
                        <div className="scene-h">
                          <h3>{sc.title || `Scene ${sc.number}`}</h3>
                          {sc.location && <div className="scene-loc">{sc.location}</div>}
                        </div>
                        {text.split(/\n\n+/).map((para, pi) => <p key={pi}>{para}</p>)}
                      </div>
                    );
                  })}
                </div>
              );
            })}

            <div className="book-end" data-anchor="end">
              <h2>The End</h2>
              <p>— {project.title} —</p>
            </div>
          </div>
        </div>
      </div>

      <div className="reader-foot">
        <button className="ghost reader-nav-btn" disabled={page <= 0} onClick={() => goTo(page - 1)}>‹</button>
        <div className="reader-prog">
          <span style={{ width: `${totalPages > 1 ? Math.round((page / (totalPages - 1)) * 100) : 0}%` }} />
        </div>
        <span className="page-ind">Page {page + 1} / {totalPages}</span>
        <button className="ghost reader-nav-btn" disabled={page >= totalPages - 1} onClick={() => goTo(page + 1)}>›</button>
      </div>

      {/* Ambient loop (muted until the user enables it — satisfies autoplay). */}
      <audio ref={ambientRef} loop preload="none" src="/audio/ambient_reading.wav"
        onError={() => setAmbientOk(false)} />

      {tocOpen && (
        <TocDrawer project={project} anchors={anchors} currentPage={page}
          onJump={goTo} onClose={() => setTocOpen(false)} />
      )}
    </div>
  );
}
