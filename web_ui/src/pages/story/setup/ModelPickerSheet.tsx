// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story-only model picker: Same as chat, Worker model, or any host + model.
// Never shows a chat setting. Web twin of lib/ui/story_setup/model_picker_sheet.dart;
// the relay serves its options (`GET /api/stories/lanes`).

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../../api/client';
import type { StoryLaneChoice } from '../../../storyTypes';
import { Chip, Dialog, Note, PickChip, PickField, RadioRow } from './primitives';

interface LaneHost {
  kind: string;
  label: string;
  type: string;
  url: string;
  needsKey: boolean;
  hasKey: boolean;
  local: boolean;
}

interface LaneFile {
  name: string;
  path: string;
}

interface LaneOptions {
  chat: { label: string; detail: string };
  worker: { label: string; detail: string } | null;
  hosts: LaneHost[];
  koboldModels: LaneFile[];
  kcpps: LaneFile[];
}

interface RemoteModel {
  id: string;
  name: string;
}

/** A pick-one list opened over the sheet: the host's models, or the local files. */
interface ListPick {
  title: string;
  empty: string;
  rows: { value: string; label: string; detail?: string; mono?: boolean }[];
  onPick: (value: string) => void;
}

const basename = (p: string) => p.split(/[\\/]/).pop() ?? p;
const enc = encodeURIComponent;

/**
 * The host a lane points at. OpenRouter-type hosts share one backend type, so those match by URL;
 * Custom is whichever URL no named host owns (KoboldCpp and Custom carry an empty URL of their own,
 * which must not count as "taken").
 */
function matchHost(hosts: LaneHost[], choice: StoryLaneChoice): LaneHost | null {
  if (choice.lane !== 'host') return null;
  const url = choice.url.trim();
  return hosts.find((h) => {
    if (h.type !== choice.backend) return false;
    if (h.type !== 'openRouter') return true;
    return h.kind === 'custom' ? hosts.every((o) => o.kind === 'custom' || !o.url || o.url !== url) : h.url === url;
  }) ?? null;
}

export function ModelPickerSheet({ job, current, onPick, onClose }: {
  job: string;
  current: StoryLaneChoice;
  onPick: (choice: StoryLaneChoice) => void;
  onClose: () => void;
}) {
  const [choice, setChoice] = useState<StoryLaneChoice>({ ...current });
  const [opts, setOpts] = useState<LaneOptions | null>(null);
  const [loadError, setLoadError] = useState('');
  const [models, setModels] = useState<RemoteModel[]>([]);
  const [fetching, setFetching] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [key, setKey] = useState('');
  const [savedKeys, setSavedKeys] = useState<string[]>([]);
  const [list, setList] = useState<ListPick | null>(null);

  useEffect(() => {
    let live = true;
    api.get<LaneOptions>('/api/stories/lanes')
      .then((r) => { if (live) setOpts(r); })
      .catch(() => { if (live) setLoadError('Could not load the models. Check that the app is running, then try again.'); });
    return () => { live = false; };
  }, []);

  const hosts = opts?.hosts ?? [];
  const host = matchHost(hosts, choice);
  const isHost = choice.lane === 'host';

  const pickHost = (h: LaneHost) => {
    setChoice({ lane: 'host', backend: h.type, url: h.kind === 'custom' ? '' : h.url, model: '', kcpps: '' });
    setModels([]);
    setNote(null);
    setKey('');
  };

  /** Save a typed key, then ask the host which models it offers. */
  const refresh = async (): Promise<RemoteModel[]> => {
    if (!host) return [];
    setFetching(true);
    setNote(null);
    try {
      const url = choice.url.trim();
      if (key.trim()) {
        await api.post('/api/stories/host-key', { type: choice.backend, url, key: key.trim() });
        setKey('');
        setSavedKeys((k) => [...k, host.kind]);
      }
      const r = await api.get<{ models: RemoteModel[] }>(`/api/stories/host-models?type=${enc(choice.backend)}&url=${enc(url)}`);
      setModels(r.models);
      setNote(r.models.length === 0
        ? 'This host answered with no models. Check the URL and key.'
        : `${r.models.length} models from this host.`);
      return r.models;
    } catch (e) {
      setNote(`Could not reach this host: ${e instanceof ApiError ? e.message : String(e)}`);
      return [];
    } finally {
      setFetching(false);
    }
  };

  const pickRemoteModel = async () => {
    const found = models.length > 0 ? models : await refresh();
    if (found.length === 0) return;
    setList({
      title: 'Model',
      empty: '',
      rows: found.map((m) => ({ value: m.id, label: m.id, detail: m.name && m.name !== m.id ? m.name : undefined, mono: true })),
      onPick: (model) => setChoice((c) => ({ ...c, model })),
    });
  };

  const pickFile = (title: string, files: LaneFile[], apply: (path: string) => Partial<StoryLaneChoice>) => {
    setList({
      title,
      empty: 'Nothing found in the models folder.',
      rows: files.map((f) => ({ value: f.path, label: f.name })),
      onPick: (path) => setChoice((c) => ({ ...c, ...apply(path) })),
    });
  };

  const hostFields = (h: LaneHost) => {
    const kobold = h.type === 'kobold';
    const needsKey = h.needsKey && !h.hasKey && !savedKeys.includes(h.kind);
    return (
      <>
        {h.kind === 'custom' && (
          <div className="s-col" style={{ gap: 4 }}>
            <Note>API URL</Note>
            <input type="text" data-testid="story-host-url" placeholder="https://your-server.example/v1" value={choice.url}
              onChange={(e) => setChoice({ ...choice, url: e.target.value.trim() })} />
          </div>
        )}
        {kobold ? (
          <>
            <div className="s-col" style={{ gap: 4 }}>
              <Note>Model file</Note>
              <PickField value={choice.model ? basename(choice.model) : ''} placeholder="Choose a .gguf" testid="story-host-file"
                onClick={() => pickFile('Model file', opts?.koboldModels ?? [], (model) => ({ model }))} />
            </div>
            <div className="s-col" style={{ gap: 4 }}>
              <Note>Launch preset</Note>
              <PickField value={choice.kcpps ? basename(choice.kcpps) : ''} placeholder="Same as chat" testid="story-host-preset"
                onClick={() => pickFile('Launch preset', opts?.kcpps ?? [], (kcpps) => ({ kcpps }))} />
            </div>
          </>
        ) : (
          <>
            <div className="s-row nowrap">
              <span className="s-grow"><Note>Model</Note></span>
              <button type="button" className="s-btn-ghost" disabled={fetching} data-testid="story-host-refresh" onClick={() => void refresh()}>
                {fetching ? 'Fetching…' : '↻ Refresh list'}
              </button>
            </div>
            <PickField value={choice.model} placeholder="Choose a model" testid="story-host-model" onClick={() => void pickRemoteModel()} />
            {needsKey ? (
              <input type="password" data-testid="story-host-key" placeholder="API key for this host" value={key}
                onChange={(e) => setKey(e.target.value)} />
            ) : h.needsKey && <Note>Using the saved key for {h.label}.</Note>}
          </>
        )}
        {note && <Note>{note}</Note>}
        {h.local && (
          <div className="s-row nowrap" style={{ alignItems: 'flex-start', marginTop: 4 }}>
            <Chip tone="honey">Swaps with the chat model</Chip>
            <Note>Each switch unloads one model and loads the other. Reviews are grouped so it happens once per stage, not once per try.</Note>
          </div>
        )}
      </>
    );
  };

  return (
    <>
      <Dialog sheet title={`${job} model`} onClose={onClose} testid="story-model-picker" actions={(
        <>
          {isHost && choice.backend !== 'kobold' && (
            <button type="button" className="s-btn-ghost" style={{ marginRight: 'auto' }} disabled={fetching || !host} onClick={() => void refresh()}>Test</button>
          )}
          <button type="button" className="s-btn-ghost" onClick={onClose}>Cancel</button>
          <button type="button" className="s-btn-primary" data-testid="story-lane-use"
            disabled={opts === null || (isHost && !choice.model.trim())} onClick={() => onPick(choice)}>Use this model</button>
        </>
      )}>
        {loadError ? <div className="s-error">{loadError}</div>
          : opts === null ? <div className="body">Loading the models…</div>
          : (
            <div className="s-col" style={{ gap: 0 }}>
              <RadioRow testid="story-lane-chat" selected={choice.lane === 'main'} title="Same as chat" detail={opts.chat.detail}
                onSelect={() => setChoice({ lane: 'main', backend: '', url: '', model: '', kcpps: '' })} />
              {opts.worker && (
                <RadioRow testid="story-lane-worker" selected={choice.lane === 'worker'} title="Worker model" detail={opts.worker.detail}
                  onSelect={() => setChoice({ lane: 'worker', backend: '', url: '', model: '', kcpps: '' })} />
              )}
              {hosts.length > 0 && (
                <RadioRow testid="story-lane-host" selected={isHost} title="Another host" onSelect={() => pickHost(hosts[0])} />
              )}
              {isHost && (
                <div className="s-col" style={{ paddingLeft: 26, gap: 8 }}>
                  <div className="s-chips">
                    {hosts.map((h) => (
                      <PickChip key={h.kind} on={h === host} testid={`story-host-${h.kind}`} onClick={() => pickHost(h)}>{h.label}</PickChip>
                    ))}
                  </div>
                  {host && hostFields(host)}
                </div>
              )}
            </div>
          )}
      </Dialog>
      {list && (
        <Dialog title={list.title} wide onClose={() => setList(null)}
          actions={<button type="button" className="s-btn-ghost" onClick={() => setList(null)}>Cancel</button>}>
          {list.rows.length === 0 ? <div className="body">{list.empty}</div> : (
            <div className="s-col" style={{ gap: 0 }}>
              {list.rows.map((r) => (
                <button key={r.value} type="button" className="s-listrow" data-testid={`story-model-${r.value}`}
                  onClick={() => { list.onPick(r.value); setList(null); }}>
                  <span className={`s-grow s-ell${r.mono ? ' mono' : ''}`}>{r.label}</span>
                  {r.detail && <span className="s-muted s-small s-ell">{r.detail}</span>}
                </button>
              ))}
            </div>
          )}
        </Dialog>
      )}
    </>
  );
}
