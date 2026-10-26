// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat page's scene sound hook (docs/design/ambient-stage.md §5, PR 3):
// it plays what the chat state's scene says only with the desktop's Scene
// sound on, ducks while a voice clip from the Speak button plays on this
// device and comes back when it ends, answers a flash with thunder on a
// storm, and stops when the chat page goes.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { useSceneSound } from './useSceneSound';
import { trackVoice } from '../../components/voiceActivity';
import { SCENE_DUCK, type AudioLike } from '../../theme/sceneSound';
import type { Flash } from '../../theme/sceneEffects';

class FakeAudio implements AudioLike {
  loop = false;
  volume = 1;
  currentTime = 0;
  playing = false;
  plays = 0;
  constructor(readonly src: string) {}
  play() {
    this.plays++;
    this.playing = true;
    return Promise.resolve();
  }
  pause() {
    this.playing = false;
  }
}

let made: FakeAudio[];
let host: HTMLDivElement;
let root: Root;
let flash: ((f: Flash) => void) | null;

function Probe({ scene }: { scene: unknown }) {
  const { onFlash } = useSceneSound(scene, {
    makeAudio: (src) => {
      const a = new FakeAudio(src);
      made.push(a);
      return a;
    },
  });
  flash = onFlash;
  return null;
}

const scene = (condition: string, on: boolean, volume = 0.6) => ({
  condition, daypart: 'night', temp: 'mild', sound: { on, volume },
});

beforeEach(() => {
  vi.useFakeTimers();
  vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
  made = [];
  flash = null;
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  host.remove();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

it('plays nothing with Scene sound off or without a scene', async () => {
  await act(async () => root.render(createElement(Probe, { scene: scene('rain', false) })));
  await act(async () => root.render(createElement(Probe, { scene: null })));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(1000);
  });
  expect(made).toHaveLength(0);
  act(() => root.unmount());
});

it('ducks under a voice clip and stops when the page goes', async () => {
  await act(async () => root.render(createElement(Probe, { scene: scene('fog', true, 0.6) })));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(1000);
  });
  expect(made).toHaveLength(1);
  expect(made[0].src).toBe('/audio/scene/fog.mp3');
  expect(made[0].volume).toBeCloseTo(0.6);

  const voice = new Audio();
  trackVoice(voice);
  voice.dispatchEvent(new Event('playing'));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(1000);
  });
  expect(made[0].volume).toBeCloseTo(0.6 * SCENE_DUCK);
  voice.dispatchEvent(new Event('ended'));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(1000);
  });
  expect(made[0].volume).toBeCloseTo(0.6);

  act(() => root.unmount());
  expect(made[0].playing).toBe(false);
});

it('answers a storm flash with thunder', async () => {
  await act(async () => root.render(createElement(Probe, { scene: scene('storm', true, 0.5) })));
  act(() => flash?.({ at: 4, rumbleDelay: 0.5 }));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(600);
  });
  const played = made.filter((a) => a.plays > 0).map((a) => a.src).sort();
  expect(played).toEqual(['/audio/scene/storm_rain.mp3', '/audio/scene/thunder_1.mp3']);
  act(() => root.unmount());
});
