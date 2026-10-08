// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone Image Studio desk. It shows what the computer's desk shows and
// asks the computer to make each choice by the desktop's own rules; it writes
// nothing on its own, only what a tap asks for.

import { useEffect, useState, type ReactNode } from 'react';
import { ApiError } from '../../api/client';
import { CivitaiSheet } from './studio/CivitaiSheet';
import { DeskAdvanced } from './studio/DeskAdvanced';
import { DeskConnection, backendName } from './studio/DeskConnection';
import { DeskLoras } from './studio/DeskLoras';
import { DeskModel } from './studio/DeskModel';
import { DeskRail, type Picture, type Subject } from './studio/DeskRail';
import { DeskSize } from './studio/DeskSize';
import { PackPanel } from './studio/PackPanel';
import { GraphSheet } from './studio/GraphSheet';
import { LoraSheet } from './studio/LoraSheet';
import { ModelSheet } from './studio/ModelSheet';
import { installedChoice, pick, setLoaderSupport } from './studio/deskApi';
import { factsByFile, readyLine } from './studio/deskRules';
import { useDeskReady } from './studio/useDeskReady';
import { useSharedGeneration } from './studio/useSharedGeneration';
import type { GraphUpload, ImageConfig, LoraFact, LoraSlot, Mode } from './studio/types';
import './studio/desk.css';

export type { Picture } from './studio/DeskRail';

/** What a Generate press sends: the mode, and the picture if there is one. */
export interface GenerateRequest {
  mode: Mode;
  picture: Picture | null;
}

export interface StudioDeskProps {
  cfg: ImageConfig;
  /** The computer's answer to a pick: the config as it is now. */
  onConfig: (next: ImageConfig) => void;
  /** Saves part of the config. Resolves false when the computer refused it. */
  save: (patch: Record<string, unknown>) => Promise<boolean>;
  totpEnabled: boolean;
  prompt: string;
  onPrompt: (value: string) => void;
  onGenerate: (request: GenerateRequest) => void;
  generateError?: string;
  busy?: boolean;
  /** 0 to 1 while a picture is being made, when the computer knows. */
  progress?: number | null;
  /** Finished picture. Wide desks place it under Expression pack. */
  result?: ReactNode;
  /** The picture the last generate saved, to edit next. */
  lastSaved?: { name: string; url: string } | null;
  /** How often a CivitAI download is asked about; for tests. */
  civitaiPollMs?: number;
  onSharedBusy?: (busy: boolean) => void;
  onConfigMode?: (mode: Mode) => void;
}

type Sheet =
  | { kind: 'graph' }
  | { kind: 'model'; token?: string }
  | { kind: 'lora' }
  | { kind: 'civitai'; lora: boolean };

const SLOTS = 8;

function paddedSlots(cfg: ImageConfig): LoraSlot[] {
  const list = cfg.loras ?? [];
  return Array.from({ length: SLOTS }, (_, i) => list[i] ?? { file: '', weight: 0.8 });
}

export function StudioDesk(props: StudioDeskProps) {
  const { cfg } = props;
  const [mode, setMode] = useState<Mode>('create');
  const [tab, setTab] = useState<Mode | 'pack'>('create');
  const [packVisited, setPackVisited] = useState(false);
  const [packBusy, setPackBusy] = useState(false);
  const [subject, setSubject] = useState<Subject>('free');
  const [picture, setPicture] = useState<Picture | null>(null);
  const [sheet, setSheet] = useState<Sheet | null>(null);
  const [note, setNote] = useState('');
  const [known, setKnown] = useState<Record<string, LoraFact>>({});

  const readyKey = JSON.stringify([
    cfg.backend, cfg.model, cfg.editModel, cfg.comfyCreateWorkflowId, cfg.comfyEditWorkflowId,
    cfg.comfyCreateModelChoices, cfg.comfyEditModelChoices, cfg.loras, cfg.imageRemoteHost,
    cfg.comfyUrl, cfg.localUrl, cfg.drawThingsHost, cfg.drawThingsPort,
    cfg.comfyCreateUploadedTitle, cfg.comfyEditUploadedTitle,
  ]);
  const configMode = tab === 'pack' ? cfg.packConfigMode ?? (cfg.backend === 'a1111' ? 'create' : 'edit') : mode;
  const { onConfigMode, onSharedBusy } = props;
  useEffect(() => onConfigMode?.(configMode), [configMode, onConfigMode]);
  const globalGeneration = useSharedGeneration(props.busy === true || packBusy);
  const globalBusy = globalGeneration.busy;
  const sharedBusy = props.busy === true || (globalBusy ?? cfg.isGenerating) === true || packBusy;
  useEffect(() => onSharedBusy?.(sharedBusy), [sharedBusy, onSharedBusy]);
  const { facts, refresh } = useDeskReady(configMode, readyKey);
  const file = facts?.primary ?? '';
  const facing = { ...factsByFile(facts?.loraFacts), ...known };

  const failed = (e: unknown, fallback: string) =>
    setNote(e instanceof ApiError && e.message ? e.message : fallback);

  const saveConfig = (patch: Record<string, unknown>) => sharedBusy ? Promise.resolve(false) : props.save(patch);
  const choose = (body: Parameters<typeof pick>[0]) =>
    sharedBusy ? Promise.resolve() : pick(body).then((next) => {
      props.onConfig(next);
      refresh();
    });

  const useLoaderSupport = () => {
    const url = facts?.savedUrl ?? cfg.comfyUrl;
    if (props.busy || !url) return;
    const confirmed = facts?.loaderSupportConfirmed === true;
    if (!confirmed && !window.confirm(`Choose this if your workflow already runs in ComfyUI with a compatible loader or extension. Front Porch will skip its GGUF compatibility check for ${url} until Front Porch restarts. ComfyUI will still validate the workflow.`)) return;
    void setLoaderSupport(url, !confirmed).then(refresh)
      .catch((e) => failed(e, 'Could not change the GGUF support check.'));
  };

  const pickGraph = (id: string, forMode: Mode) => {
    setSheet(null);
    void choose({ kind: 'graph', mode: forMode, id }).catch((e) => failed(e, 'Could not use that graph.'));
  };

  const pickFile = (name: string, token?: string) => {
    setSheet(null);
    void choose(token ? { kind: 'support', mode: configMode, token, file: name } : { kind: 'model', mode: configMode, file: name })
      .catch((e) => failed(e, 'Could not use that file.'));
  };

  const addLora = (name: string) => {
    const slots = paddedSlots(cfg);
    const index = slots.findIndex((s) => !s.file.trim());
    if (index < 0) {
      setNote('All LoRA slots are full. Remove one to add another.');
      return;
    }
    slots[index] = { file: name, weight: slots[index].weight || 0.8 };
    setSheet(null);
    void saveConfig({ loras: slots }).then(refresh);
  };

  const storedGraph = (result: GraphUpload) => {
    setSheet(null);
    if (result.config) props.onConfig(result.config);
    const shown = result.mode === 'edit' ? 'edit' : 'portrait';
    setNote(`${result.title ?? 'That file'} is the workflow for this ${shown}.`);
    refresh();
  };

  /** A finished download is selected only when this graph can load it. */
  const installed = async (filename: string, lora: boolean): Promise<string> => {
    const saved = 'Saved to your models folder on this computer.';
    const where = lora
      ? cfg.backend === 'a1111' ? 'It is in the Lora folder.' : 'Pick it with Add under LoRA.'
      : 'Pick it with Change model.';
    try {
      const choice = await installedChoice({ filename, lora, workflowId: facts?.workflowId ?? '' });
      if (!choice.accept) return choice.kind === 'lora-full' ? `${saved} All LoRA slots are full.` : `${saved} ${where}`;
      if (choice.kind === 'lora' && choice.loras) {
        await saveConfig({ loras: choice.loras });
      } else if (choice.kind === 'comfy' && choice.token) {
        await choose({ kind: 'support', mode: configMode, token: choice.token, file: filename });
      } else if (choice.kind === 'slot') {
        await choose({ kind: 'model', mode: configMode, file: filename });
      } else {
        return `${saved} ${where}`;
      }
      refresh();
      return saved;
    } catch {
      return `${saved} ${where}`;
    }
  };

  const ready = facts?.ready === true;
  const needsPicture = mode === 'edit' && !picture;
  const line = readyLine({
    ready,
    busy: sharedBusy,
    kind: facts?.kind,
    message: facts?.message,
    missingClass: facts?.missingClass,
    backendName: backendName(cfg.backend),
    file,
    blockedLora: facts?.blockedLora,
  });

  return (
    <section className="studio-desk">
      <div role="tablist" aria-label="Image Studio workspace" className="fp-workspace-tabs">
        {(['create', 'edit', 'pack'] as const).map((value) => (
          <button key={value} id={`studio-tab-${value}`} type="button" role="tab"
            aria-selected={tab === value} aria-pressed={tab === value}
            aria-expanded={value === 'pack' ? tab === 'pack' : undefined}
            aria-controls={value === 'pack' ? 'studio-pack-panel' : 'studio-image-panel'}
            tabIndex={tab === value ? 0 : -1}
            onKeyDown={(e) => {
              const values = ['create', 'edit', 'pack'] as const;
              const index = values.indexOf(value);
              const next = e.key === 'ArrowRight' ? values[(index + 1) % 3]
                : e.key === 'ArrowLeft' ? values[(index + 2) % 3]
                : e.key === 'Home' ? 'create' : e.key === 'End' ? 'pack' : null;
              if (next) {
                e.preventDefault();
                document.getElementById(`studio-tab-${next}`)?.click();
                document.getElementById(`studio-tab-${next}`)?.focus();
              }
            }}
            onClick={() => {
              setTab(value);
              if (value === 'pack') setPackVisited(true);
              else setMode(value);
            }}>
            {value === 'pack' ? 'Expression pack' : value === 'create' ? 'Create' : 'Edit'}
          </button>
        ))}
      </div>
      <div className="fp-desk-body">
        <div className="fp-desk-rail" id="studio-image-panel" role="tabpanel"
          aria-labelledby={`studio-tab-${mode}`} hidden={tab === 'pack'}>
        <DeskRail
          mode={mode}
          subject={subject}
          onSubject={setSubject}
          prompt={props.prompt}
          onPrompt={props.onPrompt}
          picture={picture}
          onPicture={setPicture}
          lastSaved={props.lastSaved ?? null}
          onNote={setNote}
        />
        </div>
        {packVisited ? <div className="fp-desk-rail" id="studio-pack-panel" role="tabpanel"
          aria-labelledby="studio-tab-pack" hidden={tab !== 'pack'}>
          <PackPanel lastSaved={props.lastSaved ?? null}
            sharedBusy={props.busy === true || (globalBusy ?? cfg.isGenerating) === true}
            configMode={configMode} onBusy={setPackBusy} />
        </div> : null}
        {props.result ? <div className="fp-desk-output" data-region="output">{props.result}</div> : null}
        <div className="fp-desk-stove" data-region="stove">
          <fieldset className="fp-desk-settings" disabled={sharedBusy}>
          <legend>{tab === 'pack' ? `Pack settings · ${configMode === 'edit' ? 'Edit' : 'Create / img2img'}` : 'Image settings'}</legend>
          <DeskConnection
            cfg={cfg}
            facts={facts}
            totpEnabled={props.totpEnabled}
            onBackend={(backend) => void saveConfig({ backend }).then(refresh)}
            save={saveConfig}
            onCheck={refresh}
          />
          <DeskModel
            cfg={cfg}
            mode={configMode}
            facts={facts}
            onGraph={() => setSheet({ kind: 'graph' })}
            onModel={(token) => setSheet({ kind: 'model', token })}
            onCivitai={() => setSheet({ kind: 'civitai', lora: false })}
            onLoaderSupport={useLoaderSupport}
            busy={props.busy}
          />
          <DeskLoras
            slots={paddedSlots(cfg)}
            facts={facts}
            known={facing}
            onWeights={(next) => void saveConfig({ loras: next }).then(refresh)}
            onAdd={() => setSheet({ kind: 'lora' })}
            onCivitai={() => setSheet({ kind: 'civitai', lora: true })}
            onUseAnyway={(family) => void saveConfig({ loraOverrideFamily: family }).then(refresh)}
          />
          <DeskSize size={cfg.size} onSize={(size) => void saveConfig({ size })} />
          <DeskAdvanced cfg={cfg} samplers={cfg.drawThingsSamplers ?? []} save={saveConfig} />
          </fieldset>
          {props.busy ? (
            <div>
              <progress aria-label="Generation progress" max={1} value={props.progress ?? undefined} />
              {props.progress != null ? <span>{`Painting… ${Math.round(props.progress * 100)}%`}</span> : null}
            </div>
          ) : null}
          <p>{line}</p>
          {needsPicture ? <p>Pick a picture to edit.</p> : null}
          {tab !== 'pack' ? <button
            type="button"
            disabled={!ready || props.busy === true || globalBusy === true || packBusy || needsPicture || !props.prompt.trim()}
            onClick={() => props.onGenerate({ mode, picture })}
          >
            Generate
          </button> : null}
          {props.generateError ? <p>{props.generateError}</p> : null}
          {note ? <p>{note}</p> : null}
          {globalGeneration.problem ? <p role="status">{globalGeneration.problem}</p> : null}
        </div>
      </div>
      {!sharedBusy && sheet?.kind === 'graph' ? (
        <GraphSheet
          mode={configMode}
          backend={cfg.backend}
          totpEnabled={props.totpEnabled}
          onPick={pickGraph}
          onStored={storedGraph}
          onClose={() => setSheet(null)}
        />
      ) : null}
      {!sharedBusy && sheet?.kind === 'model' ? (
        <ModelSheet
          mode={configMode}
          backend={cfg.backend}
          token={sheet.token}
          primary={file}
          onPick={(name) => pickFile(name, sheet.token)}
          onClose={() => setSheet(null)}
        />
      ) : null}
      {!sharedBusy && sheet?.kind === 'lora' ? (
        <LoraSheet
          mode={configMode}
          backend={cfg.backend}
          facts={facts}
          onFacts={setKnown}
          onPick={addLora}
          onClose={() => setSheet(null)}
        />
      ) : null}
      {!sharedBusy && sheet?.kind === 'civitai' ? (
        <CivitaiSheet
          lora={sheet.lora}
          backend={cfg.backend}
          adultAllowed={cfg.adultAllowed === true}
          totpEnabled={props.totpEnabled}
          onInstalled={installed}
          pollMs={props.civitaiPollMs}
          onClose={() => setSheet(null)}
        />
      ) : null}
    </section>
  );
}
