// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Setting place's picture behind the chat (SceneBackdrop, the desktop
// SceneBackdropLayer's twin): the first picture shows at once, a move to
// another place keeps the old picture leaving under the new one arriving
// until the dissolve is over, a re-saved picture of the same place dissolves
// too, reduced motion swaps at once, and a chat without one paints nothing.

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

const tea = { placeId: 'tea', placeName: 'Tea Rooms', url: '/api/worlds/cover?id=tea&v=1' };
const square = { placeId: 'square', placeName: 'The Square', url: '/api/worlds/cover?id=square&v=7' };

function show(backdrop: typeof tea | null) {
  act(() => root.render(createElement(SceneBackdrop, { backdrop })));
}

const pictures = () => Array.from(host.querySelectorAll<HTMLImageElement>('img.scene-backdrop-img'));

it('shows the first picture at once, with its veil and tint over it', () => {
  show(tea);
  const imgs = pictures();
  expect(imgs.map((i) => i.getAttribute('src'))).toEqual([tea.url]);
  expect(imgs[0].classList.contains('is-arriving')).toBe(false);
  expect(host.querySelector('.scene-backdrop-veil')).not.toBeNull();
  expect(host.querySelector('.scene-backdrop-tint')).not.toBeNull();
  expect(host.querySelector('.scene-backdrop')?.getAttribute('aria-hidden')).toBe('true');
});

it('dissolves on a move: the old picture leaves under the new one, then goes', () => {
  show(tea);
  show(square);
  const during = pictures();
  expect(during.map((i) => i.getAttribute('src'))).toEqual([tea.url, square.url]);
  expect(during[0].classList.contains('is-leaving')).toBe(true);
  expect(during[1].classList.contains('is-arriving')).toBe(true);
  act(() => { vi.advanceTimersByTime(SCENE_BACKDROP_TRANSITION_MS + 1); });
  expect(pictures().map((i) => i.getAttribute('src'))).toEqual([square.url]);
});

it('a re-saved picture of the same place dissolves too', () => {
  show(tea);
  show({ ...tea, url: '/api/worlds/cover?id=tea&v=2' });
  expect(pictures()).toHaveLength(2);
  act(() => { vi.advanceTimersByTime(SCENE_BACKDROP_TRANSITION_MS + 1); });
  expect(pictures()).toHaveLength(1);
});

it('reduced motion swaps the picture at once', () => {
  reduce = true;
  show(tea);
  show(square);
  expect(pictures().map((i) => i.getAttribute('src'))).toEqual([square.url]);
});

it('a chat without a place picture paints nothing', () => {
  show(tea);
  show(null);
  expect(host.querySelector('.scene-backdrop')).toBeNull();
});

it('parses only a wire that names the place and a relay URL', () => {
  expect(parseSceneBackdrop(tea)).toEqual(tea);
  expect(parseSceneBackdrop(null)).toBeNull();
  expect(parseSceneBackdrop({ placeId: 'x', url: 'https://elsewhere/x.png' })).toBeNull();
  expect(parseSceneBackdrop({ placeId: 'x', url: '/api/worlds/cover?id=x&v=1' })?.placeName).toBe('');
});
