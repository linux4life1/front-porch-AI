// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scroll mode (sketch P): one continuous column with a heading per chapter (a
// scene with prose), resuming where the reader left off. A tap in the middle of
// the screen hides the bars; the chapter buttons sit at the bottom, Read aloud
// in the bar above. Web twin of story_reader_page.scroll.dart.
//
// The page scrolls inside the app's own container, not the window, so the
// position is read from and written to that container.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { StoryProject } from '../../storyTypes';
import { ChevronLeftIcon, ChevronRightIcon } from './icons';
import { splitParagraphs } from './paragraphs';
import { ReaderBar, ReaderStatus, type ReaderChrome } from './ReaderBar';
import { scrollParent } from './scrollParent';
import { orderedScenes, sceneText } from './storyShape';
import { TocDrawer } from './TocDrawer';
import { scrollTocEntries } from './tocEntries';
import { useSceneNarration } from './useSceneNarration';

const ORDINALS = ['ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN',
  'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN', 'SIXTEEN', 'SEVENTEEN', 'EIGHTEEN', 'NINETEEN', 'TWENTY'];

export function ScrollReader({ id, project, chrome }: { id: string; project: StoryProject; chrome: ReaderChrome }) {
  const [hud, setHud] = useState(true);
  const [chapter, setChapter] = useState(0);
  const [percent, setPercent] = useState(0);
  const [tocOpen, setTocOpen] = useState(false);
  const root = useRef<HTMLDivElement | null>(null);
  const refs = useRef<(HTMLDivElement | null)[]>([]);
  const restored = useRef(false);

  const chapters = useMemo(
    () => orderedScenes(project).filter((r) => sceneText(project, r.act, r.index)),
    [project],
  );
  const narrationScenes = useMemo(() => chapters.map((r) => ({ ai: r.act, si: r.index })), [chapters]);

  const jump = useCallback((i: number) => {
    refs.current[i]?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }, []);
  const onNarrationJump = useCallback((ai: number, si: number) => {
    jump(chapters.findIndex((r) => r.act === ai && r.index === si));
  }, [chapters, jump]);
  const narration = useSceneNarration(id, narrationScenes, onNarrationJump);

  // Resume once, then follow the reader: the chapter in view, how far down, and (debounced) the saved position.
  const savedScroll = project.reader_scroll ?? 0;
  useEffect(() => {
    const scroller = scrollParent(root.current);
    if (!scroller) return;
    const target: EventTarget = scroller === document.scrollingElement ? window : scroller;
    const room = () => scroller.scrollHeight - scroller.clientHeight;
    const track = () => {
      const top = scroller === document.scrollingElement ? 0 : scroller.getBoundingClientRect().top;
      let visible = 0;
      refs.current.forEach((el, i) => { if (el && el.getBoundingClientRect().top <= top + 160) visible = i; });
      setChapter(visible);
      const fraction = room() > 0 ? Math.min(1, Math.max(0, scroller.scrollTop / room())) : 0;
      setPercent(Math.round(fraction * 100));
      return fraction;
    };
    if (!restored.current) {
      restored.current = true;
      if (savedScroll > 0 && room() > 0) scroller.scrollTop = savedScroll * room();
      track();
    }
    let timer: ReturnType<typeof setTimeout> | undefined;
    const onScroll = () => {
      const scroll = track();
      clearTimeout(timer);
      timer = setTimeout(() => {
        api.post(`/api/stories/${id}/reading-position`, { scroll })
          .catch((e) => console.warn('[story] reading position not saved', e));
      }, 800);
    };
    target.addEventListener('scroll', onScroll, { passive: true });
    return () => { target.removeEventListener('scroll', onScroll); clearTimeout(timer); };
  }, [id, savedScroll]);

  // A tap in the middle third hides or shows the bars (not while selecting text or tapping a control).
  const toggleHud = (e: React.MouseEvent<HTMLDivElement>) => {
    const w = window.innerWidth;
    if (e.clientX <= w * 0.3 || e.clientX >= w * 0.7) return;
    if ((e.target as HTMLElement).closest('button, a') || window.getSelection()?.toString()) return;
    setHud((h) => !h);
  };

  const toTop = () => scrollParent(root.current)?.scrollTo({ top: 0, behavior: 'smooth' });
  const entries = scrollTocEntries(project, chapters, chapter, jump, toTop);

  return (
    <div ref={root} className="s-reader-scroll">
      {hud && (
        <>
          <ReaderBar chrome={chrome} where={chapters.length > 0 ? `Ch. ${chapter + 1} · ${percent}%` : ''}
            reading={narration.reading} canRead={chapters.length > 0}
            onRead={() => { void narration.start(chapter); }} onStop={narration.stop} onContents={() => setTocOpen(true)} />
          <ReaderStatus chrome={chrome} narration={narration} />
        </>
      )}
      <div className="s-scroll" onClick={toggleHud} data-testid="scroll-reader">
        {chapters.map((r, i) => (
          <div key={r.scene.id ?? `${r.act}-${r.index}`} className="ch" ref={(el) => { refs.current[i] = el; }}>
            <div className="ch-eyebrow">CHAPTER {ORDINALS[i] ?? i + 1}</div>
            <div className="ch-title">{r.scene.title}</div>
            {splitParagraphs(sceneText(project, r.act, r.index)).map((para, pi) => <p key={pi}>{para}</p>)}
          </div>
        ))}
        {chapters.length === 0 && <p className="s-muted" style={{ textAlign: 'center' }}>Nothing written yet.</p>}
      </div>
      {hud && (
        <div className="s-scroll-bar" data-testid="scroll-nav">
          <button type="button" className="s-btn-ghost" disabled={chapter <= 0} onClick={() => jump(chapter - 1)}>
            <ChevronLeftIcon /> Ch. {chapter}
          </button>
          <button type="button" className="s-btn-ghost" disabled={chapter >= chapters.length - 1} onClick={() => jump(chapter + 1)}>
            Ch. {chapter + 2} <ChevronRightIcon />
          </button>
        </div>
      )}
      {tocOpen && <TocDrawer title={project.title} entries={entries} onClose={() => setTocOpen(false)} />}
    </div>
  );
}
