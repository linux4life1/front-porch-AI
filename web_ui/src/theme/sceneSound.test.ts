// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web scene sound (docs/design/ambient-stage.md §5, PR 3), the twin of
// test/services/chat/scene/scene_sound_test.dart: the loop for every
// condition and part of day, a true crossfade between loops, thunder after a
// storm flash's gap and never without a storm, the duck under a voice, the
// autoplay-refused wait for a tap, and silence in a hidden tab. The <audio>
// elements are fakes; the timers are vitest's.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  SCENE_DUCK, SceneSoundPlayer, loopGain, parseSceneSound, rampAt, rampLengthMs, sceneLoopFor,
  sceneSoundSrc, thunderDelayMs, thunderFor, type AudioLike,
} from './sceneSound';
import { SceneEffectsSim } from './sceneEffects';
import { SceneEffectsPlayer } from './sceneEffectsPlayer';

const DAYPARTS = ['dawn', 'morning', 'late_morning', 'afternoon', 'evening', 'night'];

class FakeAudio implements AudioLike {
  loop = false;
  volume = 1;
  playing = false;
  plays = 0;
  refuse: string | null = null;
  constructor(readonly src: string) {}
  play(): Promise<void> {
    this.plays++;
    if (this.refuse) return Promise.reject(new DOMException('no', this.refuse));
    this.playing = true;
    return Promise.resolve();
  }
  pause(): void {
    this.playing = false;
  }
}

let made: FakeAudio[];
let refuseNext: string | null;
const makeAudio = (src: string) => {
  const a = new FakeAudio(src);
  a.refuse = refuseNext;
  made.push(a);
  return a;
};
const flush = () => vi.advanceTimersByTimeAsync(0);
let hidden = false;

beforeEach(() => {
  vi.useFakeTimers();
  made = [];
  refuseNext = null;
  hidden = false;
  vi.spyOn(document, 'hidden', 'get').mockImplementation(() => hidden);
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('the scene sound table', () => {
  it('maps every condition at every part of the day', () => {
    const expected: Record<string, (d: string) => string | null> = {
      clear: (d) => (d === 'evening' || d === 'night' ? 'crickets' : 'birds'),
      cloudy: () => null,
      overcast: () => null,
      fog: () => 'fog',
      rain: () => 'rain',
      storm: () => 'storm_rain',
      snow: () => 'wind',
    };
    for (const [condition, want] of Object.entries(expected)) {
      for (const d of DAYPARTS) expect(sceneLoopFor(condition, d), `${condition} at ${d}`).toBe(want(d));
    }
    expect(sceneLoopFor('clear', 'teatime')).toBeNull();
    expect(sceneLoopFor('hail', 'night')).toBeNull();
    expect(sceneSoundSrc('rain')).toBe('/audio/scene/rain.mp3');
  });

  it('holds the thunder gap to 0.4..1.8 s and picks one of three by it', () => {
    expect(thunderDelayMs(0)).toBe(400);
    expect(thunderDelayMs(1.2)).toBe(1200);
    expect(thunderDelayMs(9)).toBe(1800);
    expect(thunderDelayMs(Number.NaN)).toBe(400);
    expect(thunderFor(0.4)).toBe('thunder_1');
    expect(thunderFor(1.1)).toBe('thunder_2');
    expect(thunderFor(1.8)).toBe('thunder_3');
  });

  it('ducks to 30%, is silent hidden, and ramps within 0..1', () => {
    expect(loopGain(0.8, true)).toBeCloseTo(0.24);
    expect(loopGain(0.8, false)).toBe(0.8);
    expect(loopGain(0.8, false, false)).toBe(0);
    expect(loopGain(3, false)).toBe(1);
    expect(rampLengthMs(0, 1)).toBe(600);
    expect(rampLengthMs(0.5, 0.2)).toBe(180);
    for (let ms = 0; ms <= 700; ms += 20) {
      const v = rampAt(0.2, 0.9, ms);
      expect(v).toBeGreaterThanOrEqual(0.2);
      expect(v).toBeLessThanOrEqual(0.9);
    }
    expect(rampAt(0.2, 0.9, 700)).toBe(0.9);
    expect(rampAt(2, -1, 0)).toBeLessThanOrEqual(1);
  });

  it('reads the sound off the chat state scene', () => {
    expect(parseSceneSound(null)).toBeNull();
    expect(parseSceneSound({ condition: 'rain', daypart: 'night' })).toBeNull();
    expect(parseSceneSound({ condition: 'rain', daypart: 'night', sound: { on: true, volume: 4 } }))
      .toEqual({ on: true, volume: 1, condition: 'rain', daypart: 'night' });
  });
});

describe('the scene sound player', () => {
  it('plays the loop and crossfades to the next on its own element', async () => {
    const p = new SceneSoundPlayer({ makeAudio });
    p.update({ loop: 'rain', volume: 0.6, storm: false });
    await flush();
    expect(made).toHaveLength(1);
    expect(made[0].src).toBe('/audio/scene/rain.mp3');
    expect(made[0].loop).toBe(true);
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[0].volume).toBeCloseTo(0.6);

    p.update({ loop: 'storm_rain', volume: 0.6, storm: true });
    await vi.advanceTimersByTimeAsync(200);
    // Both sound at once mid-fade: the old one going down, the new one up.
    expect(made).toHaveLength(2);
    expect(made[0].volume).toBeGreaterThan(0);
    expect(made[0].volume).toBeLessThan(0.6);
    expect(made[1].volume).toBeGreaterThan(0);
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[0].playing).toBe(false);
    expect(made[0].volume).toBe(0);
    expect(made[1].volume).toBeCloseTo(0.6);
    expect(p.playing).toBe('storm_rain');

    p.update({ loop: null, volume: 0.6, storm: false });
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[1].playing).toBe(false);
    expect(p.playing).toBeNull();
    p.dispose();
  });

  it('answers a storm flash after its gap, and only a storm', async () => {
    const p = new SceneSoundPlayer({ makeAudio });
    p.update({ loop: 'storm_rain', volume: 0.5, storm: true });
    await flush();
    p.flash({ at: 3, rumbleDelay: 1.2 });
    await vi.advanceTimersByTimeAsync(1150);
    expect(made.filter((a) => a.src.includes('thunder'))).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(100);
    const thunder = made.filter((a) => a.src.includes('thunder'));
    expect(thunder).toHaveLength(1);
    expect(thunder[0].src).toBe('/audio/scene/thunder_2.mp3');
    expect(thunder[0].loop).toBe(false);
    expect(thunder[0].volume).toBe(0.5);
    expect(thunder[0].playing).toBe(true);

    // Rain is not a storm; and a rumble on its way is dropped when the scene changes.
    p.flash({ at: 9, rumbleDelay: 1.0 });
    p.update({ loop: 'rain', volume: 0.5, storm: false });
    p.flash({ at: 10, rumbleDelay: 0.5 });
    await vi.advanceTimersByTimeAsync(3000);
    expect(made.filter((a) => a.src.includes('thunder'))).toHaveLength(1);
    p.dispose();
  });

  it('hears the effects canvas flash through the player', () => {
    vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener: () => {}, removeEventListener: () => {} }));
    vi.spyOn(window, 'requestAnimationFrame').mockReturnValue(1);
    const canvas = {
      width: 0, height: 0,
      getBoundingClientRect: () => ({ width: 400, height: 300 }),
      getContext: () => null,
    } as unknown as HTMLCanvasElement;
    const effects = new SceneEffectsPlayer(canvas, {
      level: 'effects', seed: 9, pauseWhileGenerating: true,
      effects: {
        kind: 'rain', density: 0.0003, clouds: 4, fog: false, lightning: true, wind: 0.4,
        paints: { rain: '#000000', snow: '#000000', cloud: '#000000', fog: '#000000', fogClear: '#000000', flash: '#000000' },
      },
    });
    const heard: number[] = [];
    effects.onFlash = (f) => heard.push(f.rumbleDelay);
    // The sim inside fires on its seeded schedule; step it the way frames do.
    const sim = (effects as unknown as { sim: SceneEffectsSim }).sim;
    for (let i = 0; i < 200 && heard.length === 0; i++) sim.advance(0.1);
    expect(heard).toHaveLength(1);
    expect(heard[0]).toBeGreaterThanOrEqual(0.4);
    expect(heard[0]).toBeLessThanOrEqual(1.8);
    effects.dispose();
    vi.unstubAllGlobals();
  });

  it('ducks under a voice and comes back after', async () => {
    const p = new SceneSoundPlayer({ makeAudio });
    p.update({ loop: 'fog', volume: 0.8, storm: false });
    await vi.advanceTimersByTimeAsync(1000);
    p.setSpeaking(true);
    await vi.advanceTimersByTimeAsync(80);
    expect(made[0].volume).toBeLessThan(0.8);
    expect(made[0].volume).toBeGreaterThan(0.8 * SCENE_DUCK);
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[0].volume).toBeCloseTo(0.8 * SCENE_DUCK);
    p.setSpeaking(false);
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[0].volume).toBeCloseTo(0.8);
    expect(made).toHaveLength(1);
    p.dispose();
  });

  it('waits for a tap when the browser refuses to start sound', async () => {
    const blocked: boolean[] = [];
    refuseNext = 'NotAllowedError';
    const p = new SceneSoundPlayer({ makeAudio, onBlocked: (b) => blocked.push(b) });
    p.update({ loop: 'birds', volume: 0.5, storm: false });
    await vi.advanceTimersByTimeAsync(1000);
    expect(p.blocked).toBe(true);
    expect(blocked).toEqual([true]);
    expect(made[0].playing).toBe(false);

    made[0].refuse = null;
    document.dispatchEvent(new Event('pointerdown'));
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[0].playing).toBe(true);
    expect(p.blocked).toBe(false);
    expect(blocked).toEqual([true, false]);
    expect(made[0].volume).toBeCloseTo(0.5);
    p.dispose();
  });

  it('holds in a hidden tab and stops for good on dispose', async () => {
    const p = new SceneSoundPlayer({ makeAudio });
    p.update({ loop: 'crickets', volume: 0.7, storm: false });
    await vi.advanceTimersByTimeAsync(1000);
    hidden = true;
    document.dispatchEvent(new Event('visibilitychange'));
    expect(made[0].playing).toBe(false);
    expect(made[0].volume).toBe(0);
    hidden = false;
    document.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(1000);
    expect(made[0].playing).toBe(true);
    expect(made[0].volume).toBeCloseTo(0.7);
    p.dispose();
    expect(made[0].playing).toBe(false);
    p.update({ loop: 'rain', volume: 0.7, storm: false });
    await vi.advanceTimersByTimeAsync(1000);
    expect(made).toHaveLength(1);
  });
});
