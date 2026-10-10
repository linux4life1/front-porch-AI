// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone picker shows the desktop's row label, so the first reply reads
// "Original" (desktop VariantOption.toJson sends it; pinned Dart-side in
// variant_picker_original_label_test.dart).

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';

const get = vi.fn();

vi.mock('../api/client', () => ({
  api: {
    get: (...args: unknown[]) => get(...args),
    post: vi.fn(),
  },
}));

const { VariantPickerModal } = await import('./VariantPickerModal');

describe('VariantPickerModal row label', () => {
  let container: HTMLDivElement;
  let root: Root;

  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    get.mockReset();
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('labels the first reply Original and later ones Regen', async () => {
    get.mockResolvedValue({
      kind: 'regen',
      title: 'Select variant',
      currentIndex: 1,
      variants: [
        { index: 0, snippet: 'She smiles.', text: 'She smiles.', charCount: 11, tokenCount: 3, current: false, kind: 'regen', label: 'Original' },
        { index: 1, snippet: 'She takes the peach.', text: 'She takes the peach.', charCount: 20, tokenCount: 5, current: true, kind: 'regen', label: 'Regen' },
      ],
    });
    await act(async () => {
      root.render(
        createElement(VariantPickerModal, { messageIndex: 3, onClose: () => {}, onPicked: () => {} }),
      );
    });
    await act(async () => {
      await Promise.resolve();
    });
    const metas = [...container.querySelectorAll('.variant-card-meta')].map((m) => m.textContent);
    expect(metas).toEqual(['Original · 11 characters · 3t', 'Regen · 20 characters · 5t']);
  });
});
