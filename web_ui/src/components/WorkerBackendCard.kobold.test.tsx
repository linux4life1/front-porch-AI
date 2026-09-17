// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () => Promise.resolve({
      models: [{ name: 'worker.gguf', path: '/models/worker.gguf', sizeBytes: 1, quant: 'Q4', paramCountB: 1, loaded: false }],
    }),
    post: async () => ({}),
  },
}));

const { WorkerBackendCard } = await import('./WorkerBackendCard');
type WorkerBackendFields = import('./WorkerBackendCard').WorkerBackendFields;

let container: HTMLDivElement;
let root: Root;
let latest: WorkerBackendFields;

function render(s: WorkerBackendFields) {
  latest = { ...s };
  const onPatch = (p: Partial<WorkerBackendFields>) => {
    latest = { ...latest, ...p };
    act(() => {
      root.render(
        createElement(WorkerBackendCard, {
          s: latest,
          workerApiKey: '',
          onWorkerApiKey: () => {},
          onPatch,
        }),
      );
    });
  };
  act(() => {
    root.render(
      createElement(WorkerBackendCard, {
        s,
        workerApiKey: '',
        onWorkerApiKey: () => {},
        onPatch,
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

describe('WorkerBackendCard Kobold GGUF slot', () => {
  it('shows a Realism evals GGUF picker on the Kobold chip', async () => {
    render({
      backend: 'kobold',
      lastUsedModelPath: '/models/mouth.gguf',
      workerBackend: 'kobold',
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.querySelector('[data-testid="side-jobs-kobold-model"]')).not.toBeNull();
    expect(container.textContent).toContain('Same as Models tab');
    expect(container.textContent).not.toContain('using the model and GPU settings from');
    const select = container.querySelector(
      '[data-testid="side-jobs-kobold-model-select"]',
    ) as HTMLSelectElement;
    expect(select).not.toBeNull();
    act(() => {
      select.value = '/models/worker.gguf';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(latest.workerKoboldModelPath).toBe('/models/worker.gguf');
  });

  it('shows a Realism evals .kcpps picker on the Kobold chip', async () => {
    render({
      backend: 'kobold',
      lastUsedModelPath: '/models/mouth.gguf',
      activeKcppsPath: '/cfg/mouth.kcpps',
      workerBackend: 'kobold',
      workerKoboldModelPath: '/models/worker.gguf',
      localKcpps: [{ name: 'worker.kcpps', path: '/cfg/worker.kcpps' }],
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.querySelector('[data-testid="side-jobs-kobold-kcpps"]')).not.toBeNull();
    expect(container.textContent).toContain('None (model file only)');
    const select = container.querySelector(
      '[data-testid="side-jobs-kobold-kcpps-select"]',
    ) as HTMLSelectElement;
    act(() => {
      select.value = '/cfg/worker.kcpps';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(latest.workerKoboldKcppsPath).toBe('/cfg/worker.kcpps');
  });
});
