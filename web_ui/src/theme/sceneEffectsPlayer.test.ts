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
import { FOG_BANK_CORE, FOG_BANK_SQUASH, fogBankBreath } from './sceneEffectsRender';

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

  it('builds each fog gradient once per scatter and colour, not per frame', () => {
    const { canvas, calls } = fakeCanvas();
    const ctx = canvas.getContext('2d')!;
    const fog = { ...wire(true).effects, kind: 'fog' as const, density: 0, clouds: 0, fog: true, lightning: false };
    const sim = new SceneEffectsSim(fog, 42, 800, 600);
    const built = () => calls.filter((c) => c === 'createRadialGradient').length;
    paintSceneEffects(ctx, sim, paints);
    expect(built()).toBe(sim.fogBlobs.length);
    sim.advance(1 / 30);
    paintSceneEffects(ctx, sim, paints);
    expect(built()).toBe(sim.fogBlobs.length);
    expect(calls.filter((c) => c === 'translate')).toHaveLength(sim.fogBlobs.length * 2);
    paintSceneEffects(ctx, sim, { ...paints, fog: 'rgba(201, 206, 211, 0.702)' });
    expect(built()).toBe(sim.fogBlobs.length * 2);
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
    const storm = { ...wire(true).effects, fog: true };
    const sim = new SceneEffectsSim(storm, 42, 800, 600);
    sim.flash = 0.5;
    paintSceneEffects(ctx, sim, paints);
    const cloudFill = calls.lastIndexOf('fill');
    const firstFog = calls.indexOf('translate');
    const lastFog = calls.lastIndexOf('translate');
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

describe('scene effects fog banks', () => {
  // A blob drawn as a full disc at a fixed alpha read as one flat grey wash
  // over the fog's own haze; each is now a squashed bank, solid out to its
  // core, breathing on its own phase. The desktop's SceneFogLayer twin is
  // pinned in ambient_stage_effects_test.
  it('draws each blob as a squashed bank with a solid core that breathes', () => {
    const stops: [number, string][] = [];
    const scales: [number, number][] = [];
    const alphas: number[] = [];
    const ctx = new Proxy({} as Record<string, unknown>, {
      get: (target, prop: string) => {
        if (prop === 'createRadialGradient') {
          return () => ({ addColorStop: (at: number, c: string) => stops.push([at, c]) });
        }
        if (prop === 'scale') return (x: number, y: number) => scales.push([x, y]);
        if (prop in target) return target[prop];
        return () => {};
      },
      set: (target, prop: string, value) => {
        target[prop] = value;
        if (prop === 'globalAlpha') alphas.push(value as number);
        return true;
      },
    }) as unknown as CanvasRenderingContext2D;
    const fog = { kind: 'fog' as const, density: 0, clouds: 0, fog: true, lightning: false, wind: 0 };
    const sim = new SceneEffectsSim(fog, 42, 800, 600);
    const n = sim.fogBlobs.length;
    expect(n).toBeGreaterThan(0);

    const paintAt = (time: number) => {
      sim.time = time;
      scales.length = 0;
      alphas.length = 0;
      paintSceneEffects(ctx, sim, paints);
      return alphas.slice(0, n);
    };
    const first = paintAt(0);
    expect(stops.slice(0, 3)).toEqual([[0, paints.fog], [FOG_BANK_CORE, paints.fog], [1, paints.fogClear]]);
    expect(scales).toEqual(Array.from({ length: n }, () => [1, FOG_BANK_SQUASH]));
    sim.fogBlobs.forEach((f, i) => expect(first[i]).toBeCloseTo(f.a * fogBankBreath(i, 0), 9));
    const later = paintAt(3.7);
    sim.fogBlobs.forEach((f, i) => expect(later[i]).toBeCloseTo(f.a * fogBankBreath(i, 3.7), 9));
    expect(later).not.toEqual(first);
  });
});
