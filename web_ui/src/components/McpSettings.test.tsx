// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Check connection on Porch Life must show a readable pass/fail line.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const get = vi.fn(async (_url?: string) => ({
  mcpDefault: false,
  servers: [] as unknown[],
}));
const post = vi.fn(async (url: string, _body?: unknown) => {
  if (url === '/api/mcp/servers/check-draft') {
    return {
      mcpDefault: false,
      servers: [
        {
          id: 'mcp_1',
          displayName: 'Docker',
          url: 'http://127.0.0.1:3000/mcp',
          status: 'connected',
          enabledGlobal: true,
          toolNames: ['list_containers'],
          conflictToolNames: [],
        },
      ],
      checkResult: 'Connected — 1 tool: list_containers',
    };
  }
  return { mcpDefault: false, servers: [] };
});

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) => get(url) as Promise<{ mcpDefault: boolean; servers: unknown[] }>,
    post: (url: string, body?: unknown) => post(url, body),
  },
}));

const { McpSettings, mcpCheckResultLine } = await import('./McpSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean })
    .IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockClear();
  post.mockClear();
  await act(async () => {
    root.render(createElement(McpSettings));
    await Promise.resolve();
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('MCP Porch Life', () => {
  it('formats Check connection the same way as desktop', () => {
    expect(
      mcpCheckResultLine({
        url: 'http://127.0.0.1:3000/mcp',
        status: 'connected',
        toolNames: ['list_containers'],
      }),
    ).toBe('Connected — 1 tool: list_containers');
    expect(
      mcpCheckResultLine({
        url: 'http://127.0.0.1:9/mcp',
        status: 'error',
        toolNames: [],
        lastError: 'HTTP 500',
      }),
    ).toBe('Could not reach http://127.0.0.1:9/mcp — HTTP 500');
    expect(
      mcpCheckResultLine({
        url: 'http://127.0.0.1:8811/sse',
        status: 'error',
        toolNames: [],
        lastError:
          'ClientException with SocketException: Connection refused, errno = 61',
      }),
    ).toContain('Nothing is listening');
    expect(
      mcpCheckResultLine({
        url: 'http://127.0.0.1:8811/mcp',
        status: 'connected',
        toolNames: Array.from({ length: 110 }, (_, i) => `tool_${i}`),
      }),
    ).toBe('Connected — 110 tools');
  });

  it('Check connection shows advertised tools', async () => {
    const input = container.querySelector(
      '[data-testid="mcp-add-url"]',
    ) as HTMLInputElement;
    expect(input).toBeTruthy();
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )!.set!;
      setter.call(input, 'http://127.0.0.1:3000/mcp');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });

    const check = container.querySelector(
      '[data-testid="mcp-check-connection"]',
    ) as HTMLButtonElement;
    await act(async () => {
      check.click();
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(post).toHaveBeenCalledWith('/api/mcp/servers/check-draft', {
      displayName: '',
      url: 'http://127.0.0.1:3000/mcp',
      authToken: '',
    });
    expect(container.textContent).toContain('Connected — 1 tool: list_containers');
  });
});
