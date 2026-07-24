/**
 * Orchestrator: decode audio blob → apply emotional voice DSP → return AudioBuffer.
 * Returns null when disabled or on failure (caller falls back to plain playback).
 */

import { emotionalVoiceDsp } from './emotionalVoiceDsp';

const STORAGE_KEY = 'emotionalVoice';
let _ctx: AudioContext | null = null;

function getAudioContext(): AudioContext {
  if (!_ctx) _ctx = new AudioContext();
  return _ctx;
}

/** Whether emotional voice processing is enabled (persisted in localStorage). */
export function isEmotionalVoiceEnabled(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
}

/** Toggle the emotional voice setting. */
export function setEmotionalVoiceEnabled(v: boolean): void {
  try { localStorage.setItem(STORAGE_KEY, String(v)); } catch { /* noop */ }
}

/**
 * Process [audioBlob] through emotional voice DSP.
 *
 * Returns a playable `AudioBuffer` with emotion-adapted audio,
 * or `null` when processing is skipped (disabled / no emotion / error).
 */
export async function processEmotionalVoice(
  audioBlob: Blob,
  emotion: string | undefined | null,
  enabled: boolean,
): Promise<AudioBuffer | null> {
  if (!enabled || !emotion) return null;

  try {
    const ctx = getAudioContext();
    const arrayBuffer = await audioBlob.arrayBuffer();
    const audioBuffer = await ctx.decodeAudioData(arrayBuffer);

    // Extract mono samples from first channel
    const mono = audioBuffer.getChannelData(0);
    const samples = new Float32Array(mono.length);
    samples.set(mono);

    // Apply DSP
    const processed = emotionalVoiceDsp(samples, audioBuffer.sampleRate, emotion);

    // Build output AudioBuffer
    const out = ctx.createBuffer(1, processed.length, audioBuffer.sampleRate);
    out.getChannelData(0).set(processed);
    return out;
  } catch (e) {
    console.warn('EmotionalVoice: DSP failed, falling back to plain audio', e);
    return null;
  }
}
