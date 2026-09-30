// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { StepUpFields } from '../../StepUpFields';
import type { ImageConfig, ReadyFacts } from './types';

const BACKENDS: [string, string][] = [
  ['remote', 'Remote'],
  ['comfyui', 'ComfyUI'],
  ['a1111', 'Automatic1111'],
  ['drawthings', 'Draw Things'],
];

export function backendName(backend: string): string {
  return BACKENDS.find(([id]) => id === backend)?.[1] ?? 'Remote';
}

/** Where the server the pictures come from lives. Changing which computer it
 *  is, is credential-grade, so it needs the web password; its port does not. */
export function DeskConnection(props: {
  cfg: ImageConfig;
  facts: ReadyFacts | null;
  totpEnabled: boolean;
  onBackend: (backend: string) => void;
  /** Saves [patch]; resolves false when the server refused it. */
  save: (patch: Record<string, unknown>) => Promise<boolean>;
  onCheck: () => void;
}) {
  const { cfg, facts, save } = props;
  const local = cfg.backend === 'comfyui' || cfg.backend === 'a1111';
  const saved = cfg.backend === 'comfyui' ? cfg.comfyUrl : cfg.backend === 'a1111' ? cfg.localUrl : cfg.drawThingsHost;
  const [address, setAddress] = useState(saved);
  const [port, setPort] = useState(String(cfg.drawThingsPort));
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  useEffect(() => setAddress(saved), [saved, cfg.backend]);
  useEffect(() => setPort(String(cfg.drawThingsPort)), [cfg.drawThingsPort]);

  const key = cfg.backend === 'comfyui' ? 'comfyUrl' : cfg.backend === 'a1111' ? 'localUrl' : 'drawThingsHost';
  const dirty = cfg.backend !== 'remote' && address.trim() !== saved;
  const portValue = Number(port);
  const portValid = Number.isInteger(portValue) && portValue > 0 && portValue < 65536;
  const portDirty = cfg.backend === 'drawthings' && portValue !== cfg.drawThingsPort;

  // The host and the port decide where this computer dials, so both need the
  // password, and are saved together.
  const saveAddress = () => {
    const patch: Record<string, unknown> = { currentPassword: password };
    if (dirty) patch[key] = address.trim();
    if (portDirty && portValid) patch.drawThingsPort = portValue;
    if (props.totpEnabled && totp.trim()) patch.totpCode = totp.trim();
    void save(patch).then((ok) => {
      if (ok) {
        setPassword('');
        setTotp('');
        props.onCheck();
      }
    });
  };

  return (
    <div>
      <div>Connection</div>
      <div>{backendName(cfg.backend)}</div>
      {cfg.backend === 'remote' ? null : (
        <>
          <label>
            {cfg.backend === 'drawthings' ? 'Draw Things host' : `${backendName(cfg.backend)} address`}
            <input
              aria-label={cfg.backend === 'drawthings' ? 'Draw Things host' : 'Server address'}
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder={cfg.backend === 'comfyui' ? 'http://127.0.0.1:8188' : cfg.backend === 'a1111' ? 'http://127.0.0.1:7860' : '127.0.0.1'}
            />
          </label>
          {cfg.backend === 'drawthings' ? (
            <label>
              gRPC port
              <input
                aria-label="Draw Things port"
                type="number"
                min={1}
                max={65535}
                value={port}
                onChange={(e) => setPort(e.target.value)}
              />
            </label>
          ) : null}
          {dirty || (portDirty && portValid) ? (
            <>
              <StepUpFields
                password={password}
                onPassword={setPassword}
                totpEnabled={props.totpEnabled}
                totpCode={totp}
                onTotp={setTotp}
                reason={
                  props.totpEnabled
                    ? 'Changing the local image host — confirm your web login password and a 2FA code.'
                    : 'Changing the local image host — confirm your web login password.'
                }
              />
              <button
                type="button"
                disabled={!password || (dirty && !address.trim())}
                onClick={saveAddress}
              >
                {dirty ? 'Save address' : 'Save port'}
              </button>
            </>
          ) : null}
          {facts?.reachable ? (
            local || cfg.backend === 'drawthings' ? (
              <p>
                {cfg.backend === 'a1111'
                  ? 'Reachable'
                  : `Reachable · ${facts.diffusionCount ?? 0} diffusion files · ${facts.loraCount ?? 0} LoRAs`}
              </p>
            ) : null
          ) : (
            <p>Not running</p>
          )}
          <button type="button" onClick={props.onCheck}>
            Check
          </button>
        </>
      )}
      <details>
        <summary>Change…</summary>
        {BACKENDS.map(([id, label]) => (
          <button key={id} type="button" aria-pressed={cfg.backend === id} onClick={() => props.onBackend(id)}>
            {label}
          </button>
        ))}
      </details>
    </div>
  );
}
