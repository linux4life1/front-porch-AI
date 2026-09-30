// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// useReprocessNeeds derives the Reprocess Needs modal props from the facade
// chips. speakerName is needsSpeaker and nothing else: the open character
// can be the previous speaker in a group. The last case drives the real
// hook into the real modal for the stale-open case.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { type Message } from '../../components/chatTypes';
import { ReprocessNeedsModal } from '../../components/ReprocessNeedsModal';
import { useReprocessNeeds } from './useReprocessNeeds';

const msg = (chips?: Message['chips']): Message => ({
  index: 0,
  sender: 'Aria',
  text: 'Evening.',
  isUser: false,
  chips,
});

describe('useReprocessNeeds', () => {
  it('is empty when the sheet is closed', () => {
    expect(useReprocessNeeds(null, [msg()])).toEqual({
      enabledNeeds: [],
      speaker: '',
      speakerName: '',
    });
  });

  it('reads enabledNeeds and speaker from the message chips', () => {
    expect(
      useReprocessNeeds(
        0,
        [
          msg({
            enabledNeeds: ['hunger', 'energy'],
            needsSpeaker: 'Bram',
          }),
        ],
      ),
    ).toEqual({
      enabledNeeds: ['hunger', 'energy'],
      speaker: 'Bram',
      speakerName: 'Bram',
    });
  });

  it('leaves the name empty when the chip has no speaker', () => {
    expect(useReprocessNeeds(0, [msg({ enabledNeeds: ['fun'] })])).toEqual({
      enabledNeeds: ['fun'],
      speaker: '',
      speakerName: '',
    });
  });
});

describe('stale open after Needs is switched off (F7)', () => {
  let container: HTMLDivElement;
  let root: Root;
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('F7 chips lost enabledNeeds/needsSpeaker: the modal shows the one null string and only Close', () => {
    // After Needs is switched off the facade drops needsReprocessable,
    // enabledNeeds and needsSpeaker; the modal is still open on that index.
    const stale = [msg({ needsDeltas: { hunger: { delta: -5, reason: '' } } })];
    const props = useReprocessNeeds(0, stale);
    act(() => {
      root.render(
        createElement(ReprocessNeedsModal, {
          ...props,
          onSubmit: vi.fn(async () => {}),
          onClose: vi.fn(),
        }),
      );
    });
    const text = container.textContent ?? '';
    expect(text).toContain("There's nothing to reprocess for this message.");
    expect(text).not.toContain('Aria');
    expect(container.querySelector('textarea')).toBeNull();
    const buttons = Array.from(container.querySelectorAll('button')).map((b) => b.textContent?.trim());
    expect(buttons).toEqual(['Close']);
  });
});
