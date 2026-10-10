// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Editing your own message must not offer a "Thinking" section (user
// messages have no model reasoning); a character's message keeps it. Rendered
// through ChatOverlays so the page's wiring is what is pinned.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { ChatOverlays } from './ChatOverlays';
import { type Message } from '../../components/chatTypes';

let container: HTMLDivElement;
let root: Root;

const messages: Message[] = [
  { index: 0, sender: 'Carmen', text: 'Evening, neighbor.', isUser: false },
  { index: 1, sender: 'You', text: 'I brought peaches.', isUser: true },
];

function render(index: number) {
  const noop = () => {};
  return act(async () => {
    root.render(
      createElement(ChatOverlays, {
        showPicker: false,
        onPick: noop,
        onClosePicker: noop,
        editTarget: { index, text: messages[index].text },
        onCancelEdit: noop,
        onSaveEdit: async () => {},
        showPersona: false,
        onClosePersona: noop,
        onPersonaChanged: noop,
        reprocessIndex: null,
        messages,
        onSubmitReprocess: async () => {},
        onSubmitReprocessFeelings: async () => {},
        onCloseReprocess: noop,
        chance: null,
        onReveal: noop,
        onAccept: noop,
      }),
    );
  });
}

describe('message editor Thinking section', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
  });

  it('is hidden when editing your own message', async () => {
    await render(1);
    expect(container.querySelector('[aria-label="Edit message"]')).not.toBeNull();
    expect(container.textContent).not.toContain('Thinking');
  });

  it('stays for a character message', async () => {
    await render(0);
    expect(container.textContent).toContain('Thinking');
  });
});
