// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { familyLabel } from './deskRules';
import type { ImageConfig, Mode, ReadyFacts } from './types';

/** The token that holds the primary file; every other slot is a support file. */
const isSupportToken = (token: string) => token.includes('CLIP') || token.includes('VAE');

function why(cfg: ImageConfig, mode: Mode, facts: ReadyFacts | null, file: string): string {
  const id = facts?.workflowId ?? (mode === 'edit' ? cfg.comfyEditWorkflowId : cfg.comfyCreateWorkflowId) ?? '';
  if (id === '__uploaded__') {
    return `Workflow · your file · ${facts?.uploadedTitle || 'workflow'} · ${facts?.uploadedNodes ?? 0} nodes`;
  }
  if (file.toLowerCase().endsWith('.gguf')) return `Workflow · GGUF · chosen for this file · ${id}`;
  return `Workflow · ${mode === 'edit' ? 'Edit' : 'Text to image'} · ${id}`;
}

/** The model on the desk, its graph, and the files the graph also loads. */
export function DeskModel(props: {
  cfg: ImageConfig;
  mode: Mode;
  facts: ReadyFacts | null;
  onGraph: () => void;
  onModel: (token?: string) => void;
  onCivitai: () => void;
  onUpdateLoader?: () => void;
}) {
  const { cfg, mode, facts } = props;
  const file = facts?.primary ?? '';
  const comfy = cfg.backend === 'comfyui';
  const support = (facts?.slots ?? []).filter((slot) => isSupportToken(slot.token));
  const hasGraphSlots = (facts?.slots ?? []).length > 0;
  return (
    <div>
      <div>Model</div>
      <strong>{familyLabel(facts?.loraFamily, file)}</strong>
      <div>{file || 'No model chosen'}</div>
      {comfy ? <p>{why(cfg, mode, facts, file)}</p> : null}
      {comfy ? (
        <button type="button" onClick={props.onGraph}>
          Change graph
        </button>
      ) : null}
      {cfg.backend === 'remote' ? null : (
        <button type="button" onClick={() => props.onModel()}>
          Change model
        </button>
      )}
      {cfg.backend === 'remote' ? null : (
        <button type="button" onClick={props.onCivitai}>
          Get a model from CivitAI
        </button>
      )}
      {facts?.kind === 'needsLoaderUpdate' && facts.canUpdateLoader ? (
        <p>Confirm the ComfyUI-GGUF loader update on your computer, then check again.</p>
      ) : null}
      {comfy && hasGraphSlots ? (
        support.length === 0 ? (
          <p>This graph has no text encoder or VAE slot.</p>
        ) : (
          <>
            <p>This graph also loads</p>
            {support.map((slot) => (
              <div key={slot.token}>
                <span>{slot.label || (slot.token.includes('VAE') ? 'VAE' : 'Text encoder')}</span>
                <span>{slot.file || 'Not chosen'}</span>
                <button type="button" onClick={() => props.onModel(slot.token)}>
                  Change
                </button>
              </div>
            ))}
            <p>These files do not set the LoRA family. The text encoder can be Qwen while the model is Z-Image.</p>
          </>
        )
      ) : null}
    </div>
  );
}
