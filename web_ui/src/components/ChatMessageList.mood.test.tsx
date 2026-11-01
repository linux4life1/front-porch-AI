// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mood on the character at its full level: the latest reply wears its
// stamped mood in the desktop's hue, at full loudness while the stamp still
// matches the host's live mood and mild once it is stale; earlier replies,
// the user's bubbles and the lower levels wear nothing.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { Message } from './chatTypes';
import { moodPaintsOf, type MoodLook } from '../theme/moodAtmosphere';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

const paints = moodPaintsOf({
  tones: { sour: '#ff5252', low: '#607d8b', anxious: '#7c4dff', lifted: '#ffc107', warm: '#ff4081', charged: '#ffab40' },
  dark: { needs: { energy: '#ffd740' }, haloWarm: '#ff4081', haloChill: '#448aff' },
  light: { needs: { energy: '#92400e' }, haloWarm: '#9d174d', haloChill: '#1d4ed8' },
}, 'dark');

const messages: Message[] = [
  { index: 0, sender: 'Maren', text: 'Hello.', isUser: false, characterId: 'c1', chips: { emotionLabel: 'sadness' } },
  { index: 1, sender: 'You', text: 'Hi.', isUser: true },
  { index: 2, sender: 'Maren', text: 'You came back.', isUser: false, characterId: 'c1', chips: { emotionLabel: 'joy' } },
];

function renderList(moodLook: MoodLook, liveMood: { emotion: string; intensity: string; held: number } | null) {
  act(() => {
    root.render(
      createElement(ChatMessageList, {
        messages,
        castById: new Map(),
        multiCast: false,
        lastIndex: 2,
        busy: false,
        canSpeak: false,
        onBeginEdit: noop,
        onSwipe: noop,
        onRegenerate: noop,
        onContinue: noop,
        onFork: noop,
        onDelete: noop,
        onReprocess: noop,
        onRevert: noop,
        streaming: '',
        followStreamingReplies: true,
        genStatus: null,
        scrollRef: createRef<HTMLDivElement>(),
        sessionId: 's1',
        moodLook,
        moodPaints: paints,
        liveMood,
      }),
    );
  });
}

const bubbles = () => Array.from(container.querySelectorAll<HTMLElement>('.bubble'));

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('the latest reply wears its stamped mood at the live loudness', () => {
  renderList({ level: 'all', drama: 1 }, { emotion: 'joy', intensity: 'strong', held: 0 });
  const [first, user, latest] = bubbles();
  expect(latest.className).toBe('bubble ai mood-bubble tone-lifted');
  expect(latest.style.getPropertyValue('--mood-hue')).toBe('#ffc107');
  expect(latest.style.getPropertyValue('--mood-a')).toBe('0.850');
  expect(first.className).toBe('bubble ai');
  expect(user.className).toBe('bubble user');
});

it('a stale stamp paints mild, and the lower levels paint nothing', () => {
  renderList({ level: 'all', drama: 1 }, { emotion: 'anger', intensity: 'strong', held: 3 });
  expect(bubbles()[2].className).toBe('bubble ai mood-bubble tone-lifted');
  expect(bubbles()[2].style.getPropertyValue('--mood-a')).toBe('0.300');
  renderList({ level: 'portrait', drama: 1 }, { emotion: 'joy', intensity: 'strong', held: 0 });
  expect(bubbles()[2].className).toBe('bubble ai');
  renderList({ level: 'off', drama: 1 }, null);
  expect(bubbles()[2].className).toBe('bubble ai');
});
