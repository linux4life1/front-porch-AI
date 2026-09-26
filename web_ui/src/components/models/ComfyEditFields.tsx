// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { ComfyPreset, ComfySlot } from './ComfyCreateFields';

interface LiveSlot extends ComfySlot {
  files: string[];
}

interface WorkflowChoice {
  id: string;
  title: string;
  source: string;
}

export function ComfyEditFields({
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
  const [workflows, setWorkflows] = useState<WorkflowChoice[] | null>(null);
  const [slots, setSlots] = useState<LiveSlot[] | null>(null);
  const [uploadRevision, setUploadRevision] = useState(0);
  const [uploadError, setUploadError] = useState('');

  useEffect(() => {
    api.get<{ editTemplates: WorkflowChoice[] }>('/api/image/comfy-catalog')
      .then((result) => setWorkflows(result.editTemplates ?? []))
      .catch(() => setWorkflows([]));
  }, []);

  useEffect(() => {
    let active = true;
    setSlots(null);
    api.get<{ slots: LiveSlot[] }>(
      `/api/image/comfy-workflow-slots?kind=edit&workflowId=${encodeURIComponent(workflowId)}`,
    ).then((result) => { if (active) setSlots(result.slots); })
      .catch(() => { if (active) setSlots([]); });
    return () => { active = false; };
  }, [workflowId, uploadRevision]);

  const uploadWorkflow = async (file: File | undefined) => {
    if (!file) return;
    try {
      const json = await file.text();
      const value: unknown = JSON.parse(json);
      if (!value || typeof value !== 'object' || Array.isArray(value) ||
          !json.includes('%IMAGE%') || !json.includes('%PROMPT%')) {
        throw new Error('Choose an API workflow with %IMAGE% and %PROMPT% placeholders.');
      }
      const saved = await onChange({
        comfyEditUploadedWorkflow: json,
        comfyEditWorkflowId: '__uploaded__',
      });
      if (!saved) throw new Error('Could not save workflow.');
      setUploadError('');
      setUploadRevision((revision) => revision + 1);
    } catch (error) {
      setUploadError(error instanceof Error ? error.message : 'Could not load workflow');
    }
  };

  const knownIds = new Set([
    ...presets.map((preset) => preset.id),
    ...(workflows ?? []).map((workflow) => workflow.id),
    '__uploaded__',
  ]);
  return (
    <fieldset disabled={workflows === null} className="comfy-edit-fields">
      <legend>Edit workflow</legend>
      <label>
        Workflow
        <select
          value={workflowId}
          onChange={(event) => void onChange({ comfyEditWorkflowId: event.target.value })}
        >
          {presets.map((preset) => (
            <option key={preset.id} value={preset.id}>{preset.label}</option>
          ))}
          {(workflows ?? []).map((workflow) => (
            <option key={workflow.id} value={workflow.id}>
              {workflow.source === 'userdata' ? 'Saved' : 'ComfyUI'} · {workflow.title}
            </option>
          ))}
          {!knownIds.has(workflowId) && (
            <option value={workflowId}>{workflowId.replace(/^comfy:/, 'Saved · ')}</option>
          )}
          <option value="__uploaded__">Upload your own…</option>
        </select>
      </label>
      {workflowId === '__uploaded__' && (
        <label>
          API workflow JSON
          <input type="file" accept=".json,application/json"
            onChange={(event) => void uploadWorkflow(event.target.files?.[0])} />
          {uploadError && <span role="alert">{uploadError}</span>}
        </label>
      )}
      {slots === null && <p className="muted small">Loading model choices…</p>}
      {(slots ?? []).map((slot) => {
        const key = `${workflowId}/${slot.token}`;
        const current = modelChoices[key] ?? '';
        return (
          <label key={key}>
            {slot.label}
            <select
              value={slot.files.includes(current) ? current : ''}
              onChange={(event) => void onChange({
                comfyEditModelChoices: { ...modelChoices, [key]: event.target.value },
              })}
            >
              <option value="">{slot.files.length ? 'pick a file' : 'No files for this loader'}</option>
              {slot.files.map((file) => (
                <option key={file} value={file}>{file}</option>
              ))}
            </select>
          </label>
        );
      })}
    </fieldset>
  );
}
