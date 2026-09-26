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

interface LiveComfySlot extends ComfySlot {
  files: string[];
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
  templates?: { id: string; name: string; title: string; source: string }[];
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
  onChange: (patch: Record<string, unknown>) => Promise<boolean>;
}) {
  const [cat, setCat] = useState<ComfyCatalog | null>(null);
  const [liveSlots, setLiveSlots] = useState<LiveComfySlot[] | null>(null);
  const [uploadRevision, setUploadRevision] = useState(0);
  const [uploadError, setUploadError] = useState('');
  useEffect(() => {
    api
      .get<ComfyCatalog>('/api/image/comfy-catalog')
      .then(setCat)
      .catch(() => setCat({ checkpoints: [], diffusionModels: [], textEncoders: [], vaes: [] }));
  }, []);

  useEffect(() => {
    let active = true;
    setLiveSlots(null);
    api.get<{ slots: LiveComfySlot[] }>(
      `/api/image/comfy-workflow-slots?workflowId=${encodeURIComponent(workflowId)}`,
    ).then((result) => { if (active) setLiveSlots(result.slots); })
      .catch(() => { if (active) setLiveSlots([]); });
    return () => { active = false; };
  }, [workflowId, uploadRevision]);

  const bundledNames = new Set(presets.map((p) => p.comfyTemplateName).filter(Boolean));
  const live = (cat?.templates ?? []).filter(
    (template) => template.source === 'userdata' || !bundledNames.has(template.name),
  );
  const slots = liveSlots ?? [];
  const knownIds = new Set([
    ...presets.map((preset) => preset.id),
    ...live.map((template) => template.id),
    '__uploaded__',
  ]);

  const uploadWorkflow = async (file: File | undefined) => {
    if (!file) return;
    try {
      const json = await file.text();
      const value: unknown = JSON.parse(json);
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('Choose a ComfyUI workflow JSON object.');
      }
      const saved = await onChange({ comfyCreateUploadedWorkflow: json, comfyCreateWorkflowId: '__uploaded__' });
      if (!saved) throw new Error('Could not save workflow.');
      setUploadError('');
      setUploadRevision((n) => n + 1);
    } catch (error) {
      setUploadError(error instanceof Error ? error.message : 'Could not load workflow');
    }
  };

  return (
    <>
      <label>
        Create family
        <select
          value={workflowId}
          disabled={cat === null}
          onChange={(e) => onChange({ comfyCreateWorkflowId: e.target.value })}
        >
          {presets.map((p) => (
            <option key={p.id} value={p.id}>
              {p.label}
            </option>
          ))}
          {live.map((t) => (
            <option key={t.id} value={t.id}>
              {t.source === 'userdata' ? 'Saved' : 'ComfyUI'} · {t.title}
            </option>
          ))}
          {!knownIds.has(workflowId) && (
            <option value={workflowId}>{workflowId.replace(/^comfy:/, 'Saved · ')}</option>
          )}
          <option value="__uploaded__">Upload your own…</option>
        </select>
      </label>
      {workflowId === '__uploaded__' && (
        <label>ComfyUI workflow JSON
          <input type="file" accept=".json,application/json" onChange={(e) => void uploadWorkflow(e.target.files?.[0])} />
          {uploadError && <span role="alert">{uploadError}</span>}
        </label>
      )}
      {liveSlots === null && <p className="muted small">Loading model choices…</p>}
      {slots.map((slot) => {
        const key = `${workflowId}/${slot.token}`;
        const files = slot.files;
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
