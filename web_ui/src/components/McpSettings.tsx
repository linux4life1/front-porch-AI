// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life: MCP server list, address, Check connection. Connecting is not
// consent — each chat has its own switches.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

interface McpServer {
  id: string;
  displayName: string;
  url: string;
  status: string;
  lastError?: string | null;
  enabledGlobal: boolean;
  toolNames: string[];
  conflictToolNames: string[];
}

interface McpState {
  mcpDefault: boolean;
  servers: McpServer[];
  checkResult?: string;
}

function emptyState(): McpState {
  return { mcpDefault: false, servers: [] };
}

const DOCKER_CMD =
  'docker mcp gateway run --transport streaming --port 8811';
const DOCKER_MCP_URL = 'http://127.0.0.1:8811/mcp';

export function mcpToolsPhrase(names: string[]): string {
  if (names.length === 0) return 'no tools advertised';
  const n = names.length;
  const noun = n === 1 ? 'tool' : 'tools';
  if (n <= 3) return `${n} ${noun}: ${names.join(', ')}`;
  return `${n} ${noun}`;
}

export function mcpHumanizeConnectError(
  lastError?: string | null,
  url = '',
): string {
  const raw = (lastError ?? '').trim();
  if (!raw) return '';
  const lower = raw.toLowerCase();
  const refused =
    lower.includes('connection refused') ||
    lower.includes('errno = 61') ||
    (lower.includes('socketexception') && lower.includes('refused'));
  if (refused) {
    if (url.includes('8811') || raw.includes('8811')) {
      return (
        'Nothing is listening there. Docker Desktop MCP does not open a URL. In a terminal: ' +
        DOCKER_CMD
      );
    }
    return 'Nothing is listening at that address.';
  }
  if (lower.includes('401') || lower.includes('unauthorized')) {
    return 'This server wants a token. If you started the Docker gateway, it printed a Bearer token when it started.';
  }
  if (lower.includes('clientexception') || lower.includes('socketexception')) {
    return 'Could not connect. Is the server running?';
  }
  return raw;
}

export function mcpCheckResultLine(opts: {
  url: string;
  status: string;
  toolNames: string[];
  lastError?: string | null;
}): string {
  const url = opts.url.trim();
  if (!url) return 'Enter a server address first';
  if (opts.status === 'connected') {
    return `Connected — ${mcpToolsPhrase(opts.toolNames)}`;
  }
  const reason = mcpHumanizeConnectError(opts.lastError, url);
  if (
    reason.startsWith('Nothing is listening') ||
    reason.startsWith('This server wants')
  ) {
    return reason;
  }
  return reason ? `Could not reach ${url} — ${reason}` : `Could not reach ${url}`;
}

export function McpSettings() {
  const [st, setSt] = useState<McpState>(emptyState);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [command, setCommand] = useState('');
  const [token, setToken] = useState('');
  const [busy, setBusy] = useState(false);
  const [wantToken, setWantToken] = useState(false);
  const [result, setResult] = useState('');
  const [edits, setEdits] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    try {
      const raw = await api.get<Partial<McpState>>('/api/mcp/servers');
      setSt({
        mcpDefault: raw.mcpDefault === true,
        servers: Array.isArray(raw.servers) ? raw.servers : [],
      });
    } catch {
      /* host not serving MCP yet */
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const apply = (p: Promise<McpState>) => {
    void p
      .then((next) => {
        setSt({
          mcpDefault: next.mcpDefault === true,
          servers: Array.isArray(next.servers) ? next.servers : [],
        });
        if (next.checkResult) setResult(next.checkResult);
      })
      .catch(() => {});
  };

  const connectDockerEasy = async () => {
    setBusy(true);
    try {
      const checked = await api.post<McpState>(
        '/api/mcp/servers/docker-easy',
        {},
      );
      setSt({
        mcpDefault: checked.mcpDefault === true,
        servers: Array.isArray(checked.servers) ? checked.servers : [],
      });
      setResult(checked.checkResult ?? '');
    } catch {
      setResult('Could not start Docker MCP.');
    } finally {
      setBusy(false);
    }
  };

  const checkDraft = async () => {
    const cmd = command.trim();
    const trimmed = url.trim();
    if (!trimmed && !cmd) {
      setResult(mcpCheckResultLine({ url: '', status: 'disconnected', toolNames: [] }));
      return;
    }
    setBusy(true);
    try {
      const checked = await api.post<McpState & { wantsToken?: boolean }>(
        '/api/mcp/servers/check-draft',
        cmd
          ? {
              displayName: name,
              url: trimmed,
              authToken: token,
              transport: 'stdio',
              command: cmd.split(/\s+/)[0] ?? cmd,
              args: cmd.split(/\s+/).slice(1),
            }
          : { displayName: name, url: trimmed, authToken: token },
      );
      setSt({
        mcpDefault: checked.mcpDefault === true,
        servers: Array.isArray(checked.servers) ? checked.servers : [],
      });
      setResult(checked.checkResult ?? '');
      if (checked.wantsToken) setWantToken(true);
      if ((checked.checkResult ?? '').startsWith('Connected')) {
        setName('');
        setUrl('');
        setCommand('');
        setToken('');
        setWantToken(false);
      }
    } catch {
      setResult(
        mcpCheckResultLine({
          url: trimmed,
          status: 'error',
          toolNames: [],
          lastError: 'connection refused',
        }),
      );
    } finally {
      setBusy(false);
    }
  };

  const findLocal = async () => {
    setBusy(true);
    try {
      const found = await api.get<
        McpState & { found?: boolean; url?: string }
      >('/api/mcp/servers/find-local');
      if (found.url) setUrl(found.url);
      if (found.checkResult) setResult(found.checkResult);
    } catch {
      setResult('Could not look for a local gateway.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mcp-porch-life">
      <label className="toggle-row">
        <span>MCP tools</span>
        <input
          type="checkbox"
          checked={st.mcpDefault}
          onChange={(e) =>
            apply(
              api.post<McpState>('/api/mcp/servers/default', {
                mcpDefault: e.target.checked,
              }),
            )
          }
        />
      </label>
      <p className="muted small">
        Connect Docker MCP starts Docker Desktop’s toolkit on stdio — one tap,
        no URL. Or tap Docker, then Check, for the HTTP gateway. A token is
        only needed if the HTTP server asks.
      </p>
      <div className="mcp-presets">
        <button
          type="button"
          data-testid="mcp-docker-stdio"
          className="ghost"
          disabled={busy}
          onClick={() => void connectDockerEasy()}
        >
          Connect Docker MCP
        </button>
        <button
          type="button"
          data-testid="mcp-docker-preset"
          className="ghost"
          disabled={busy}
          onClick={() => {
            setUrl(DOCKER_MCP_URL);
            if (!name.trim()) setName('Docker');
          }}
        >
          Docker
        </button>
        <button
          type="button"
          data-testid="mcp-find-local"
          className="ghost"
          disabled={busy}
          onClick={() => void findLocal()}
        >
          Find local servers
        </button>
      </div>
      <input
        data-testid="mcp-add-url"
        placeholder="Or paste a URL"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
      />
      <input
        data-testid="mcp-add-command"
        placeholder="Or a stdio command (npx -y @scope/mcp-server)"
        value={command}
        onChange={(e) => setCommand(e.target.value)}
      />
      {wantToken && (
        <input
          data-testid="mcp-add-token"
          placeholder="Bearer token (printed when the gateway started)"
          type="password"
          value={token}
          onChange={(e) => setToken(e.target.value)}
        />
      )}
      <button
        className="primary"
        data-testid="mcp-check-connection"
        disabled={busy}
        onClick={() => void checkDraft()}
      >
        {busy ? 'Checking…' : 'Check connection'}
      </button>
      {result && <p className="muted small">{result}</p>}
      {st.servers.map((s) => (
        <div key={s.id} className="mcp-server-row" style={{ marginTop: 8 }}>
          <div>
            <strong>{s.displayName}</strong>
            <input
              value={edits[s.id] ?? s.url}
              onChange={(e) =>
                setEdits((cur) => ({ ...cur, [s.id]: e.target.value }))
              }
            />
            <div className="muted small">
              {s.status}
              {s.lastError ? ` — ${s.lastError}` : ''}
            </div>
            {s.toolNames.length > 0 && (
              <div className="muted small">{mcpToolsPhrase(s.toolNames)}</div>
            )}
          </div>
          <label className="toggle-row">
            <span>On</span>
            <input
              type="checkbox"
              checked={s.enabledGlobal}
              onChange={(e) =>
                apply(
                  api.post<McpState>(
                    `/api/mcp/servers/${encodeURIComponent(s.id)}`,
                    { enabledGlobal: e.target.checked },
                  ),
                )
              }
            />
          </label>
          <button
            className="ghost"
            disabled={busy}
            onClick={() => {
              const nextUrl = (edits[s.id] ?? s.url).trim();
              setBusy(true);
              void (async () => {
                try {
                  if (nextUrl && nextUrl !== s.url) {
                    await api.post(`/api/mcp/servers/${encodeURIComponent(s.id)}`, {
                      url: nextUrl,
                    });
                  }
                  const checked = await api.post<McpState>(
                    `/api/mcp/servers/${encodeURIComponent(s.id)}/check`,
                  );
                  setSt({
                    mcpDefault: checked.mcpDefault === true,
                    servers: Array.isArray(checked.servers) ? checked.servers : [],
                  });
                  setResult(checked.checkResult ?? '');
                } finally {
                  setBusy(false);
                }
              })();
            }}
          >
            Check connection
          </button>
          <button
            className="ghost"
            onClick={() =>
              apply(
                api.post<McpState>(
                  `/api/mcp/servers/${encodeURIComponent(s.id)}/delete`,
                ),
              )
            }
          >
            Remove
          </button>
        </div>
      ))}
    </div>
  );
}
