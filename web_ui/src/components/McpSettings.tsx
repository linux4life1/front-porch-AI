// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web Settings: MCP server list, status, tool inventory, add/remove.

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
}

export function McpSettings() {
  const [st, setSt] = useState<McpState | null>(null);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [token, setToken] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setSt(await api.get<McpState>('/api/mcp/servers'));
    } catch {
      /* host not serving MCP yet */
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (!st) return null;

  const apply = (p: Promise<McpState>) => {
    void p.then(setSt).catch(() => {});
  };

  return (
    <section className="card">
      <h3>MCP servers</h3>
      <p className="muted small">
        Connect to tools the character can call. Connecting a server is not
        consent — each chat has its own switches. Front Porch does not spawn
        servers; you run them, we connect over HTTP.
      </p>
      <label className="toggle-row">
        <span>Enable for new chats</span>
        <input
          type="checkbox"
          checked={st.mcpDefault}
          onChange={(e) =>
            apply(api.post<McpState>('/api/mcp/servers/default', { mcpDefault: e.target.checked }))
          }
        />
      </label>
      {st.servers.length === 0 && (
        <p className="muted small">No servers yet.</p>
      )}
      {st.servers.map((s) => (
        <div key={s.id} className="mcp-server-row" style={{ marginTop: 8 }}>
          <div>
            <strong>{s.displayName}</strong>
            <div className="muted small">{s.url}</div>
            <div className="muted small">
              {s.status}
              {s.lastError ? ` — ${s.lastError}` : ''}
            </div>
            {s.toolNames.length > 0 && (
              <div className="muted small">Tools: {s.toolNames.join(', ')}</div>
            )}
            {s.conflictToolNames.length > 0 && (
              <div className="muted small">
                Name collision — omitted: {s.conflictToolNames.join(', ')}
              </div>
            )}
          </div>
          <label className="toggle-row">
            <span>On</span>
            <input
              type="checkbox"
              checked={s.enabledGlobal}
              onChange={(e) =>
                apply(
                  api.post<McpState>(`/api/mcp/servers/${encodeURIComponent(s.id)}`, {
                    enabledGlobal: e.target.checked,
                  }),
                )
              }
            />
          </label>
          <button
            className="ghost"
            onClick={() =>
              apply(api.post<McpState>(`/api/mcp/servers/${encodeURIComponent(s.id)}/refresh`))
            }
          >
            Refresh
          </button>
          <button
            className="ghost"
            onClick={() =>
              apply(api.post<McpState>(`/api/mcp/servers/${encodeURIComponent(s.id)}/delete`))
            }
          >
            Remove
          </button>
        </div>
      ))}
      <div style={{ marginTop: 12 }}>
        <input
          placeholder="Display name"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <input
          placeholder="URL (Streamable HTTP or SSE)"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
        />
        <input
          placeholder="Auth token (optional)"
          type="password"
          value={token}
          onChange={(e) => setToken(e.target.value)}
        />
        <button
          className="primary"
          disabled={busy || !url.trim()}
          onClick={() => {
            setBusy(true);
            apply(
              api
                .post<McpState>('/api/mcp/servers', {
                  displayName: name,
                  url,
                  authToken: token,
                })
                .finally(() => {
                  setBusy(false);
                  setName('');
                  setUrl('');
                  setToken('');
                }),
            );
          }}
        >
          Add server
        </button>
      </div>
    </section>
  );
}
