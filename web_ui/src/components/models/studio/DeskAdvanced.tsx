// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'react';
import type { ImageConfig } from './types';

const SAMPLERS = ['Euler a', 'Euler', 'DPM++ 2M', 'DPM++ 2M Karras', 'DPM++ SDE Karras', 'DPM++ 2M SDE Karras', 'DDIM', 'UniPC', 'LCM'];
const SCHEDULERS = ['Automatic', 'normal', 'karras', 'exponential', 'sgm_uniform', 'simple', 'beta'];
const STYLES: Record<string, string> = {
  photorealistic: 'Photorealistic',
  anime: 'Anime / Manga',
  fantasy_art: 'Fantasy Art',
  oil_painting: 'Oil Painting',
  digital_art: 'Digital Art',
  watercolor: 'Watercolor',
};

const uniq = (names: string[]) => names.filter((name, i, all) => name && all.indexOf(name) === i);

/** Steps, CFG, sampler, scheduler, negative prompt, art style, prompt review. */
export function DeskAdvanced(props: {
  cfg: ImageConfig;
  samplers: { label: string; value: number }[];
  save: (patch: Record<string, unknown>) => Promise<boolean>;
}) {
  const { cfg, save } = props;
  const [open, setOpen] = useState(false);
  const drawThings = cfg.backend === 'drawthings';
  const scheduler = cfg.scheduler || 'Automatic';
  const summary = `${cfg.steps} steps · cfg ${cfg.cfgScale} · ${cfg.sampler} · ${scheduler}`;
  return (
    <div>
      <button type="button" onClick={() => setOpen((v) => !v)}>
        {open ? `Advanced ▾ ${summary}` : `Advanced ▸ ${summary}`}
      </button>
      {open && !drawThings ? (
        <>
          <label>
            Steps
            <input aria-label="Steps" type="range" min={1} max={50} value={cfg.steps}
              onChange={(e) => void save({ steps: Number(e.target.value) })} />
          </label>
          <label>
            CFG
            <input aria-label="CFG" type="range" min={1} max={20} step={0.5} value={cfg.cfgScale}
              onChange={(e) => void save({ cfgScale: Number(e.target.value) })} />
          </label>
          <label>
            Sampler
            <select aria-label="Sampler" value={cfg.sampler}
              onChange={(e) => void save({ sampler: e.target.value })}>
              {uniq([cfg.sampler, ...SAMPLERS]).map((name) => <option key={name}>{name}</option>)}
            </select>
          </label>
          <label>
            Scheduler
            <select aria-label="Scheduler" value={scheduler}
              onChange={(e) => void save({ scheduler: e.target.value })}>
              {uniq([scheduler, ...SCHEDULERS]).map((name) => <option key={name}>{name}</option>)}
            </select>
          </label>
        </>
      ) : null}
      {open && drawThings ? (
        <label>
          Sampler
          <select aria-label="Draw Things sampler" value={String(cfg.drawThingsSampler ?? 16)}
            onChange={(e) => void save({ drawThingsSampler: Number(e.target.value) })}>
            {props.samplers.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
        </label>
      ) : null}
      {open ? (
        <>
          <label>
            Negative prompt
            <textarea aria-label="Negative prompt" rows={2} defaultValue={cfg.negativePrompt}
              key={`neg-${cfg.negativePrompt}`}
              onBlur={(e) => e.target.value !== cfg.negativePrompt && void save({ negativePrompt: e.target.value })} />
          </label>
          <label>
            Art style
            <select aria-label="Art style" value={STYLES[cfg.style] ? cfg.style : 'photorealistic'}
              onChange={(e) => void save({ style: e.target.value })}>
              {Object.entries(STYLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="tool-toggle">
            <span>Review AI prompts before generating (/image pauses so you can edit)</span>
            <input aria-label="Review prompts" type="checkbox" checked={cfg.promptReview}
              onChange={(e) => void save({ promptReview: e.target.checked })} />
          </label>
        </>
      ) : null}
    </div>
  );
}
