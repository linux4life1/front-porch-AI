// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat page's weather canvas (docs/design/ambient-stage.md, PR 2): a new
// poll of the same scene, new colours or a flipped pause switch reach the
// running player instead of scattering the rain again; only a new seed or
// effects spec does.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { SceneEffectsCanvas } from './SceneEffectsCanvas';

const players: { seed: number; paints: unknown[]; pause: boolean[]; generating: boolean[]; disposed: boolean }[] = [];

vi.mock('../../theme/sceneEffectsPlayer', () => ({
  SceneEffectsPlayer: class {
    private readonly rec;
    constructor(_canvas: unknown, wire: { seed: number; pauseWhileGenerating: boolean; effects: { paints: unknown } }) {
      this.rec = { seed: wire.seed, paints: [wire.effects.paints], pause: [wire.pauseWhileGenerating], generating: [] as boolean[], disposed: false };
      players.push(this.rec);
    }
    setPaints(p: unknown) { this.rec.paints.push(p); }
    setPauseWhileGenerating(on: boolean) { this.rec.pause.push(on); }
    setGenerating(on: boolean) { this.rec.generating.push(on); }
    resize() {}
    dispose() { this.rec.disposed = true; }
  },
}));

const darkPaints = {
  rain: 'rgba(200, 215, 235, 0.549)', snow: 'rgba(255, 255, 255, 0.902)', cloud: 'rgba(140, 150, 162, 0.4)',
  fog: 'rgba(169, 177, 187, 0.306)', fogClear: 'rgba(169, 177, 187, 0.0)', flash: 'rgba(240, 244, 255, 0.6)',
};

function scene(o: { seed?: number; pause?: boolean; rain?: string; clouds?: number } = {}) {
  const paints = { ...darkPaints, rain: o.rain ?? darkPaints.rain };
  return {
    level: 'effects',
    seed: o.seed ?? 42,
    pauseWhileGenerating: o.pause ?? true,
    effects: { kind: 'rain', density: 0.00035, clouds: o.clouds ?? 6, fog: false, lightning: false, wind: 0.18 },
    dark: { paints },
    light: { paints },
  };
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

const show = (s: unknown, generating = false) =>
  act(() => root.render(createElement(SceneEffectsCanvas, { scene: s, generating })));

it('keeps the running weather through a poll, new colours and the pause switch', () => {
  show(scene());
  expect(players).toHaveLength(1);
  show(scene());
  show(scene({ rain: 'rgba(75, 91, 110, 0.451)' }));
  show(scene({ rain: 'rgba(75, 91, 110, 0.451)', pause: false }));
  show(scene({ rain: 'rgba(75, 91, 110, 0.451)', pause: false }), true);
  expect(players).toHaveLength(1);
  const p = players[0];
  expect(p.disposed).toBe(false);
  expect(p.paints.at(-1)).toMatchObject({ rain: 'rgba(75, 91, 110, 0.451)' });
  expect(p.pause.at(-1)).toBe(false);
  expect(p.generating.at(-1)).toBe(true);
});

it('scatters again for a new seed or a new spec', () => {
  show(scene());
  show(scene({ seed: 43 }));
  expect(players).toHaveLength(2);
  expect(players[0].disposed).toBe(true);
  expect(players[1].seed).toBe(43);
  show(scene({ seed: 43, clouds: 9 }));
  expect(players).toHaveLength(3);
});
