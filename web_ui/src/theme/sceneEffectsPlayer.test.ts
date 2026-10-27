// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web stage's pause rules (docs/design/ambient-stage.md): the weather
// stops while a reply is generating only when the desktop's Pause effects
// while generating is on, holds still under prefers-reduced-motion, stops
// while the tab is hidden, paints each frame from the wire's colours, keeps
// to 30 fps on a 60 Hz display without a burst after a stall, builds no fog
// gradient per frame, and stacks clouds, fog, rain or snow, flash.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { SceneEffectsSim, parseSceneEffects, type SceneEffectsWire } from './sceneEffects';
import { SceneEffectsPlayer, paintSceneEffects } from './sceneEffectsPlayer';
import { MIST_LAYERS, MIST_SHARE, MIST_SPAN, mistBreath, mistShift } from './sceneFogMist';

const paints = {
  rain: 'rgba(200, 215, 235, 0.549)',
  snow: 'rgba(255, 255, 255, 0.902)',
  cloud: 'rgba(140, 150, 162, 0.4)',
  fog: 'rgba(169, 177, 187, 0.306)',
  fogClear: 'rgba(169, 177, 187, 0.0)',
  flash: 'rgba(240, 244, 255, 0.6)',
};

function wire(pauseWhileGenerating: boolean): SceneEffectsWire {
  return parseSceneEffects({
    level: 'effects',
    seed: 42,
    pauseWhileGenerating,
    effects: { kind: 'rain', density: 0.00035, clouds: 6, fog: false, lightning: true, wind: 0.42 },
    dark: { paints },
  }, 'dark')!;
}

/** A canvas with a recording 2D context; jsdom has no real one. */
function fakeCanvas() {
  const calls: string[] = [];
  const ctx = new Proxy({} as Record<string, unknown>, {
    get: (target, prop: string) => {
      if (prop in target) return target[prop];
      return (...args: unknown[]) => {
        calls.push(prop);
        if (prop === 'createRadialGradient') return { addColorStop: () => {} };
        return args.length ? undefined : undefined;
      };
    },
    set: (target, prop: string, value) => {
      target[prop] = value;
      calls.push(`${prop}=${String(value)}`);
      return true;
    },
  }) as unknown as CanvasRenderingContext2D;
  const canvas = {
    width: 0,
    height: 0,
    getBoundingClientRect: () => ({ width: 800, height: 600 }),
    getContext: () => ctx,
  } as unknown as HTMLCanvasElement;
  return { canvas, calls };
}

function mockReducedMotion(matches: boolean) {
  vi.stubGlobal('matchMedia', (query: string) => ({
    matches: query.includes('reduce') && matches,
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('scene effects player', () => {
  it('stops for a reply only when the pause switch is on', () => {
    mockReducedMotion(false);
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockReturnValue(1);
    const cancel = vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {});
    const on = new SceneEffectsPlayer(fakeCanvas().canvas, wire(true));
    expect(on.running).toBe(true);
    expect(raf).toHaveBeenCalled();
    on.setGenerating(true);
    expect(on.running).toBe(false);
    expect(cancel).toHaveBeenCalled();
    on.setGenerating(false);
    expect(on.running).toBe(true);
    on.dispose();

    const off = new SceneEffectsPlayer(fakeCanvas().canvas, wire(false));
    off.setGenerating(true);
    expect(off.running).toBe(true);
    off.dispose();
  });

  it('holds still under reduced motion and paints a still frame', () => {
    mockReducedMotion(true);
    const raf = vi.spyOn(window, 'requestAnimationFrame').mockReturnValue(1);
    const { canvas, calls } = fakeCanvas();
    const player = new SceneEffectsPlayer(canvas, wire(true));
    expect(player.running).toBe(false);
    expect(raf).not.toHaveBeenCalled();
    expect(calls).toContain('stroke');
    expect(canvas.width).toBeGreaterThan(0);
    player.dispose();
  });

  it('stops while the tab is hidden', () => {
    mockReducedMotion(false);
    vi.spyOn(window, 'requestAnimationFrame').mockReturnValue(1);
    vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    const player = new SceneEffectsPlayer(fakeCanvas().canvas, wire(true));
    expect(player.running).toBe(false);
    player.dispose();
  });

  // Changed with the render recipe (sceneEffectsRender.ts): the rain was
  // one stroke of every drop and a cloud one fill. Now the rain is streak
  // sprites, or, where the page cannot build them (jsdom here), lines in
  // a far sheet and three depth bands (four strokes, every drop drawn
  // twice); a cloud is a body and a lifted top (two fills); a flash adds
  // the bolt's glow and core (two more strokes).
  it('paints every shape from the wire colours, the rain in its depth bands', () => {
    const { canvas, calls } = fakeCanvas();
    const ctx = canvas.getContext('2d')!;
    const sim = new SceneEffectsSim(wire(true).effects, 42, 800, 600);
    sim.flash = 0.5;
    paintSceneEffects(ctx, sim, paints);
    expect(calls.filter((c) => c === 'stroke')).toHaveLength(6);
    expect(calls.filter((c) => c === 'lineTo').length).toBeGreaterThanOrEqual(sim.drops.length * 2);
    expect(calls).toContain(`strokeStyle=${paints.rain}`);
    expect(calls).toContain(`strokeStyle=${paints.flash}`);
    expect(calls).toContain(`fillStyle=${paints.cloud}`);
    expect(calls).toContain(`fillStyle=${paints.flash}`);
    expect(calls.filter((c) => c === 'fill')).toHaveLength(sim.clouds.length * 2);
    // The flash paints at its shaped strength, not the sim's raw decay.
    expect(calls).toContain('globalAlpha=0.85');
  });

  it('a still frame without a flash draws no bolt', () => {
    const { canvas, calls } = fakeCanvas();
    const ctx = canvas.getContext('2d')!;
    const sim = new SceneEffectsSim(wire(true).effects, 42, 800, 600);
    paintSceneEffects(ctx, sim, paints);
    expect(calls).not.toContain(`strokeStyle=${paints.flash}`);
    expect(calls.filter((c) => c === 'stroke')).toHaveLength(4);
  });

  it('paints every other frame on a 60 Hz display, and a stall does not burst', () => {
    mockReducedMotion(false);
    let next: FrameRequestCallback | null = null;
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      next = cb;
      return 1;
    });
    vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {});
    const { canvas, calls } = fakeCanvas();
    const player = new SceneEffectsPlayer(canvas, wire(false));
    const painted = () => calls.filter((c) => c === 'clearRect').length;
    const tick = (now: number) => (next as FrameRequestCallback | null)!(now);
    // Two 60 Hz periods sum to a hair under a 30 fps step, as a real
    // display's timestamps often do.
    let t = 1000;
    let before = painted();
    for (let i = 0; i < 60; i++, t += 16.666) tick(t);
    expect(painted() - before).toBeGreaterThanOrEqual(28);
    expect(painted() - before).toBeLessThanOrEqual(30);
    // After a stall of any length, 50 ms or five seconds, the frame back
    // paints once and the next one does not paint again.
    for (const gap of [50, 5000]) {
      t += gap;
      const perFrame: number[] = [];
      for (let i = 0; i < 6; i++, t += 16.666) {
        before = painted();
        tick(t);
        perFrame.push(painted() - before);
      }
      expect(perFrame[0]).toBe(1);
      for (let i = 1; i < perFrame.length; i++) {
        expect(perFrame[i] + perFrame[i - 1]).toBeLessThanOrEqual(1);
      }
    }
    player.dispose();
  });

  // Changed with the fog: it built one radial gradient per blob, and the
  // blobs are gone. The mist canvases follow the same rule: built once per
  // scatter and colour, never per frame.
  it('builds the fog mist once per scatter and colour, not per frame', () => {
    const { canvas, calls } = fakeCanvas();
    const ctx = canvas.getContext('2d')!;
    const made = mockMistCanvases();
    const fog = { ...wire(true).effects, kind: 'fog' as const, density: 0, clouds: 0, fog: true, lightning: false };
    const sim = new SceneEffectsSim(fog, 42, 800, 600);
    paintSceneEffects(ctx, sim, paints);
    expect(made()).toBe(MIST_LAYERS);
    sim.advance(1 / 30);
    paintSceneEffects(ctx, sim, paints);
    expect(made()).toBe(MIST_LAYERS);
    expect(calls.filter((c) => c === 'drawImage')).toHaveLength(MIST_LAYERS * 2 * 2);
    paintSceneEffects(ctx, sim, { ...paints, fog: 'rgba(201, 206, 211, 0.702)' });
    expect(made()).toBe(MIST_LAYERS * 2);
  });

  it('takes new colours and the pause switch without scattering again', () => {
    mockReducedMotion(false);
    vi.spyOn(window, 'requestAnimationFrame').mockReturnValue(1);
    vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {});
    const { canvas, calls } = fakeCanvas();
    const player = new SceneEffectsPlayer(canvas, wire(false));
    player.setGenerating(true);
    expect(player.running).toBe(true);
    player.setPauseWhileGenerating(true);
    expect(player.running).toBe(false);
    // Stopped, so the new colours repaint the still frame at once.
    const light = { ...paints, rain: 'rgba(75, 91, 110, 0.451)' };
    player.setPaints(light);
    expect(calls).toContain(`strokeStyle=${light.rain}`);
    player.dispose();
  });

  it('paints in the desktop\'s stack order: clouds, fog, rain, flash', () => {
    const { canvas, calls } = fakeCanvas();
    const ctx = canvas.getContext('2d')!;
    // Changed with the fog: it was found by its blobs' translates and is
    // now the mist's image draws. Only the mist gets working canvases, so
    // the rain still draws its lines and its strokes mark it.
    mockMistCanvases(MIST_LAYERS);
    const storm = { ...wire(true).effects, fog: true };
    const sim = new SceneEffectsSim(storm, 42, 800, 600);
    sim.flash = 0.5;
    paintSceneEffects(ctx, sim, paints);
    const cloudFill = calls.lastIndexOf('fill');
    const firstFog = calls.indexOf('drawImage');
    const lastFog = calls.lastIndexOf('drawImage');
    const rain = calls.indexOf('stroke');
    const flash = calls.indexOf(`fillStyle=${paints.flash}`);
    expect(sim.clouds.length).toBeGreaterThan(0);
    expect(sim.fogBlobs.length).toBeGreaterThan(0);
    expect(cloudFill).toBeGreaterThan(-1);
    expect(cloudFill).toBeLessThan(firstFog);
    expect(lastFog).toBeLessThan(rain);
    expect(rain).toBeLessThan(flash);
    expect(calls.lastIndexOf('fillRect')).toBeGreaterThan(flash);
  });
});

/** Stubs the first `limit` canvases the page makes with working fakes, for the mist; returns how many were made. */
function mockMistCanvases(limit = Infinity): () => number {
  let made = 0;
  const real = document.createElement.bind(document);
  vi.spyOn(document, 'createElement').mockImplementation(((tag: string) => {
    if (tag !== 'canvas' || made >= limit) return real(tag);
    made++;
    const g = new Proxy({} as Record<string, unknown>, {
      get: (target, prop: string) => {
        if (prop in target) return target[prop];
        if (prop === 'createImageData') return (w: number, h: number) => ({ data: new Uint8ClampedArray(w * h * 4) });
        return () => {};
      },
      set: (target, prop: string, value) => { target[prop] = value; return true; },
    });
    return { width: 0, height: 0, getContext: () => g } as unknown as HTMLCanvasElement;
  }) as typeof document.createElement);
  return () => made;
}

describe('scene effects fog mist', () => {
  // Soft blobs over a flat haze read as a plain grey background. Fog is two
  // mist layers, each a tile and its left neighbour, that stream right with
  // the sim's clock and breathe on their own phases. The desktop's
  // SceneFogLayer twin is pinned in ambient_stage_effects_test.
  it('streams two breathing layers of mist across the stage', () => {
    mockMistCanvases();
    const draws: { x: number; w: number; alpha: number }[] = [];
    const ctx = new Proxy({} as Record<string, unknown>, {
      get: (target, prop: string) => {
        if (prop === 'drawImage') {
          return (_img: unknown, x: number, _y: number, w: number) => draws.push({ x, w, alpha: target.globalAlpha as number });
        }
        if (prop in target) return target[prop];
        return () => {};
      },
      set: (target, prop: string, value) => { target[prop] = value; return true; },
    }) as unknown as CanvasRenderingContext2D;
    const fog = { kind: 'fog' as const, density: 0, clouds: 0, fog: true, lightning: false, wind: 0 };
    const sim = new SceneEffectsSim(fog, 42, 800, 600);
    const tileW = 800 * MIST_SPAN;
    const paintAt = (time: number) => {
      sim.time = time;
      draws.length = 0;
      paintSceneEffects(ctx, sim, paints);
      expect(draws).toHaveLength(MIST_LAYERS * 2);
      return draws.map((d) => ({ ...d }));
    };
    for (const t of [0, 3.7]) {
      const d = paintAt(t);
      for (let l = 0; l < MIST_LAYERS; l++) {
        const shift = mistShift(l, t, 800);
        expect(d[l * 2].x).toBeCloseTo(shift - tileW, 9);
        expect(d[l * 2 + 1].x).toBeCloseTo(shift, 9);
        expect(d[l * 2].w).toBeCloseTo(tileW, 9);
        expect(d[l * 2].alpha).toBeCloseTo(MIST_SHARE[l] * mistBreath(l, t), 9);
      }
    }
    const early = paintAt(1);
    const later = paintAt(2);
    expect(later[1].x).toBeGreaterThan(early[1].x);
    expect(later[3].x - early[3].x).toBeGreaterThan(later[1].x - early[1].x);
  });
});
