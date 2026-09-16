// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { kWorkerDualLocalMessage } from '../workerBackend';
import { WorkerBackendCard, type WorkerBackendFields } from './WorkerBackendCard';

let container: HTMLDivElement;
let root: Root;

function render(s: WorkerBackendFields) {
  act(() => {
    root.render(
      createElement(WorkerBackendCard, {
        s,
        workerApiKey: '',
        onWorkerApiKey: () => {},
        onPatch: () => {},
      }),
    );
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean })
    .IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('WorkerBackendCard V2 swap banner', () => {
  it('hides the GPU-fight banner when swap is available', () => {
    render({
      backend: 'kobold',
      remoteApiUrl: '',
      workerBackend: 'omlx',
      workerRemoteApiUrl: 'http://localhost:8000/v1',
      workerGpuSwapAvailable: true,
      omlxAvailable: true,
    });
    expect(container.querySelector('[data-testid="worker-dual-local-banner"]')).toBeNull();
    expect(container.textContent).not.toContain(kWorkerDualLocalMessage);
  });

  it('keeps honest refuse copy when swap is not available', () => {
    render({
      backend: 'kobold',
      remoteApiUrl: '',
      workerBackend: 'omlx',
      workerRemoteApiUrl: 'http://localhost:8000/v1',
      omlxAvailable: true,
    });
    const banner = container.querySelector('[data-testid="worker-dual-local-banner"]');
    expect(banner?.textContent).toBe(kWorkerDualLocalMessage);
  });
});
