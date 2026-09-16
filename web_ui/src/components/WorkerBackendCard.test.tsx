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

describe('WorkerBackendCard', () => {
  it('defaults to Off — same as chat', () => {
    render({ backend: 'openRouter', remoteApiUrl: 'https://nano-gpt.com/api/v1' });
    const select = container.querySelector('select') as HTMLSelectElement;
    expect(select.value).toBe('off');
    expect(container.textContent).toContain('Off — same as chat');
    expect(container.querySelector('[data-testid="worker-dual-local-banner"]')).toBeNull();
  });

  it('shows the GPU warning live when chat is Kobold and worker is oMLX', () => {
    render({
      backend: 'kobold',
      remoteApiUrl: '',
      workerBackend: 'omlx',
      workerRemoteApiUrl: 'http://localhost:8000/v1',
      omlxAvailable: true,
    });
    const banner = container.querySelector('[data-testid="worker-dual-local-banner"]');
    expect(banner?.textContent).toContain('fight over the GPU');
    expect(banner?.textContent).toBe(kWorkerDualLocalMessage);
  });

  it('shows unready copy when the pair is allowed', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerBackend: 'kobold',
      workerUnreadyMessage: 'Side jobs are waiting for KoboldCPP to start.',
    });
    const banner = container.querySelector('[data-testid="worker-dual-local-banner"]');
    expect(banner?.textContent).toContain('waiting for KoboldCPP');
  });

  it('lists the same picker families as desktop when oMLX is available', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      omlxAvailable: true,
    });
    const labels = [...container.querySelectorAll('option')].map((o) => o.textContent);
    expect(labels).toEqual([
      'Off — same as chat',
      'KoboldCpp',
      'OpenRouter',
      'Nano-GPT',
      'LM Studio',
      'oMLX',
      'Custom',
    ]);
  });

  it('hides oMLX when the host does not offer it', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      omlxAvailable: false,
    });
    const labels = [...container.querySelectorAll('option')].map((o) => o.textContent);
    expect(labels).not.toContain('oMLX');
    expect(labels).toContain('Off — same as chat');
    expect(labels).toContain('KoboldCpp');
    expect(labels).toContain('Custom');
  });

  it('keeps Nano + Nano (same host, different model) without a warning', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerBackend: 'openRouter',
      workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerRemoteModelName: 'z-ai/glm-5.3',
    });
    expect(container.querySelector('[data-testid="worker-dual-local-banner"]')).toBeNull();
    const select = container.querySelector('select') as HTMLSelectElement;
    expect(select.value).toBe('nanogpt');
  });
});
