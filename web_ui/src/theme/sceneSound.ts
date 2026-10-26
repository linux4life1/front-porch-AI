// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient Stage's scene sound on the web (docs/design/ambient-stage.md
// §5), the twin of lib/services/chat/scene/scene_sound.dart and
// scene_sound_service.dart: the same (condition, daypart) → loop table, the
// same thunder pick from the flash's seeded gap, the same duck under a
// voice. The files are the desktop's own (assets/audio/scene, synthesised
// by tools/gen_scene_sounds.py, CC0), served as /audio/scene/<name>.mp3.
//
// Each active loop is its own <audio loop> element, so a change of loop
// is a true crossfade: the new one ramps up while the old one ramps down.
// A browser that refuses to start sound before the page is touched leaves
// the loop waiting; the next tap or key on the page starts it (the same
// fallback as the story reader's useAmbient, which turns itself off).

import type { Flash } from './sceneEffects';

export const SCENE_DUCK = 0.3;
export const RAMP_FULL_MS = 600;
export const RAMP_STEP_MS = 40;
export const THUNDER_MIN_S = 0.4;
export const THUNDER_MAX_S = 1.8;
export const THUNDER = ['thunder_1', 'thunder_2', 'thunder_3'] as const;

const DAY = new Set(['dawn', 'morning', 'late_morning', 'afternoon']);
const NIGHT = new Set(['evening', 'night']);

/** The loop for a scene's weather at a part of the day, or null: cloudy and overcast are quiet. */
export function sceneLoopFor(condition: string, daypart: string): string | null {
  switch (condition) {
    case 'rain': return 'rain';
    case 'storm': return 'storm_rain';
    case 'snow': return 'wind';
    case 'fog': return 'fog';
    case 'clear':
      if (DAY.has(daypart)) return 'birds';
      if (NIGHT.has(daypart)) return 'crickets';
      return null;
    default: return null;
  }
}

export const sceneSoundSrc = (name: string) => `/audio/scene/${name}.mp3`;

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** The wait after a flash, in ms: its seeded gap held to 0.4..1.8 s. */
export function thunderDelayMs(rumbleDelay: number): number {
  const s = Number.isFinite(rumbleDelay) ? clamp(rumbleDelay, THUNDER_MIN_S, THUNDER_MAX_S) : THUNDER_MIN_S;
  return Math.round(s * 1000);
}

/** Which thunder answers a flash: a near strike (short gap) the shortest roll. */
export function thunderFor(rumbleDelay: number): string {
  const t = Number.isFinite(rumbleDelay)
    ? clamp((rumbleDelay - THUNDER_MIN_S) / (THUNDER_MAX_S - THUNDER_MIN_S), 0, 1)
    : 0;
  return THUNDER[clamp(Math.floor(t * THUNDER.length), 0, THUNDER.length - 1)];
}

/** The loop's level: the volume, ducked to 30% under a voice, silent when hidden. */
export function loopGain(volume: number, speaking: boolean, visible = true): number {
  if (!visible) return 0;
  const v = Number.isFinite(volume) ? clamp(volume, 0, 1) : 0;
  return speaking ? v * SCENE_DUCK : v;
}

/** How long a ramp between two levels takes, in ms. */
export function rampLengthMs(from: number, to: number): number {
  return Math.round(RAMP_FULL_MS * clamp(Math.abs(to - from), 0, 1));
}

/** The level elapsed ms into a ramp: linear, held at the ends, within 0..1. */
export function rampAt(from: number, to: number, elapsedMs: number): number {
  const total = rampLengthMs(from, to);
  if (total === 0 || elapsedMs >= total) return clamp(to, 0, 1);
  const t = Math.max(0, elapsedMs) / total;
  return clamp(from + (to - from) * t, 0, 1);
}

/** What the chat state's `scene` says to play, or null when it says nothing. */
export interface SceneSoundState { on: boolean; volume: number; condition: string; daypart: string }

export function parseSceneSound(scene: unknown): SceneSoundState | null {
  if (!scene || typeof scene !== 'object') return null;
  const w = scene as Record<string, unknown>;
  if (typeof w.condition !== 'string' || typeof w.daypart !== 'string') return null;
  const s = w.sound as Record<string, unknown> | undefined;
  if (!s || typeof s !== 'object') return null;
  const volume = typeof s.volume === 'number' && Number.isFinite(s.volume) ? clamp(s.volume, 0, 1) : 0.5;
  return { on: s.on === true, volume, condition: w.condition, daypart: w.daypart };
}

/** The bits of an <audio> element the player uses, so tests can hand in a fake. */
export interface AudioLike {
  loop: boolean;
  volume: number;
  currentTime: number;
  play(): Promise<void>;
  pause(): void;
}

export interface SceneSoundOptions {
  makeAudio?: (src: string) => AudioLike;
  /** Called when the browser refuses (true) and later allows (false) the sound. */
  onBlocked?: (blocked: boolean) => void;
}

/** One loop's element; `held` while a hidden tab has paused it. */
interface Voice { name: string; el: AudioLike; gain: number; timer: ReturnType<typeof setInterval> | null; held: boolean }

/** Plays one chat's scene sound. update() with each new chat state; dispose() on unmount. */
export class SceneSoundPlayer {
  private readonly makeAudio: (src: string) => AudioLike;
  private readonly onBlocked?: (blocked: boolean) => void;
  private loop: string | null = null;
  private volume = 0.5;
  private storm = false;
  private speaking = false;
  private current: Voice | null = null;
  private fading: Voice[] = [];
  private readonly thunders = new Set<ReturnType<typeof setTimeout>>();
  /** The three thunders, made (and so fetched) when a storm starts, so a rumble never waits on the network. */
  private thunderEls = new Map<string, AudioLike>();
  private waitingForTap = false;
  private disposed = false;
  blocked = false;

  constructor(opts: SceneSoundOptions = {}) {
    this.makeAudio = opts.makeAudio ?? ((src) => {
      const el = new Audio(src);
      el.preload = 'auto';
      return el;
    });
    this.onBlocked = opts.onBlocked;
    document.addEventListener('visibilitychange', this.onVisibility);
  }

  /** The loop name (null for none: sound off, no scene, a quiet sky), the volume, and whether a storm may thunder. */
  update(next: { loop: string | null; volume: number; storm: boolean }): void {
    this.loop = next.loop;
    this.volume = next.volume;
    this.storm = next.storm;
    if (this.storm && this.loop !== null) this.readyThunder();
    else this.dropThunder();
    this.reconcile();
  }

  setSpeaking(speaking: boolean): void {
    if (this.speaking === speaking) return;
    this.speaking = speaking;
    this.reconcile();
  }

  /** A flash on the stage: thunder after its gap, on a storm only. */
  flash(f: Flash): void {
    if (!this.thunderAllowed) return;
    const t = setTimeout(() => {
      this.thunders.delete(t);
      if (!this.thunderAllowed) return;
      const el = this.readyThunder().get(thunderFor(f.rumbleDelay))!;
      el.currentTime = 0;
      el.volume = loopGain(this.volume, this.speaking);
      el.play().catch((e: unknown) => console.warn('[scene sound] thunder could not play', e));
    }, thunderDelayMs(f.rumbleDelay));
    this.thunders.add(t);
  }

  /** The loop playing (or waiting to) now, for tests and the page. */
  get playing(): string | null {
    return this.current?.name ?? null;
  }

  get gain(): number {
    return this.current?.gain ?? 0;
  }

  dispose(): void {
    this.disposed = true;
    document.removeEventListener('visibilitychange', this.onVisibility);
    this.stopWaitingForTap();
    this.dropThunder();
    for (const v of [...this.fading, ...(this.current ? [this.current] : [])]) this.drop(v);
    this.fading = [];
    this.current = null;
  }

  private get visible(): boolean {
    return !document.hidden;
  }

  private get thunderAllowed(): boolean {
    return !this.disposed && this.storm && this.loop !== null && this.visible;
  }

  private readonly onVisibility = () => {
    if (!this.visible) this.cancelThunder();
    this.reconcile();
  };

  private reconcile(): void {
    if (this.disposed) return;
    if (!this.visible) {
      // Hidden: everything holds where it is, silent; a wanted loop resumes on return.
      for (const v of this.fading) this.drop(v);
      this.fading = [];
      const cur = this.current;
      if (cur) {
        this.stopRamp(cur);
        cur.el.pause();
        cur.held = true;
        cur.gain = 0;
        cur.el.volume = 0;
        if (this.loop !== cur.name) {
          this.drop(cur);
          this.current = null;
        }
      }
      return;
    }
    if (this.current?.name !== this.loop) {
      const old = this.current;
      if (old) {
        this.fading.push(old);
        this.ramp(old, 0, () => {
          this.fading = this.fading.filter((v) => v !== old);
          this.drop(old);
        });
      }
      this.current = null;
      if (this.loop) this.current = this.start(this.loop);
    }
    const cur = this.current;
    if (!cur) return;
    if (cur.held) {
      // Back from a hidden tab: carry on from where it paused.
      cur.held = false;
      this.play(cur);
    }
    if (!this.blocked) this.ramp(cur, loopGain(this.volume, this.speaking));
  }

  private start(name: string): Voice {
    const el = this.makeAudio(sceneSoundSrc(name));
    el.loop = true;
    el.volume = 0;
    const voice: Voice = { name, el, gain: 0, timer: null, held: false };
    this.play(voice);
    return voice;
  }

  private play(voice: Voice): void {
    voice.el.play().then(
      () => {
        if (this.blocked) {
          this.blocked = false;
          this.onBlocked?.(false);
          this.reconcile();
        }
      },
      (e: unknown) => {
        if (this.disposed || voice !== this.current) return;
        if (e instanceof DOMException && e.name === 'NotAllowedError') {
          // The browser wants a tap first: wait for one, then try again.
          if (!this.blocked) {
            this.blocked = true;
            this.onBlocked?.(true);
          }
          this.waitForTap();
        } else {
          console.warn(`[scene sound] ${voice.name} could not play`, e);
        }
      },
    );
  }

  /** On a refused start, the next tap or key on the page tries again. */
  private waitForTap(): void {
    if (this.waitingForTap) return;
    this.waitingForTap = true;
    document.addEventListener('pointerdown', this.onTap, true);
    document.addEventListener('keydown', this.onTap, true);
  }

  private stopWaitingForTap(): void {
    if (!this.waitingForTap) return;
    this.waitingForTap = false;
    document.removeEventListener('pointerdown', this.onTap, true);
    document.removeEventListener('keydown', this.onTap, true);
  }

  private readonly onTap = () => {
    this.stopWaitingForTap();
    const cur = this.current;
    if (cur && this.visible) this.play(cur);
  };

  /** Moves a voice's level to `to` at RAMP_FULL_MS for a full swing, then runs `then`. */
  private ramp(voice: Voice, to: number, then?: () => void): void {
    this.stopRamp(voice);
    const from = voice.gain;
    const length = rampLengthMs(from, to);
    if (length < RAMP_STEP_MS) {
      voice.gain = to;
      voice.el.volume = to;
      then?.();
      return;
    }
    let elapsed = 0;
    voice.timer = setInterval(() => {
      elapsed += RAMP_STEP_MS;
      voice.gain = rampAt(from, to, elapsed);
      voice.el.volume = voice.gain;
      if (elapsed >= length) {
        this.stopRamp(voice);
        then?.();
      }
    }, RAMP_STEP_MS);
  }

  private stopRamp(voice: Voice): void {
    if (voice.timer !== null) clearInterval(voice.timer);
    voice.timer = null;
  }

  private drop(voice: Voice): void {
    this.stopRamp(voice);
    voice.el.pause();
  }

  private readyThunder(): Map<string, AudioLike> {
    if (this.thunderEls.size === 0) {
      for (const name of THUNDER) {
        const el = this.makeAudio(sceneSoundSrc(name));
        el.loop = false;
        this.thunderEls.set(name, el);
      }
    }
    return this.thunderEls;
  }

  /** No storm any more: the rumbles on their way and the thunders themselves go. */
  private dropThunder(): void {
    this.cancelThunder();
    for (const el of this.thunderEls.values()) el.pause();
    this.thunderEls = new Map();
  }

  private cancelThunder(): void {
    for (const t of this.thunders) clearTimeout(t);
    this.thunders.clear();
  }
}
