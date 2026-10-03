// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the Contents drawer lists. In Book it is the title page, each act and
// each scene that has prose, with the page it starts on; in Scroll it is the
// same list with chapters instead of pages, and an entry scrolls to its
// chapter. An entry with nothing to go to (an act without prose) is not
// tappable.

import type { StoryProject } from '../../storyTypes';
import type { SceneRef } from './storyShape';

export interface TocEntry {
  key: string;
  label: string;
  kind: 'title' | 'act' | 'scene';
  /** The page or chapter number on the right; '' for none. */
  num: number | '';
  current: boolean;
  /** Null when there is nowhere to go. */
  onPick: (() => void) | null;
}

const sceneTitle = (r: { scene: { title: string; number: number } }) => r.scene.title || `Scene ${r.scene.number}`;

/** Book: every entry points at the page its anchor landed on. */
export function bookTocEntries(
  p: StoryProject, anchors: Record<string, number>, currentPage: number, goTo: (page: number) => void,
): TocEntry[] {
  const entry = (key: string, label: string, kind: TocEntry['kind'], page: number): TocEntry => ({
    key, label, kind, num: page + 1, current: page === currentPage, onPick: () => goTo(page),
  });
  return [
    entry('title', 'Title Page', 'title', anchors['title'] ?? 0),
    ...p.acts.flatMap((act, ai) => [
      entry(`act-${ai}`, `Act ${act.number}: ${act.title}`, 'act', anchors[`act:${ai}`] ?? 0),
      ...(p.scenes[String(ai)] ?? []).flatMap((scene, si) => {
        const page = anchors[`scene:${ai}-${si}`];
        return page === undefined ? [] : [entry(`scene-${ai}-${si}`, sceneTitle({ scene }), 'scene', page)];
      }),
    ]),
  ];
}

/** Scroll: the chapters are the scenes with prose; an act goes to its first chapter. */
export function scrollTocEntries(
  p: StoryProject, chapters: SceneRef[], currentChapter: number, goToChapter: (index: number) => void, toTop: () => void,
): TocEntry[] {
  return [
    { key: 'title', label: 'Title Page', kind: 'title', num: '', current: false, onPick: toTop },
    ...p.acts.flatMap((act, ai) => {
      const inAct = chapters.map((r, i) => ({ r, i })).filter(({ r }) => r.act === ai);
      return [
        {
          key: `act-${ai}`, label: `Act ${act.number}: ${act.title}`, kind: 'act' as const, num: '' as const, current: false,
          onPick: inAct.length > 0 ? () => goToChapter(inAct[0].i) : null,
        },
        ...inAct.map(({ r, i }) => ({
          key: `chapter-${i}`, label: sceneTitle(r), kind: 'scene' as const, num: i + 1, current: i === currentChapter,
          onPick: () => goToChapter(i),
        })),
      ];
    }),
  ];
}
