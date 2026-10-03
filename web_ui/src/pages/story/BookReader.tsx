// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web book reader: a paper, two-margin, CSS-columns paginated book with
// prev/next, keyboard flips, a Contents drawer, reading-progress persistence
// (last_read_page_index), continuous "Read aloud" scene narration, and the
// page-turn sound when ambient sound is on. The bar above it is the shared
// ReaderBar. A clean web reader — it does not pixel-match the Flutter
// CustomPageFlip.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { StoryProject } from '../../storyTypes';
import { ChevronLeftIcon, ChevronRightIcon } from './icons';
import { splitParagraphs } from './paragraphs';
import { ReaderBar, ReaderStatus, type ReaderChrome } from './ReaderBar';
import { TocDrawer } from './TocDrawer';
import { bookTocEntries } from './tocEntries';
import { useBookPages } from './useBookPages';
import { useSceneNarration } from './useSceneNarration';

export function BookReader({ id, project, chrome }: { id: string; project: StoryProject; chrome: ReaderChrome }) {
  const flowRef = useRef<HTMLDivElement | null>(null);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const [page, setPage] = useState(0);
  const [tocOpen, setTocOpen] = useState(false);
  const restoredRef = useRef(false);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // The page-turn sound follows the ambient switch, like the desktop's.
  const soundRef = useRef(chrome.ambient.on);
  useEffect(() => { soundRef.current = chrome.ambient.on; }, [chrome.ambient.on]);

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
    if (!soundRef.current) return;
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

  // Read aloud starts at the scene on the page in view, like the desktop starts at the current page.
  const sceneInView = () => {
    let at = 0;
    proseScenes.forEach((s, i) => {
      const start = anchors[`scene:${s.ai}-${s.si}`];
      if (start !== undefined && start <= page) at = i;
    });
    return at;
  };

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

  // Persist reading progress (debounced, no reload). Only the page goes up —
  // posting the whole project here overwrote anything the desktop wrote to the
  // story after this reader loaded it.
  useEffect(() => {
    if (!restoredRef.current) return;
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      api
        .post(`/api/stories/${id}/reading-position`, { page })
        .catch((e) => console.warn('[story] reading position not saved', e));
    }, 900);
    return () => { if (saveTimer.current) clearTimeout(saveTimer.current); };
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

  const entries = bookTocEntries(project, anchors, page, goTo);

  return (
    <div>
      <ReaderBar chrome={chrome} where={`Page ${page + 1} of ${totalPages}`}
        reading={narration.reading} canRead={proseScenes.length > 0}
        onRead={() => { void narration.start(sceneInView()); }} onStop={narration.stop}
        onContents={() => setTocOpen(true)} />
      <ReaderStatus chrome={chrome} narration={narration} />

      <div className="s-reader-book">
        <div className="book-wrap">
          <div className="book-page" ref={viewportRef}>
            <div className="book-flow" ref={flowRef}
              style={{ transform: `translateX(-${page * stride}px)` }}>
              <div className="book-cover" data-anchor="title">
                <h1>{project.title}</h1>
                <p className="byline">A Porch Story</p>
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
                          {splitParagraphs(text).map((para, pi) => <p key={pi}>{para}</p>)}
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
      </div>

      <div className="s-pager">
        <div className="s-pager-prog">
          <i style={{ width: `${totalPages > 1 ? Math.round((page / (totalPages - 1)) * 100) : 100}%` }} />
        </div>
        <div className="s-pager-pill">
          <button type="button" className="s-btn-ico ghost" data-testid="reader-prev-page" aria-label="Previous page"
            disabled={page <= 0} onClick={() => goTo(page - 1)}><ChevronLeftIcon /></button>
          <span className="s-pager-ind">Page {page + 1} / {totalPages}</span>
          <button type="button" className="s-btn-ico ghost" data-testid="reader-next-page" aria-label="Next page"
            disabled={page >= totalPages - 1} onClick={() => goTo(page + 1)}><ChevronRightIcon /></button>
        </div>
      </div>

      {tocOpen && <TocDrawer title={project.title} entries={entries} onClose={() => setTocOpen(false)} />}
    </div>
  );
}
