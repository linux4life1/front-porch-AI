// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Manual Reprocess on the phone offers the same choice as the desktop: Needs
// (today's critique pass, the default) or Feelings (bond, trust and mood
// scored again). The button shows when the facade offers either; the modal
// reads the facade's feelingsSpeaker and never re-derives the gate.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../api/client';
import { ChipsRow } from './ChipsRow';
import {
  CHOICE_FEELINGS,
  CHOICE_NEEDS,
  CHOICE_PROMPT,
  FEELINGS_BUTTON,
  ReprocessNeedsModal,
  feelingsIntro,
} from './ReprocessNeedsModal';
import { type Chips, type Message } from './chatTypes';
import { useReprocessNeeds } from '../pages/chat/useReprocessNeeds';

let container: HTMLDivElement;
let root: Root;

const text = () => container.textContent ?? '';
const buttons = () => Array.from(container.querySelectorAll('button'));
const button = (label: string) => buttons().find((b) => b.textContent?.trim() === label);

async function clickAsync(el: Element | undefined) {
  expect(el).toBeDefined();
  await act(async () => {
    el!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

function renderModal(props: {
  enabledNeeds: string[];
  feelingsSpeaker?: string;
  onSubmit?: () => Promise<void>;
  onSubmitFeelings?: () => Promise<void>;
}) {
  const onSubmit = props.onSubmit ?? vi.fn(async () => {});
  const onSubmitFeelings = props.onSubmitFeelings ?? vi.fn(async () => {});
  act(() => {
    root.render(
      createElement(ReprocessNeedsModal, {
        enabledNeeds: props.enabledNeeds,
        speaker: 'Mara',
        speakerName: 'Mara',
        feelingsSpeaker: props.feelingsSpeaker,
        onSubmit,
        onSubmitFeelings,
        onClose: vi.fn(),
      }),
    );
  });
  return { onSubmit, onSubmitFeelings };
}

describe('Manual Reprocess: Needs or Feelings', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('both on offer: Needs is the default; picking Feelings submits the re-score, not Needs', async () => {
    const { onSubmit, onSubmitFeelings } = renderModal({
      enabledNeeds: ['hunger', 'energy'],
      feelingsSpeaker: 'Mara',
    });
    expect(text()).toContain(CHOICE_PROMPT);
    expect(text()).toContain('Reprocess Needs');
    expect(container.querySelector('textarea')).not.toBeNull();
    expect(button(CHOICE_NEEDS)?.getAttribute('aria-checked')).toBe('true');

    await clickAsync(button(CHOICE_FEELINGS));
    expect(text()).toContain('Reprocess Feelings');
    expect(text()).toContain(feelingsIntro('Mara'));
    expect(container.querySelector('textarea')).toBeNull();
    expect(button('Reprocess')).toBeUndefined();

    await clickAsync(button(FEELINGS_BUTTON));
    expect(onSubmitFeelings).toHaveBeenCalledTimes(1);
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('Needs off, Realism on: Feelings only, no choice row', () => {
    renderModal({ enabledNeeds: [], feelingsSpeaker: 'Mara' });
    expect(text()).not.toContain(CHOICE_PROMPT);
    expect(text()).toContain(feelingsIntro('Mara'));
    expect(button(FEELINGS_BUTTON)).toBeDefined();
    expect(button('Cancel')).toBeDefined();
  });

  it('no feelingsSpeaker from the facade: no Feelings choice at all', () => {
    renderModal({ enabledNeeds: ['hunger'] });
    expect(text()).not.toContain(CHOICE_PROMPT);
    expect(button(CHOICE_FEELINGS)).toBeUndefined();
    expect(button('Reprocess')).toBeDefined();
  });

  it('a failed re-score says why in plain words and keeps the modal open', async () => {
    const reason = "The model's answer couldn't be read, so this reply keeps the feelings it had. You can try again.";
    renderModal({
      enabledNeeds: [],
      feelingsSpeaker: 'Mara',
      onSubmitFeelings: vi.fn(async () => {
        throw new ApiError(409, reason, { error: reason });
      }),
    });
    await clickAsync(button(FEELINGS_BUTTON));
    expect(text()).toContain(reason);
    expect(button(FEELINGS_BUTTON)).toBeDefined();
  });

  it('the Manual Reprocess button shows for a Feelings-only reply, and only on the last one', () => {
    const chips = { feelingsReprocessable: true, feelingsSpeaker: 'Mara', bondDelta: 2 } as Chips;
    const draw = (isLast: boolean) =>
      act(() => {
        root.render(createElement(ChipsRow, { chips, isLast, busy: false, onReprocess: vi.fn(), onRevert: vi.fn() }));
      });
    const reprocess = () => buttons().find((b) => (b.textContent ?? '').includes('Manual Reprocess'));
    draw(true);
    expect(reprocess()).toBeDefined();
    draw(false);
    expect(reprocess()).toBeUndefined();
  });

  it('useReprocessNeeds passes the facade speaker through only when Feelings is on offer', () => {
    const msg = (chips: Chips) => ({ index: 0, sender: 'Mara', text: 'hi', isUser: false, chips }) as Message;
    expect(useReprocessNeeds(0, [msg({ feelingsReprocessable: true, feelingsSpeaker: 'Mara' })]).feelingsSpeaker).toBe('Mara');
    expect(useReprocessNeeds(0, [msg({ feelingsSpeaker: 'Mara' })]).feelingsSpeaker).toBeUndefined();
  });
});
