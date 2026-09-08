// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Connect Docker MCP posts docker-easy; stdio command uses check-draft.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const get = vi.fn(async (_url?: string) => ({
  mcpDefault: false,
  servers: [] as unknown[],
}));
const post = vi.fn(async (url: string, _body?: unknown) => {
  if (url === '/api/mcp/servers/docker-easy') {
    return {
      mcpDefault: false,
      servers: [
        {
          id: 'mcp_docker',
          displayName: 'Docker',
          url: 'docker mcp gateway run',
          transport: 'stdio',
          status: 'connected',
          enabledGlobal: true,
          toolNames: ['list_containers'],
          conflictToolNames: [],
        },
      ],
      checkResult: 'Connected — 1 tool: list_containers',
    };
  }
  if (url === '/api/mcp/servers/check-draft') {
    return {
      mcpDefault: false,
      servers: [],
      checkResult: 'Connected — 1 tool: ping',
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

const { McpSettings } = await import('./McpSettings');

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

describe('MCP stdio + Docker-easy', () => {
  it('Connect Docker MCP posts docker-easy', async () => {
    const btn = container.querySelector(
      '[data-testid="mcp-docker-stdio"]',
    ) as HTMLButtonElement;
    expect(btn).toBeTruthy();
    await act(async () => {
      btn.click();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(post).toHaveBeenCalledWith('/api/mcp/servers/docker-easy', {});
    expect(container.textContent).toContain('Connected — 1 tool: list_containers');
  });

  it('stdio command Check posts transport stdio', async () => {
    const input = container.querySelector(
      '[data-testid="mcp-add-command"]',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )!.set!;
      setter.call(input, 'npx -y @playwright/mcp');
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
      url: '',
      authToken: '',
      transport: 'stdio',
      command: 'npx',
      args: ['-y', '@playwright/mcp'],
    });
  });
});
