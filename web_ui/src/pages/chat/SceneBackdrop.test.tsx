// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Setting place's picture behind the chat (SceneBackdrop, the desktop
// SceneBackdropLayer's twin). jsdom has no 2D canvas, so what runs here is
// the no-canvas fallback (two <img> layers that dissolve) and the parts
// shared with the canvas path: the wire parser, the title card, nothing
// painted for a chat without a picture. The move itself is pinned by
// sceneBackdropTransition.test.ts.
//
// Rewritten with the canvas backdrop: the earlier component was the two
// <img> layers alone; those are now the fallback, and the title card is new.

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { SCENE_BACKDROP_TRANSITION_MS, SceneBackdrop, parseSceneBackdrop } from './SceneBackdrop';

let host: HTMLDivElement;
let root: Root;
let reduce = false;

beforeEach(() => {
  vi.useFakeTimers();
  reduce = false;
  window.matchMedia = ((query: string) =>
    ({ matches: reduce && query.includes('reduce'), media: query } as MediaQueryList)) as typeof window.matchMedia;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.useRealTimers();
});

const tea = { placeId: 'tea', placeName: 'Tea Rooms', url: '/api/worlds/cover?id=tea&v=1', condition: 'rain' };
const square = { placeId: 'square', placeName: 'The Square', url: '/api/worlds/cover?id=square&v=7', condition: 'storm' };

function show(backdrop: typeof tea | null) {
  act(() => root.render(createElement(SceneBackdrop, { backdrop })));
}

const pictures = () => Array.from(host.querySelectorAll<HTMLImageElement>('img.scene-backdrop-img'));

it('shows the first picture at once, with its veil and tint over it, and no card', () => {
  show(tea);
  const imgs = pictures();
  expect(imgs.map((i) => i.getAttribute('src'))).toEqual([tea.url]);
  expect(imgs[0].classList.contains('is-arriving')).toBe(false);
  expect(host.querySelector('.scene-backdrop-veil')).not.toBeNull();
  expect(host.querySelector('.scene-backdrop-tint')).not.toBeNull();
  expect(host.querySelector('.scene-backdrop')?.getAttribute('aria-hidden')).toBe('true');
  expect(host.querySelector('.scene-move-title')).toBeNull();
});

it('a move keeps the old picture under the new one and names the place, then settles', () => {
  show(tea);
  show(square);
  const during = pictures();
  expect(during.map((i) => i.getAttribute('src'))).toEqual([tea.url, square.url]);
  expect(during[0].classList.contains('is-leaving')).toBe(true);
  expect(during[1].classList.contains('is-arriving')).toBe(true);
  expect(host.querySelector('.scene-move-title')?.textContent).toBe('The Square');
  act(() => { vi.advanceTimersByTime(SCENE_BACKDROP_TRANSITION_MS + 1); });
  expect(pictures().map((i) => i.getAttribute('src'))).toEqual([square.url]);
  expect(host.querySelector('.scene-move-title')).toBeNull();
});

it('a re-saved picture of the same place moves too', () => {
  show(tea);
  show({ ...tea, url: '/api/worlds/cover?id=tea&v=2' });
  expect(pictures()).toHaveLength(2);
  act(() => { vi.advanceTimersByTime(SCENE_BACKDROP_TRANSITION_MS + 1); });
  expect(pictures()).toHaveLength(1);
});

it('reduced motion swaps the picture at once and still names it', () => {
  reduce = true;
  show(tea);
  show(square);
  expect(pictures().map((i) => i.getAttribute('src'))).toEqual([square.url]);
  expect(host.querySelector('.scene-move-title.is-still')?.textContent).toBe('The Square');
});

it('a chat without a place picture paints nothing', () => {
  show(tea);
  show(null);
  expect(host.querySelector('.scene-backdrop')).toBeNull();
});

it('parses only a wire that names the place and a relay URL, with the weather', () => {
  expect(parseSceneBackdrop(tea)).toEqual(tea);
  expect(parseSceneBackdrop({ placeId: 'x', placeName: 'X', url: '/api/worlds/cover?id=x&v=1' })?.condition).toBeNull();
  expect(parseSceneBackdrop(null)).toBeNull();
  expect(parseSceneBackdrop({ placeId: 'x', url: 'https://elsewhere/x.png' })).toBeNull();
});
