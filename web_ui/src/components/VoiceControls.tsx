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
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<BlobPart[]>([]);

  const start = async () => {
    if (working) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      chunksRef.current = [];
      recorder.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      recorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        const ext = (recorder.mimeType || 'audio/webm').includes('ogg') ? 'ogg' : 'webm';
        setWorking(true);
        try {
          const r = await api.postBlob<{ text: string }>('/api/stt/transcribe', blob, ext);
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
      recorder.start();
      recorderRef.current = recorder;
      setRecording(true);
    } catch {
      // Permission denied or no device — leave the button idle.
    }
  };

  const stop = () => {
    recorderRef.current?.stop();
    recorderRef.current = null;
    setRecording(false);
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
