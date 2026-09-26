// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// useReprocessNeeds derives the Reprocess Needs modal props from the facade
// chips (AMENDMENT 2 item 3: enabledNeeds / speaker / speakerName). The first
// three cases are the PR's own; the last one (folded from our F7) drives the
// real hook into the real modal for the stale-open case.

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
    expect(useReprocessNeeds(null, [msg()], 'Aria')).toEqual({
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
        'Aria',
      ),
    ).toEqual({
      enabledNeeds: ['hunger', 'energy'],
      speaker: 'Bram',
      speakerName: 'Bram',
    });
  });

  it('falls back to the character name when the chip has no speaker', () => {
    expect(useReprocessNeeds(0, [msg({ enabledNeeds: ['fun'] })], 'Aria')).toEqual({
      enabledNeeds: ['fun'],
      speaker: '',
      speakerName: 'Aria',
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
    const props = useReprocessNeeds(0, stale, 'Aria');
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
