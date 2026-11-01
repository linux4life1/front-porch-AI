// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The sky's two canvases on the chat page: one player for a scene with a
// sky, handed both canvases; a new minute reaches the running player; the
// generating flag follows; nothing mounts without a sky; leaving disposes.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { SceneSkyCanvas, useSceneSky } from './SceneSkyCanvas';

const players: { minutes: number[]; attached: Record<string, boolean>; generating: boolean[]; disposed: boolean }[] = [];

vi.mock('../../theme/sceneSkyPlayer', () => ({
  SceneSkyPlayer: class {
    private readonly rec;
    constructor(wire: { minute: number }) {
      this.rec = { minutes: [wire.minute], attached: {} as Record<string, boolean>, generating: [] as boolean[], disposed: false };
      players.push(this.rec);
    }
    attach(layer: string, canvas: unknown) { this.rec.attached[layer] = canvas !== null; }
    setScene(wire: { minute: number }) { this.rec.minutes.push(wire.minute); }
    setGenerating(on: boolean) { this.rec.generating.push(on); }
    resize() {}
    dispose() { this.rec.disposed = true; }
  },
}));

const paints = {
  scale: 1,
  stops: [{ at: 360, colour: '#f2a07b', alpha: 0.14 }, { at: 1350, colour: '#122a4a', alpha: 0.32 }],
  sunHigh: '#fff0c8', sunLow: '#ffb06a', moon: '#e8ecf6', moonGlow: '#dce4ff', star: '#ecf0ff', dawn: '#f2a07b', dusk: '#e8913f',
};

function scene(minute: number) {
  return {
    level: 'effects',
    pauseWhileGenerating: true,
    sky: { minute, moonPhase: 0.4, disc: 1, stars: 1, dark: paints, light: paints },
    dark: {},
    light: {},
  };
}

function Page({ scene: s, generating }: { scene: unknown; generating: boolean }) {
  const player = useSceneSky(s, generating);
  return createElement(
    'div',
    { className: 'chat-view' },
    createElement(SceneSkyCanvas, { player, layer: 'under' }),
    createElement('div', null, 'weather'),
    createElement(SceneSkyCanvas, { player, layer: 'over' }),
  );
}

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  players.length = 0;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
});

const render = (s: unknown, generating = false) => act(() => root.render(createElement(Page, { scene: s, generating })));

it('mounts nothing without a sky', () => {
  render({ level: 'effects', dark: {}, light: {} });
  expect(host.querySelectorAll('canvas')).toHaveLength(0);
  expect(players).toHaveLength(0);
});

it('one player draws both canvases, hears a new minute, and goes with the page', () => {
  render(scene(870));
  expect(players).toHaveLength(1);
  expect(host.querySelector('canvas.scene-sky')).not.toBeNull();
  expect(host.querySelector('canvas.scene-sky-discs')).not.toBeNull();
  expect(host.querySelector('.chat-view')?.classList.contains('has-scene-sky')).toBe(true);
  expect(players[0].attached).toEqual({ under: true, over: true });
  // The same scene again is a new object every poll; the player hears nothing.
  render(scene(870));
  expect(players[0].minutes).toEqual([870]);
  render(scene(1380));
  expect(players).toHaveLength(1);
  expect(players[0].minutes).toEqual([870, 1380]);
  render(scene(1380), true);
  expect(players[0].generating.at(-1)).toBe(true);
  render({ level: 'effects', dark: {}, light: {} });
  expect(players[0].disposed).toBe(true);
  expect(host.querySelectorAll('canvas')).toHaveLength(0);
  expect(host.querySelector('.chat-view')?.classList.contains('has-scene-sky')).toBe(false);
});
