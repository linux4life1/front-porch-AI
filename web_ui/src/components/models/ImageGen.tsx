// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image-generation backend config + generate, with one-tap insert into the
// active chat. Thin over /api/image.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { StepUpFields } from '../StepUpFields';
import { PackGrid } from './PackGrid';
import { StudioDesk } from './StudioDesk';
import { ImageRemoteFields } from './ImageRemoteFields';
import type { ImageRemoteHost } from './imageRemote';

interface ImageConfig {
  backend: string;
  isConfigured: boolean;
  size: string;
  style: string;
  model: string;
  editModel?: string;
  negativePrompt: string;
  steps: number;
  cfgScale: number;
  sampler: string;
  scheduler: string;
  lora?: string;
  loraWeight?: number;
  loras?: { file: string; weight: number }[];
  surface?: {
    edit: boolean;
    img2img: boolean;
    lora: boolean;
    negative: boolean;
    checkpointSlot: boolean;
    workflowSlots: boolean;
    scheduler: boolean;
    editAllowlist: boolean;
    editPicker: boolean;
  };
  localUrl: string;
  comfyUrl: string;
  promptReview: boolean;
  drawThingsHost: string;
  drawThingsPort: number;
  remoteApiUrl: string;
  remoteModelName: string;
  hasApiKey: boolean;
  imageRemoteHost?: string;
  imageRemoteHosts?: ImageRemoteHost[];
  comfyCreateWorkflowId?: string;
  comfyCreateModelChoices?: Record<string, string>;
  comfyEditWorkflowId?: string;
  comfyEditModelChoices?: Record<string, string>;
}

const STYLES: Record<string, string> = {
  photorealistic: 'Photorealistic',
  anime: 'Anime / Manga',
  fantasy_art: 'Fantasy Art',
  oil_painting: 'Oil Painting',
  digital_art: 'Digital Art',
  watercolor: 'Watercolor',
};

export function ImageGen({ onError }: { onError: (s: string) => void }) {
  const [cfg, setCfg] = useState<ImageConfig | null>(null);
  const [prompt, setPrompt] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [filename, setFilename] = useState<string | null>(null);
  const [inserted, setInserted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [genError, setGenError] = useState('');
  const [savedRemoteApiUrl, setSavedRemoteApiUrl] = useState('');
  const [savedLocalUrl, setSavedLocalUrl] = useState('');
  const [savedComfyUrl, setSavedComfyUrl] = useState('');
  const [savedDrawThingsHost, setSavedDrawThingsHost] = useState('');
  const [password, setPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);

  useEffect(() => {
    api
      .get<ImageConfig>('/api/image/config')
      .then((next) => {
        setCfg(next);
        setSavedRemoteApiUrl(next.remoteApiUrl);
        setSavedLocalUrl(next.localUrl);
        setSavedComfyUrl(next.comfyUrl);
        setSavedDrawThingsHost(next.drawThingsHost);
      })
      .catch(() => {});
    api
      .get<{ totpEnabled?: boolean }>('/api/auth/state')
      .then((st) => setTotpEnabled(!!st.totpEnabled))
      .catch(() => {});
  }, []);

  if (!cfg) return null;
  const set = (patch: Partial<ImageConfig>) => setCfg({ ...cfg, ...patch });
  const saveConfig = (patch: Record<string, unknown>) => {
    // Studio host chips (`imageRemoteHost`) are not credentials — they pick
    // a vault URL already stored in Settings → Backend. Only a raw custom
    // remoteApiUrl / apiKey / local host still steps up.
    const needsStepUp =
      (typeof patch.remoteApiUrl === 'string' &&
        patch.remoteApiUrl !== savedRemoteApiUrl) ||
      (typeof patch.apiKey === 'string' && patch.apiKey.length > 0) ||
      (typeof patch.localUrl === 'string' && patch.localUrl !== savedLocalUrl) ||
      (typeof patch.comfyUrl === 'string' && patch.comfyUrl !== savedComfyUrl) ||
      (typeof patch.drawThingsHost === 'string' &&
        patch.drawThingsHost !== savedDrawThingsHost);
    if (needsStepUp) {
      patch.currentPassword = password;
      if (totpEnabled && totpCode.trim()) patch.totpCode = totpCode.trim();
    }
    return api
      .post<ImageConfig>('/api/image/config', patch)
      .then((next) => {
        setCfg(next);
        setSavedRemoteApiUrl(next.remoteApiUrl);
        setSavedLocalUrl(next.localUrl);
        setSavedComfyUrl(next.comfyUrl);
        setSavedDrawThingsHost(next.drawThingsHost);
        if (needsStepUp) {
          setPassword('');
          setTotpCode('');
        }
        return true;
      })
      .catch((e) => {
        if (e instanceof ApiError && e.payload.totpRequired === true) {
          setTotpEnabled(true);
        }
        onError(e instanceof ApiError ? e.message : 'Save failed');
        return false;
      });
  };

  const generate = () => {
    if (!prompt.trim()) {
      setGenError('Write a prompt first.');
      return;
    }
    setBusy(true);
    setGenError('');
    setImage(null);
    setFilename(null);
    setInserted(false);
    api.post<{ image: string; filename: string | null }>('/api/image/generate', { prompt })
      .then((r) => { setImage(r.image); setFilename(r.filename); })
      .catch((e) => {
        const message = e instanceof ApiError ? e.message : 'Generation failed';
        setGenError(message);
        onError(message);
      })
      .finally(() => setBusy(false));
  };

  const insertIntoChat = () => {
    if (!filename) return;
    // prompt rides along so the chat image carries the same hover/copyable
    // prompt the desktop attaches (older servers ignore the extra field).
    api.post('/api/chat/insert-image', { filename, prompt })
      .then(() => setInserted(true))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Could not insert into chat'));
  };

  return (
    <section className="card">
      <h3>Image generation</h3>
      <PackGrid />
      <StudioDesk
        backend={cfg.backend}
        model={cfg.model}
        editModel={cfg.editModel ?? ''}
        size={cfg.size}
        steps={cfg.steps}
        sampler={cfg.sampler}
        workflowId={cfg.comfyCreateWorkflowId ?? 'sd'}
        editWorkflowId={cfg.comfyEditWorkflowId ?? 'qwen_image_edit'}
        modelChoices={cfg.comfyCreateModelChoices ?? {}}
        editModelChoices={cfg.comfyEditModelChoices ?? {}}
        loras={cfg.loras ?? []}
        comfyUrl={cfg.comfyUrl}
        localUrl={cfg.localUrl}
        drawThingsHost={cfg.drawThingsHost}
        remoteUrl={cfg.remoteApiUrl}
        onSave={(patch) => { set(patch as Partial<ImageConfig>); return saveConfig(patch); }}
        cfg={cfg.cfgScale}
        scheduler={cfg.scheduler}
        prompt={prompt}
        onPrompt={setPrompt}
        onGenerate={generate}
        generateError={genError}
        busy={busy}
        watch={`${cfg.model}|${cfg.lora ?? ''}|${JSON.stringify(cfg.loras ?? [])}|${JSON.stringify(cfg.comfyCreateModelChoices ?? {})}|${cfg.imageRemoteHost ?? ''}`}
      />
      <label>
        Art style
        <select
          value={STYLES[cfg.style] ? cfg.style : 'photorealistic'}
          onChange={(e) => {
            set({ style: e.target.value });
            void saveConfig({ style: e.target.value });
          }}
        >
          {Object.entries(STYLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </label>
      {cfg.backend === 'remote' && (
        <ImageRemoteFields
          selectedHostId={cfg.imageRemoteHost ?? ''}
          hosts={cfg.imageRemoteHosts ?? []}
          modelId={cfg.model}
          hasApiKey={cfg.hasApiKey}
          remoteApiUrl={cfg.remoteApiUrl}
          onHost={(id) => {
            set({ imageRemoteHost: id });
            void saveConfig({ imageRemoteHost: id });
          }}
          onModel={(id) => {
            set({ model: id });
            void saveConfig({ model: id });
          }}
          onError={onError}
        />
      )}
      {((cfg.backend === 'a1111' && cfg.localUrl !== savedLocalUrl) ||
        (cfg.backend === 'comfyui' && cfg.comfyUrl !== savedComfyUrl) ||
        (cfg.backend === 'drawthings' && cfg.drawThingsHost !== savedDrawThingsHost)) && (
        <>
          <StepUpFields
            password={password}
            onPassword={setPassword}
            totpEnabled={totpEnabled}
            totpCode={totpCode}
            onTotp={setTotpCode}
            reason={
              totpEnabled
                ? 'Changing the local image host — confirm your web login password and a 2FA code.'
                : 'Changing the local image host — confirm your web login password.'
            }
          />
          <button
            className="ghost"
            disabled={!password}
            onClick={() => {
              if (cfg.backend === 'a1111') void saveConfig({ localUrl: cfg.localUrl });
              else if (cfg.backend === 'comfyui') void saveConfig({ comfyUrl: cfg.comfyUrl });
              else void saveConfig({ drawThingsHost: cfg.drawThingsHost });
            }}
          >
            Save host
          </button>
        </>
      )}

      <label className="tool-toggle">
        <span>Review AI prompts before generating (/image pauses so you can edit)</span>
        <input
          type="checkbox"
          checked={cfg.promptReview}
          onChange={(e) => { set({ promptReview: e.target.checked }); void saveConfig({ promptReview: e.target.checked }); }}
        />
      </label>
      {image && (
        <div className="image-result">
          <img src={image} alt="Generated" />
          <div className="image-result-actions">
            <a className="help-link" href={image} download="generated.png">Download</a>
            {filename && (
              <button className="secondary" disabled={inserted} onClick={insertIntoChat}>
                {inserted ? 'Inserted ✓' : 'Insert into chat'}
              </button>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
