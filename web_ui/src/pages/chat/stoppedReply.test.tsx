// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Realism overlay's button stops the whole reply, so it says so, and the
// chat state's `stoppedReply` notice is shown above the transcript with Try
// again (only while the chat still ends on the user's line) and a dismiss.
// The notice has no timer of its own: it stays until the state drops it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ProcessingOverlay, NO_PROCESSING } from '../../components/ProcessingOverlay';
import { ChatNotices } from './ChatNotices';

const NOTICE = 'You stopped this reply before it was written.';

let container: HTMLDivElement;
let root: Root;

function notices(
  stoppedReply: { notice: string; canRetry: boolean } | null,
  onRetryStopped = vi.fn(),
  onDismissStopped = vi.fn(),
) {
  act(() => {
    root.render(
      createElement(ChatNotices, {
        importNotice: '',
        onDismissImport: vi.fn(),
        sendError: null,
        onRetrySend: vi.fn(),
        onDismissSendError: vi.fn(),
        actionError: null,
        onDismissActionError: vi.fn(),
        stoppedReply,
        onRetryStopped,
        onDismissStopped,
      }),
    );
  });
  return { onRetryStopped, onDismissStopped };
}

const buttons = () => Array.from(container.querySelectorAll('button'));
const byText = (t: string) => buttons().find((b) => b.textContent?.trim() === t);

describe('stopping a reply from the Realism overlay', () => {
  beforeEach(() => {
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    vi.useFakeTimers();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.useRealTimers();
  });

  it('the overlay button says it stops the reply', () => {
    const onCancel = vi.fn();
    act(() => {
      root.render(
        createElement(ProcessingOverlay, {
          p: { ...NO_PROCESSING, active: true, realism: true, text: '{"relationship_delta":' },
          onCancel,
        }),
      );
    });
    expect(byText('Cancel Realism')).toBeUndefined();
    const stop = byText('Stop this reply');
    expect(stop).toBeDefined();
    act(() => stop!.click());
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('shows the notice with Try again, and it stays', () => {
    const { onRetryStopped, onDismissStopped } = notices({ notice: NOTICE, canRetry: true });
    expect(container.textContent).toContain(NOTICE);

    act(() => {
      vi.advanceTimersByTime(60_000);
    });
    expect(container.textContent).toContain(NOTICE);

    act(() => byText('Try again')!.click());
    expect(onRetryStopped).toHaveBeenCalledTimes(1);
    act(() => container.querySelector<HTMLButtonElement>('[aria-label="Dismiss"]')!.click());
    expect(onDismissStopped).toHaveBeenCalledTimes(1);
  });

  it('offers no Try again once the chat no longer ends on the user line', () => {
    notices({ notice: NOTICE, canRetry: false });
    expect(container.textContent).toContain(NOTICE);
    expect(byText('Try again')).toBeUndefined();
  });

  it('shows nothing when there is no stopped reply', () => {
    notices(null);
    expect(container.textContent).not.toContain(NOTICE);
  });
});
