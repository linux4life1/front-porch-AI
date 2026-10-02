// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scroll mode: one continuous column with a heading per chapter (a scene
// with prose), resuming where the reader left off; a tap in the middle hides
// the controls; chapter buttons and Read aloud at the bottom. Mirrors the
// desktop reader's scroll mode.

import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { api } from '../../api/client';
import type { StoryProject } from '../../storyTypes';
import { orderedScenes, sceneText } from './storyShape';
import { useSceneNarration } from './useSceneNarration';

const ORDINALS = ['ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN',
  'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN', 'SIXTEEN', 'SEVENTEEN', 'EIGHTEEN', 'NINETEEN', 'TWENTY'];

export function ScrollReader({ id, project, bar }: { id: string; project: StoryProject; bar: ReactNode }) {
  const [hud, setHud] = useState(true);
  const [chapter, setChapter] = useState(0);
  const refs = useRef<(HTMLDivElement | null)[]>([]);
  const restored = useRef(false);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const chapters = useMemo(
    () => orderedScenes(project).filter((r) => sceneText(project, r.act, r.index)),
    [project],
  );
  const narration = useSceneNarration(
    id,
    chapters.map((r) => ({ ai: r.act, si: r.index })),
    (ai, si) => {
      const i = chapters.findIndex((r) => r.act === ai && r.index === si);
      refs.current[i]?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    },
  );

  // Resume, then keep the position (debounced) as the reader scrolls.
  useEffect(() => {
    if (restored.current) return;
    restored.current = true;
    const max = document.documentElement.scrollHeight - window.innerHeight;
    if (max > 0 && project.reader_scroll) window.scrollTo(0, (project.reader_scroll ?? 0) * max);
  }, [project.reader_scroll]);

  useEffect(() => {
    const onScroll = () => {
      let visible = 0;
      refs.current.forEach((el, i) => { if (el && el.getBoundingClientRect().top <= 160) visible = i; });
      setChapter(visible);
      if (saveTimer.current) clearTimeout(saveTimer.current);
      saveTimer.current = setTimeout(() => {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        const scroll = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
        api.post(`/api/stories/${id}/reading-position`, { scroll }).catch(() => {});
      }, 800);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => { window.removeEventListener('scroll', onScroll); if (saveTimer.current) clearTimeout(saveTimer.current); };
  }, [id]);

  const jump = (i: number) => refs.current[i]?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  const toggleHud = (e: React.MouseEvent<HTMLDivElement>) => {
    const w = window.innerWidth;
    if (e.clientX > w * 0.3 && e.clientX < w * 0.7 && (e.target as HTMLElement).tagName !== 'BUTTON') setHud((h) => !h);
  };

  return (
    <div className="story-reader">
      {hud && bar}
      <div className="s-scroll" onClick={toggleHud} data-testid="scroll-reader">
        {chapters.map((r, i) => (
          <div key={r.scene.id ?? `${r.act}-${r.index}`} ref={(el) => { refs.current[i] = el; }}>
            <div className="ch-eyebrow">CHAPTER {ORDINALS[i] ?? i + 1}</div>
            <div className="ch-title">{r.scene.title}</div>
            {sceneText(project, r.act, r.index).split(/\n\n+/).map((para, pi) => <p key={pi}>{para.trim()}</p>)}
          </div>
        ))}
        {chapters.length === 0 && <p className="muted">Nothing written yet.</p>}
      </div>
      {hud && (
        <div className="s-scroll-bar">
          <button className="s-btn-ghost" disabled={chapter <= 0} onClick={() => jump(chapter - 1)}>◀ Ch. {chapter}</button>
          <button className="s-btn-quiet" disabled={chapters.length === 0}
            onClick={() => (narration.reading ? narration.stop() : narration.start(chapter))}>
            {narration.reading ? '⏹ Stop' : '▶ Read aloud'}
          </button>
          <button className="s-btn-ghost" disabled={chapter >= chapters.length - 1} onClick={() => jump(chapter + 1)}>Ch. {chapter + 2} ▶</button>
          <span className="muted small" style={{ alignSelf: 'center' }}>Ch. {chapter + 1} of {chapters.length}</span>
        </div>
      )}
    </div>
  );
}
