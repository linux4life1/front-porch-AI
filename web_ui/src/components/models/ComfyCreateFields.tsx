// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create-family picker for the web Models page — same slots as desktop.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';

export interface ComfySlot {
  token: string;
  label: string;
  loaderClass: string;
  inputName: string;
  folderHint: string;
}

export interface ComfyPreset {
  id: string;
  label: string;
  comfyTemplateName?: string;
  usesCheckpointBuilder?: boolean;
  slots: ComfySlot[];
}

export interface ComfyCatalog {
  checkpoints: string[];
  diffusionModels: string[];
  textEncoders: string[];
  vaes: string[];
  templates?: { id: string; name: string; title: string }[];
}

function filesFor(slot: ComfySlot, cat: ComfyCatalog | null): string[] {
  if (!cat) return [];
  if (slot.folderHint === 'checkpoints' || slot.loaderClass === 'CheckpointLoaderSimple') {
    return cat.checkpoints;
  }
  if (slot.folderHint === 'diffusion_models' || slot.loaderClass === 'UNETLoader') {
    return cat.diffusionModels;
  }
  if (slot.folderHint === 'text_encoders') return cat.textEncoders;
  if (slot.folderHint === 'vae') return cat.vaes;
  return [];
}

export function ComfyCreateFields({
  workflowId,
  modelChoices,
  presets,
  onChange,
}: {
  workflowId: string;
  modelChoices: Record<string, string>;
  presets: ComfyPreset[];
  onChange: (patch: Record<string, unknown>) => void;
}) {
  const [cat, setCat] = useState<ComfyCatalog | null>(null);
  useEffect(() => {
    api
      .get<ComfyCatalog>('/api/image/comfy-catalog')
      .then(setCat)
      .catch(() => setCat({ checkpoints: [], diffusionModels: [], textEncoders: [], vaes: [] }));
  }, []);

  const bundledNames = new Set(presets.map((p) => p.comfyTemplateName).filter(Boolean));
  const live = (cat?.templates ?? []).filter((t) => !bundledNames.has(t.name));
  const preset = presets.find((p) => p.id === workflowId);
  const slots = preset?.slots ?? [];

  return (
    <>
      <label>
        Create family
        <select
          value={workflowId}
          onChange={(e) => onChange({ comfyCreateWorkflowId: e.target.value })}
        >
          {presets.map((p) => (
            <option key={p.id} value={p.id}>
              {p.label}
            </option>
          ))}
          {live.map((t) => (
            <option key={t.id} value={t.id}>
              {t.title}
            </option>
          ))}
          <option value="__uploaded__">Upload your own… (desktop)</option>
        </select>
      </label>
      {slots.map((slot) => {
        const key = `${workflowId}/${slot.token}`;
        const files = filesFor(slot, cat);
        const current = modelChoices[key] ?? '';
        return (
          <label key={key}>
            {slot.label}
            <select
              value={files.includes(current) ? current : ''}
              onChange={(e) =>
                onChange({
                  comfyCreateModelChoices: { ...modelChoices, [key]: e.target.value },
                })
              }
            >
              <option value="">{files.length ? 'pick a file' : `No files in ${slot.folderHint || 'this drawer'}`}</option>
              {files.map((f) => (
                <option key={f} value={f}>
                  {f}
                </option>
              ))}
            </select>
          </label>
        );
      })}
    </>
  );
}
