// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Voice & Media mirrors the desktop tab (voice_media_tab.dart):
// its groups in its order and words, sub-controls only while their switch is
// on, the self-hiding photo card, the ONNX model button, and every value the
// host's — a write paints at once and rolls back if refused, a change made
// elsewhere repaints the page, and a running download is polled.

import { readFileSync } from 'node:fs';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { VoiceMediaSettings } from './VoiceMediaSettings';
import type { VoiceMediaStatus } from './voiceMedia/useVoiceMediaWire';
import { api } from '../api/client';

type Listener = (e: { event: string }) => void;
let listener: Listener | null = null;

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: Listener) {
      listener = cb;
    }
    connect() {}
    close() {
      listener = null;
    }
  },
}));

const base = (): VoiceMediaStatus => ({
  ttsEnabled: true,
  ttsEngine: 'kokoro',
  sttEnabled: true,
  sttAvailable: true,
  globalVoice: 'af_heart',
  voices: [{ id: 'af_heart', name: 'Heart' }],
  autoSendTranscription: false,
  imageGenEnabled: true,
  expressionEnabled: true,
  expressionMode: 'llm',
  expressionDisplay: 'sidebar',
  expressionRerollSame: false,
  expressionEmojiBurst: true,
  expressionEmojiBurstSize: 28,
  expressionFallback: 'neutral',
  onnxModel: { state: 'missing', progress: null, failed: false },
  photoHelper: { state: 'absent', progress: 0, sizeLabel: '~515 MB', captioning: false },
});

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  listener = null;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

async function mount(status: VoiceMediaStatus) {
  const get = vi.spyOn(api, 'get').mockResolvedValue(status);
  await act(async () => {
    root.render(createElement(VoiceMediaSettings));
  });
  return get;
}

const headings = () => [...host.querySelectorAll('.settings-group-heading')].map((h) => h.textContent);
const control = (label: string) => host.querySelector<HTMLInputElement>(`[aria-label="${label}"]`);
const text = () => host.textContent ?? '';

async function pick(label: string, value: string) {
  const el = control(label) as unknown as HTMLSelectElement;
  await act(async () => {
    el.value = value;
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

describe('Voice & Media settings', () => {
  it('shows the desktop groups in its order, with its words', async () => {
    await mount(base());
    expect(headings()).toEqual([
      'Text-to-Speech',
      'Voice Input (STT)',
      'Expression Images',
      'Image Generation',
    ]);
    expect(text()).toContain('Kokoro TTS');
    expect(text()).toContain('Enabled — Voice: Heart');
    expect(text()).toContain('Enable Voice Input');
    expect(text()).toContain('Enabled — LLM, Sidebar');
    expect(text()).toContain('Enabled — Image Studio button shown in chat');
    expect(text()).toContain('Adds the ✨ Image Studio button to the chat toolbar.');
    const modes = [...(control('Classification') as unknown as HTMLSelectElement).options].map((o) => o.text);
    expect(modes).toEqual(['LLM (Realism Engine)', 'Local ONNX Model', 'Manual Only']);
    const displays = [...(control('Display') as unknown as HTMLSelectElement).options].map((o) => o.text);
    expect(displays).toEqual(['Sidebar Only', 'Background Only', 'Both']);
    const fallbacks = [...(control('Fallback') as unknown as HTMLSelectElement).options].map((o) => o.text);
    expect(fallbacks).toEqual(['Neutral Sprite', 'Prime Avatar', 'Hide', 'Emoji Icon']);
    const slider = control('Burst emoji size')!;
    expect([slider.min, slider.max, slider.step]).toEqual(['12', '60', '4']);
  });

  it('hides the sub-controls while their switch is off, as the desktop does', async () => {
    await mount({
      ...base(),
      sttEnabled: false,
      expressionEnabled: false,
      imageGenEnabled: false,
    });
    expect(control('Auto-send transcription')).toBeNull();
    expect(control('Classification')).toBeNull();
    expect(control('Burst emoji size')).toBeNull();
    expect(text()).not.toContain('Adds the ✨ Image Studio button');
    expect(text()).toContain('Disabled');
    // Burst size shows only while the burst itself is on.
    act(() => root.unmount());
    root = createRoot(host);
    vi.restoreAllMocks();
    await mount({ ...base(), expressionEmojiBurst: false });
    expect(control('Expression Emoji Burst')).not.toBeNull();
    expect(control('Burst emoji size')).toBeNull();
  });

  it('shows Auto-send under the STT switch with the desktop helper text', async () => {
    await mount(base());
    expect(control('Auto-send transcription')).not.toBeNull();
    expect(text()).toContain(
      'When enabled, transcribed text is sent automatically instead of being placed in the input field.',
    );
  });

  it('writes each control to the host and paints at once', async () => {
    await mount(base());
    const post = vi.spyOn(api, 'post').mockImplementation(
      (_path: string, body: unknown) => Promise.resolve({ ...base(), ...(body as object) }),
    );
    await pick('Classification', 'onnx');
    expect(post).toHaveBeenLastCalledWith('/api/voice/settings', { expressionMode: 'onnx' });
    expect(text()).toContain('Enabled — ONNX, Sidebar');
    await act(async () => control('Auto-send transcription')!.click());
    expect(post).toHaveBeenLastCalledWith('/api/voice/settings', { autoSendTranscription: true });
    expect(control('Auto-send transcription')!.checked).toBe(true);
    await act(async () => control('Image Generation')!.click());
    expect(post).toHaveBeenLastCalledWith('/api/voice/settings', { imageGenEnabled: false });
    await pick('Fallback', 'emoji');
    expect(post).toHaveBeenLastCalledWith('/api/voice/settings', { expressionFallback: 'emoji' });
  });

  it('rolls a refused write back and says so', async () => {
    await mount(base());
    vi.spyOn(api, 'post').mockRejectedValue(new Error('offline'));
    await act(async () => control('Expression Images')!.click());
    expect(control('Expression Images')!.checked).toBe(true);
    expect(host.querySelector('[role="alert"]')?.textContent).toContain('Could not save that setting');
  });

  it('repaints when the desktop changes a setting', async () => {
    const get = await mount(base());
    get.mockResolvedValue({ ...base(), expressionDisplay: 'both', autoSendTranscription: true });
    await act(async () => listener?.({ event: 'settings_changed' }));
    expect(text()).toContain('Enabled — LLM, Both');
    expect(control('Auto-send transcription')!.checked).toBe(true);
  });

  it('renders no photo card until the helper is installed or downloading', async () => {
    await mount(base());
    expect(text()).not.toContain('Photo Understanding');
    act(() => root.unmount());
    root = createRoot(host);
    vi.restoreAllMocks();
    await mount({
      ...base(),
      photoHelper: { state: 'installed', progress: 0, sizeLabel: '~515 MB', captioning: false },
    });
    expect(headings()).toEqual([
      'Text-to-Speech',
      'Voice Input (STT)',
      'Photo Understanding',
      'Expression Images',
      'Image Generation',
    ]);
    expect(text()).toContain('Installed (~515 MB on disk)');
    const post = vi.spyOn(api, 'post').mockResolvedValue(base());
    const remove = [...host.querySelectorAll('button')].find((b) => b.textContent?.includes('Remove'))!;
    await act(async () => remove.click());
    expect(post).toHaveBeenCalledWith('/api/voice/photo/remove', {});
    // The host answered "absent": the whole section goes again.
    expect(text()).not.toContain('Photo Understanding');
  });

  it('shows a running photo download with progress and Cancel', async () => {
    await mount({
      ...base(),
      photoHelper: { state: 'downloading', progress: 0.4, sizeLabel: '~515 MB', captioning: false },
    });
    expect(text()).toContain('Downloading…');
    expect(host.querySelector('[role="progressbar"]')?.getAttribute('aria-valuenow')).toBe('40');
    const post = vi.spyOn(api, 'post').mockResolvedValue(base());
    const cancel = [...host.querySelectorAll('button')].find((b) => b.textContent === 'Cancel')!;
    await act(async () => cancel.click());
    expect(post).toHaveBeenCalledWith('/api/voice/photo/cancel', {});
  });

  it('mirrors the ONNX button: download, spinner while polled, then the ready check', async () => {
    vi.useFakeTimers();
    const get = await mount(base());
    const download = control('Download ONNX model for local expression classification')!;
    const downloading = { ...base(), onnxModel: { state: 'downloading' as const, progress: 0.5, failed: false } };
    const post = vi.spyOn(api, 'post').mockResolvedValue(downloading);
    await act(async () => download.click());
    expect(post).toHaveBeenCalledWith('/api/voice/onnx/download', {});
    expect(control('Downloading the ONNX model (50%)')).not.toBeNull();
    get.mockClear();
    get.mockResolvedValue({ ...base(), onnxModel: { state: 'ready', progress: null, failed: false } });
    await act(async () => {
      vi.advanceTimersByTime(1300);
    });
    expect(get).toHaveBeenCalledWith('/api/voice/status');
    expect(control('Expression model downloaded and ready')).not.toBeNull();
  });

  it('renders every voice-media marker the parity manifest pins (the page test stubs this)', async () => {
    await mount({
      ...base(),
      photoHelper: { state: 'installed', progress: 0, sizeLabel: '~515 MB', captioning: false },
    });
    const manifest = JSON.parse(
      readFileSync('../docs/design/settings-parity-manifest.json', 'utf8'),
    ) as { controls: Record<string, { section: string; webMarker: string }> };
    // Text plus accessible names: the ONNX button is an icon with a label.
    const labels = [...host.querySelectorAll('[aria-label]')].map((el) => el.getAttribute('aria-label'));
    const seen = `${text()} ${labels.join(' ')}`;
    const pinned = Object.entries(manifest.controls).filter(
      // The Reclaim card lives on the page itself, not in this component.
      ([key, c]) => c.section === 'voice-media' && key !== 'reclaimDiskSpace',
    );
    expect(pinned.length).toBeGreaterThan(10);
    for (const [key, c] of pinned) {
      expect(seen.includes(c.webMarker), `${key}: "${c.webMarker}"`).toBe(true);
    }
  });

  it('shows the ONNX circle in every classification mode, as the desktop does', async () => {
    for (const expressionMode of ['llm', 'onnx', 'manual']) {
      for (const [state, label] of [
        ['missing', 'Download ONNX model for local expression classification'],
        ['ready', 'Expression model downloaded and ready'],
        ['downloading', 'Downloading the ONNX model'],
      ] as const) {
        act(() => root.unmount());
        root = createRoot(host);
        vi.restoreAllMocks();
        await mount({ ...base(), expressionMode, onnxModel: { state, progress: null, failed: false } });
        expect(control(label), `${expressionMode} / ${state}`).not.toBeNull();
      }
    }
  });

  it('draws the hairline under the Expression Images title row only while enabled', async () => {
    await mount(base());
    const card = host.querySelector('[data-testid="vm-expressions"]')!;
    expect(card.querySelector('.vm-card-body')).not.toBeNull();
    act(() => root.unmount());
    root = createRoot(host);
    vi.restoreAllMocks();
    await mount({ ...base(), expressionEnabled: false });
    expect(host.querySelector('[data-testid="vm-expressions"] .vm-card-body')).toBeNull();
  });

  it('says so when the ONNX download failed', async () => {
    await mount({ ...base(), onnxModel: { state: 'missing', progress: null, failed: true } });
    expect(text()).toContain('Download failed. Check your internet connection and try again.');
  });
});
