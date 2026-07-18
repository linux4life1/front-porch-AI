// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { api, ApiError } from '../api/client';

interface TunnelState {
  installed: boolean;
  running: boolean;
  url: string | null;
  installUrl: string;
  // tailscale
  needsLogin?: boolean;
  magicDnsName?: string | null;
  enableHttpsUrl?: string;
  httpsState?: string | null;
  // ngrok
  authTokenUrl?: string;
  hasAuthToken?: boolean;
}
interface RemoteStatus {
  port: number;
  tailscale: TunnelState;
  ngrok: TunnelState;
  portForward: { port: number; hint: string };
}

/** URL + copy button + a QR to scan from a phone. */
function TunnelResult({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard?.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard unavailable on insecure origins — URL is still selectable */
    }
  };
  return (
    <div className="tunnel-result">
      <div className="tunnel-url-row">
        <a className="tunnel-url" href={url}>{url}</a>
        <button onClick={copy}>{copied ? 'Copied' : 'Copy'}</button>
      </div>
      <div className="qr">
        <QRCodeSVG value={url} size={160} />
      </div>
      <p className="muted small">Scan with your phone to open and install the app.</p>
    </div>
  );
}

export function RemoteAccessPage() {
  const [status, setStatus] = useState<RemoteStatus | null>(null);
  const [ngrokToken, setNgrokToken] = useState('');
  const [loginUrl, setLoginUrl] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState('');

  const load = () =>
    api.get<RemoteStatus>('/api/remote/status').then(setStatus).catch(() => {});
  useEffect(() => {
    void load();
  }, []);

  const act = async (key: string, fn: () => Promise<unknown>) => {
    setBusy(key);
    setError('');
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Action failed');
    } finally {
      setBusy('');
    }
  };

  if (!status) return <div className="centered"><div className="spinner" /></div>;
  const { tailscale: ts, ngrok } = status;

  return (
    <div className="page">
      <div className="page-head">
        <h2>Remote access</h2>
        <button className="ghost" onClick={() => void load()}>Re-check</button>
      </div>

      {!window.isSecureContext && (
        <div className="callout">
          You're on an insecure connection, so this can't be installed as an app
          (no offline / push / mic). For full mobile install, use
          <strong> Tailscale</strong> (recommended) or <strong>ngrok</strong> below —
          both give a real, warning-free HTTPS address. A plain home-network
          address works in a browser tab only.
        </div>
      )}

      {/* ── Tailscale ──────────────────────────────────────────── */}
      <section className="card">
        <div className="card-head">
          <h3>Tailscale</h3>
          <span className="badge">Recommended</span>
          {ts.running && <span className="pill ok">running</span>}
        </div>

        {!ts.installed ? (
          <>
            <p className="muted">
              Tailscale gives this machine a private, warning-free HTTPS address you
              can reach from anywhere on your devices.
            </p>
            <ol className="steps">
              <li>Install Tailscale and sign in on this computer.</li>
              <li>Install it on your phone and sign in with the same account.</li>
              <li>Come back here and click <em>Re-check</em>.</li>
            </ol>
            <a className="btn-link primary" href={ts.installUrl} target="_blank" rel="noreferrer">
              Download Tailscale
            </a>
          </>
        ) : ts.needsLogin ? (
          <>
            <p className="muted">Tailscale is installed but not signed in on this machine.</p>
            {loginUrl ? (
              <>
                <a className="tunnel-url" href={loginUrl} target="_blank" rel="noreferrer">
                  {loginUrl}
                </a>
                <p className="muted small">Open that link, sign in, then click Re-check.</p>
              </>
            ) : (
              <button
                className="primary"
                disabled={busy === 'tslogin'}
                onClick={() =>
                  act('tslogin', async () => {
                    const r = await api.post<{ url: string }>('/api/remote/tailscale/login');
                    setLoginUrl(r.url);
                  })
                }
              >
                {busy === 'tslogin' ? 'Getting link…' : 'Get sign-in link'}
              </button>
            )}
          </>
        ) : ts.url ? (
          <>
            <TunnelResult url={ts.url} />
            <button
              disabled={busy === 'ts'}
              onClick={() => act('ts', () => api.post('/api/remote/tailscale', { enable: false }))}
            >
              Disable
            </button>
          </>
        ) : (
          <>
            <p className="muted">Signed in and ready. Turn on HTTPS to get your address.</p>
            <button
              className="primary"
              disabled={busy === 'ts'}
              onClick={() => act('ts', () => api.post('/api/remote/tailscale', { enable: true }))}
            >
              {busy === 'ts' ? 'Starting…' : 'Enable HTTPS access'}
            </button>
            {ts.enableHttpsUrl && (
              <a className="help-link" href={ts.enableHttpsUrl} target="_blank" rel="noreferrer">
                HTTPS not turning on? Enable certificates for your tailnet (one-time, free)
              </a>
            )}
          </>
        )}
      </section>

      {/* ── ngrok ──────────────────────────────────────────────── */}
      <section className="card">
        <div className="card-head">
          <h3>ngrok</h3>
          {ngrok.running && <span className="pill ok">running</span>}
        </div>

        {!ngrok.installed ? (
          <>
            <p className="muted">
              ngrok exposes this machine over a temporary public HTTPS URL — handy
              for quick sharing.
            </p>
            <ol className="steps">
              <li>Install ngrok and create a free account.</li>
              <li>Copy your authtoken, paste it here, then Start.</li>
            </ol>
            <a className="btn-link primary" href={ngrok.installUrl} target="_blank" rel="noreferrer">
              Download ngrok
            </a>
          </>
        ) : ngrok.url ? (
          <>
            <TunnelResult url={ngrok.url} />
            <button
              disabled={busy === 'ng'}
              onClick={() => act('ng', () => api.post('/api/remote/ngrok', { enable: false }))}
            >
              Disable
            </button>
          </>
        ) : (
          <>
            {ngrok.hasAuthToken ? (
              <p className="muted">Authtoken saved.</p>
            ) : (
              <label>
                Auth token
                <input
                  type="password"
                  value={ngrokToken}
                  onChange={(e) => setNgrokToken(e.target.value)}
                  placeholder="paste your ngrok authtoken"
                />
                {ngrok.authTokenUrl && (
                  <a className="help-link" href={ngrok.authTokenUrl} target="_blank" rel="noreferrer">
                    Where do I find my authtoken?
                  </a>
                )}
              </label>
            )}
            <button
              className="primary"
              disabled={busy === 'ng' || (!ngrok.hasAuthToken && !ngrokToken)}
              onClick={() =>
                act('ng', () =>
                  api.post('/api/remote/ngrok', { enable: true, authToken: ngrokToken || undefined }),
                )
              }
            >
              {busy === 'ng' ? 'Starting…' : 'Start ngrok tunnel'}
            </button>
          </>
        )}
      </section>

      {/* ── Port forwarding ────────────────────────────────────── */}
      <section className="card">
        <h3>Port forwarding (advanced)</h3>
        <p className="muted">{status.portForward.hint}</p>
      </section>

      {error && <p className="error">{error}</p>}
    </div>
  );
}
