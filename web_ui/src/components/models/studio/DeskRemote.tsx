// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { ApiError } from '../../../api/client';
import { StepUpFields } from '../../StepUpFields';
import { BackendChange } from './DeskConnection';
import { STYLES } from './DeskAdvanced';
import { RemoteModelSheet } from './RemoteModelSheet';
import { fetchRemotePanel, type RemoteChoice, type RemotePanel } from './remoteApi';
import type { ImageConfig, Mode } from './types';

/** The stove for a Remote API, as the desktop draws it: host tiles, the key
 *  box when the host has no key, the model, the sizes that host takes, and
 *  Generate. Nothing a Remote API ignores (graphs, LoRAs, samplers) is here. */
export function DeskRemote(props: {
  cfg: ImageConfig;
  mode: Mode;
  busy: boolean;
  totpEnabled: boolean;
  onBackend: (backend: string) => void;
  /** Saves [patch]; resolves false when the computer refused it. */
  save: (patch: Record<string, unknown>) => Promise<boolean>;
  /** Picks the model on the desk for [mode]. */
  onModel: (id: string) => Promise<void>;
  /** Judges Ready again after a change here. */
  onChanged: () => void;
  readyLine: string;
  generateDisabled: boolean;
  showGenerate: boolean;
  onGenerate: () => void;
}) {
  const { cfg, mode, save } = props;
  const [panel, setPanel] = useState<RemotePanel | null>(null);
  const [problem, setProblem] = useState('');
  const [ask, setAsk] = useState({ tick: 0, refresh: true });
  const [key, setKey] = useState('');
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [sheet, setSheet] = useState(false);
  const [promptOpen, setPromptOpen] = useState(false);

  const editKey = mode === 'edit' ? cfg.editModel : cfg.model;
  useEffect(() => {
    let live = true;
    fetchRemotePanel(mode, ask.refresh)
      .then((next) => {
        if (!live) return;
        setPanel(next);
        setProblem('');
      })
      .catch((e) => live && setProblem(e instanceof ApiError && e.message ? e.message : 'Could not read the Remote API.'));
    return () => {
      live = false;
    };
  }, [mode, ask, cfg.imageRemoteHost, editKey, cfg.hasApiKey]);

  const reread = (refresh: boolean) => setAsk((a) => ({ tick: a.tick + 1, refresh }));
  const write = (patch: Record<string, unknown>, refresh = false) =>
    void save(patch).then((ok) => {
      if (!ok) return;
      reread(refresh);
      props.onChanged();
    });

  const saveKey = () => {
    const body: Record<string, unknown> = { apiKey: key.trim(), currentPassword: password };
    if (props.totpEnabled && totp.trim()) body.totpCode = totp.trim();
    void save(body).then((ok) => {
      if (!ok) return;
      setKey('');
      setPassword('');
      setTotp('');
      reread(true);
      props.onChanged();
    });
  };

  const pills = (choices: RemoteChoice[], onPick: (value: string) => void) => (
    <div className="fp-remote-pills">
      {choices.map((c) => (
        <button key={c.value} type="button" className="fp-pill" aria-pressed={c.selected}
          onClick={() => onPick(c.value)}>
          {c.label}
        </button>
      ))}
    </div>
  );

  const readyLine = panel?.needsKey ? panel.needsKeyLine : props.readyLine;
  const showModel = panel !== null && !panel.needsKey;

  return (
    <div className="fp-remote">
      <section aria-label="Connection" className="fp-remote-group">
        <div className="fp-remote-head">
          <div className="fp-remote-label">Connection</div>
          <BackendChange backend={cfg.backend} onBackend={props.onBackend} />
        </div>
        <div className="fp-remote-title">Remote API</div>
        {panel ? (
          <>
            <div role="radiogroup" aria-label="Remote host" className="fp-remote-hosts">
              {panel.hosts.map((h) => (
                <button key={h.id} type="button" role="radio" aria-checked={h.selected}
                  data-testid={`image-remote-host-${h.id}`}
                  className={`fp-remote-host${h.selected ? ' on' : ''}${h.hasKey ? '' : ' keyless'}`}
                  onClick={() => write({ imageRemoteHost: h.id, ...(mode === 'edit' ? { mode: 'edit' } : {}) }, true)}>
                  <span className="fp-remote-host-name">{h.label}</span>
                  <span className="fp-remote-host-sub">{h.sub}</span>
                </button>
              ))}
            </div>
            <div className="fp-remote-where">
              <div>{panel.url}</div>
              <div className="fp-remote-billing">{panel.billing}</div>
            </div>
            {panel.needsKey ? (
              <div className="fp-remote-key">
                <label htmlFor="fp-remote-key">{panel.keyPrompt}</label>
                <div className="fp-remote-key-row">
                  <input id="fp-remote-key" type="password" autoComplete="off" placeholder={panel.keyHint}
                    value={key} onChange={(e) => setKey(e.target.value)} />
                  <button type="button" className="fp-remote-save"
                    disabled={!key.trim() || !password} onClick={saveKey}>
                    Save key
                  </button>
                </div>
                {key.trim() ? (
                  <StepUpFields
                    password={password}
                    onPassword={setPassword}
                    totpEnabled={props.totpEnabled}
                    totpCode={totp}
                    onTotp={setTotp}
                    reason={props.totpEnabled
                      ? 'Saving a key — confirm your web login password and a 2FA code.'
                      : 'Saving a key — confirm your web login password.'}
                  />
                ) : null}
                <div className="fp-remote-note">{panel.keyNote}</div>
              </div>
            ) : (
              <div className="fp-remote-status">
                <span>{panel.status}</span>
                <button type="button" className="fp-remote-link" onClick={() => {
                  reread(true);
                  props.onChanged();
                }}>
                  Check
                </button>
              </div>
            )}
          </>
        ) : (
          <p className="fp-remote-note">{problem || 'Loading…'}</p>
        )}
      </section>

      {showModel ? (
        <section aria-label="Model" className="fp-remote-group fp-remote-rule">
          <div className="fp-remote-label">Model</div>
          <div className="fp-remote-model">{panel.modelName}</div>
          {panel.modelId && panel.modelId !== panel.modelName ? (
            <div className="fp-remote-id">{panel.modelId}</div>
          ) : null}
          {panel.badges.length ? (
            <div className="fp-remote-badges">
              {panel.badges.map((b) => <span key={b} className="fp-remote-badge">{b}</span>)}
            </div>
          ) : null}
          {panel.price ? <div className="fp-remote-price">{panel.price}</div> : null}
          <div>
            <button type="button" className="fp-remote-link fp-remote-change" onClick={() => setSheet(true)}>
              Change model
            </button>
          </div>
        </section>
      ) : null}

      {showModel ? (
        <section aria-label="Size" className="fp-remote-group fp-remote-rule">
          <div className="fp-remote-label">{panel.sizeMode === 'none' ? 'Size' : panel.sizeTitle}</div>
          {panel.sizeMode === 'none' ? (
            <div className="fp-remote-price">{panel.sizeNote}</div>
          ) : (
            <>
              {pills(panel.sizes, (value) =>
                write(panel.sizeMode === 'xai' ? { xaiAspect: value } : { remoteSize: value, mode }))}
              {panel.sizeMode === 'xai' ? (
                <>
                  <div className="fp-remote-label">Resolution</div>
                  {pills(panel.resolutions, (value) => write({ xaiResolution: value }))}
                </>
              ) : null}
              <div className="fp-remote-note">{panel.sizeNote}</div>
            </>
          )}
        </section>
      ) : null}

      <div>
        <button type="button" className="fp-remote-fold" aria-expanded={promptOpen}
          onClick={() => setPromptOpen((v) => !v)}>
          {promptOpen ? 'Prompt options ▾' : 'Prompt options ▸'}
        </button>
        {promptOpen ? (
          <div className="fp-remote-group">
            <label className="tool-toggle">
              <span>Review AI prompts before generating (/image pauses so you can edit)</span>
              <input aria-label="Review prompts" type="checkbox" checked={cfg.promptReview}
                onChange={(e) => void save({ promptReview: e.target.checked })} />
            </label>
            {mode === 'create' ? (
              <label>
                Art style
                <select aria-label="Art style" value={STYLES[cfg.style] ? cfg.style : 'photorealistic'}
                  onChange={(e) => void save({ style: e.target.value })}>
                  {Object.entries(STYLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </label>
            ) : (
              <div className="fp-remote-note">Style and Prompt format are in Create mode.</div>
            )}
          </div>
        ) : null}
      </div>

      <div className="fp-remote-foot fp-remote-rule">
        <span>{readyLine}</span>
        {props.showGenerate ? (
          <button type="button" className="fp-remote-generate"
            disabled={props.generateDisabled || panel?.needsKey !== false}
            onClick={props.onGenerate}>
            Generate
          </button>
        ) : null}
      </div>

      {sheet && !props.busy ? (
        <RemoteModelSheet
          current={panel?.modelId ?? ''}
          onClose={() => setSheet(false)}
          onPick={(id) => {
            setSheet(false);
            void props.onModel(id).then(() => {
              reread(false);
              props.onChanged();
            });
          }}
        />
      ) : null}
    </div>
  );
}
