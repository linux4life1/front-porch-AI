// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Voice controls for the web chat: a per-message Speak button (TTS synthesized
// on the host, played on the *client* device) and a mic button that records on
// the client and uploads to the server for transcription. The mic is gated on a
// secure context — getUserMedia is unavailable over plain-LAN http.

import { useRef, useState } from 'react';
import { api, ApiError } from '../api/client';

/** 🔊 Synthesize a message and play it on this device. */
export function SpeakButton({ text }: { text: string }) {
  const [busy, setBusy] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const speak = async () => {
    if (busy || !text.trim()) return;
    setBusy(true);
    try {
      const blob = await api.postForBlob('/api/tts/speak', { text });
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audioRef.current = audio;
      audio.onended = () => URL.revokeObjectURL(url);
      await audio.play();
    } catch {
      // TTS off or no audio — surface nothing intrusive; the button just resets.
    } finally {
      setBusy(false);
    }
  };

  return (
    <button className="icon-btn" title="Speak" aria-label="Speak this message" disabled={busy} onClick={speak}>
      {busy ? '…' : '🔊'}
    </button>
  );
}

// ── Raw-PCM mic capture ────────────────────────────────────────────────────
// The host transcribes with an in-process WAV-only engine (the Python
// decoder that used to accept MediaRecorder's webm/ogg is gone), so the mic
// captures raw PCM via the Web Audio API and encodes a 16 kHz mono WAV
// right here in the browser. AudioWorklet where available (loaded from a
// Blob URL — no extra file to serve), ScriptProcessor as the fallback.

const WORKLET_SRC = `
class FpPcmTap extends AudioWorkletProcessor {
  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (ch) this.port.postMessage(ch.slice(0));
    return true;
  }
}
registerProcessor('fp-pcm-tap', FpPcmTap);
`;

interface PcmRecorder {
  stop(): Promise<{ samples: Float32Array; sampleRate: number }>;
}

async function startPcmRecorder(): Promise<PcmRecorder> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const ctx = new AudioContext();
  await ctx.resume(); // iOS Safari: must resume inside the user gesture
  const source = ctx.createMediaStreamSource(stream);
  const chunks: Float32Array[] = [];
  // A muted gain keeps the tap node pulled by the graph without echoing the
  // mic back out of the speakers.
  const mute = ctx.createGain();
  mute.gain.value = 0;
  let cleanup: () => void;
  if (ctx.audioWorklet) {
    const url = URL.createObjectURL(new Blob([WORKLET_SRC], { type: 'application/javascript' }));
    try {
      await ctx.audioWorklet.addModule(url);
    } finally {
      URL.revokeObjectURL(url);
    }
    const node = new AudioWorkletNode(ctx, 'fp-pcm-tap');
    node.port.onmessage = (e) => chunks.push(e.data as Float32Array);
    source.connect(node);
    node.connect(mute).connect(ctx.destination);
    cleanup = () => {
      node.port.onmessage = null;
      node.disconnect();
    };
  } else {
    const node = ctx.createScriptProcessor(4096, 1, 1);
    node.onaudioprocess = (e) => chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
    source.connect(node);
    node.connect(mute).connect(ctx.destination);
    cleanup = () => {
      node.onaudioprocess = null;
      node.disconnect();
    };
  }
  return {
    stop: async () => {
      cleanup();
      mute.disconnect();
      source.disconnect();
      stream.getTracks().forEach((t) => t.stop());
      const sampleRate = ctx.sampleRate;
      await ctx.close();
      let total = 0;
      for (const c of chunks) total += c.length;
      const samples = new Float32Array(total);
      let off = 0;
      for (const c of chunks) {
        samples.set(c, off);
        off += c.length;
      }
      return { samples, sampleRate };
    },
  };
}

/** Linear-interpolation downsample to Whisper's 16 kHz (fine for speech). */
function downsampleTo16k(samples: Float32Array, fromRate: number): Float32Array {
  const toRate = 16000;
  if (fromRate <= toRate) return samples;
  const outLen = Math.floor((samples.length * toRate) / fromRate);
  const out = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const pos = (i * fromRate) / toRate;
    const i0 = Math.floor(pos);
    const i1 = Math.min(i0 + 1, samples.length - 1);
    out[i] = samples[i0] + (samples[i1] - samples[i0]) * (pos - i0);
  }
  return out;
}

function encodeWavPcm16(samples: Float32Array, rate: number): Blob {
  const buf = new ArrayBuffer(44 + samples.length * 2);
  const v = new DataView(buf);
  const tag = (o: number, s: string) => {
    for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i));
  };
  tag(0, 'RIFF');
  v.setUint32(4, 36 + samples.length * 2, true);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  v.setUint32(16, 16, true); // classic 16-byte PCM fmt chunk
  v.setUint16(20, 1, true); // PCM
  v.setUint16(22, 1, true); // mono
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  tag(36, 'data');
  v.setUint32(40, samples.length * 2, true);
  let o = 44;
  for (let i = 0; i < samples.length; i++, o += 2) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    v.setInt16(o, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }
  return new Blob([buf], { type: 'audio/wav' });
}

/** 🎤 Record on this device, upload, and hand the transcript back. Hidden by the
 *  caller unless STT is available and the page is a secure context. */
export function MicButton({
  onText,
  disabled,
}: {
  onText: (text: string) => void;
  disabled?: boolean;
}) {
  const [recording, setRecording] = useState(false);
  const [working, setWorking] = useState(false);
  const recorderRef = useRef<PcmRecorder | null>(null);

  const start = async () => {
    if (working || recorderRef.current) return;
    try {
      recorderRef.current = await startPcmRecorder();
      setRecording(true);
    } catch {
      // Permission denied or no device — leave the button idle.
    }
  };

  const stop = async () => {
    const recorder = recorderRef.current;
    recorderRef.current = null;
    setRecording(false);
    if (!recorder) return;
    setWorking(true);
    try {
      const { samples, sampleRate } = await recorder.stop();
      const wav = encodeWavPcm16(downsampleTo16k(samples, sampleRate), Math.min(sampleRate, 16000));
      const r = await api.postBlob<{ text: string }>('/api/stt/transcribe', wav, 'wav');
      if (r.text) onText(r.text);
    } catch (e) {
      if (e instanceof ApiError && e.status !== 422) {
        // 422 = no speech detected; stay quiet. Other errors are silent too,
        // since the mic button has no error surface of its own.
      }
    } finally {
      setWorking(false);
    }
  };

  return (
    <button
      className={`icon-btn mic${recording ? ' recording' : ''}`}
      title={recording ? 'Stop & transcribe' : 'Speak to type'}
      aria-label={recording ? 'Stop recording and transcribe' : 'Record voice to text'}
      aria-pressed={recording}
      disabled={disabled || working}
      onClick={recording ? stop : start}
    >
      {working ? '…' : recording ? '⏺' : '🎤'}
    </button>
  );
}
