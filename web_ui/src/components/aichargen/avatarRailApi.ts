// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review rail's verbs (PR 8d): the saved card's gallery, the portrait
// upload the web never had, expression uploads with a label, the ZIP import,
// the image engine's readiness, and one portrait render. Everything else
// (expression packs) rides the Image Studio's packApi.

import { api } from '../../api/client';

const enc = encodeURIComponent;

export type AvatarItem = {
  id: string;
  label: string;
  displayOrder: number;
  isPrime: boolean;
  isLook: boolean;
  isFavorite: boolean;
};

/** The desktop's EmotionLabels.all (lib/utils/emotion_labels.dart), copied
 *  once here; the host validates the same list on the label route. */
export const EMOTION_LABELS = [
  'admiration',
  'affection',
  'amusement',
  'anger',
  'annoyance',
  'anticipation',
  'approval',
  'caring',
  'confusion',
  'curiosity',
  'desire',
  'disappointment',
  'disapproval',
  'disgust',
  'embarrassment',
  'excitement',
  'fear',
  'gratitude',
  'grief',
  'joy',
  'love',
  'nervousness',
  'optimism',
  'pride',
  'realization',
  'relief',
  'remorse',
  'sadness',
  'surprise',
  'neutral',
] as const;

/** The desktop's EmotionLabels.emoji, for the tag dialog's chips. */
export const EMOTION_EMOJI: Record<string, string> = {
  admiration: '🤩',
  affection: '💕',
  amusement: '😄',
  anger: '😠',
  annoyance: '😤',
  anticipation: '👀',
  approval: '👍',
  caring: '🤗',
  confusion: '😕',
  curiosity: '🧐',
  desire: '🥵',
  disappointment: '😞',
  disapproval: '👎',
  disgust: '🤢',
  embarrassment: '😳',
  excitement: '🤩',
  fear: '😨',
  gratitude: '🙏',
  grief: '😭',
  joy: '😁',
  love: '😍',
  nervousness: '😰',
  optimism: '😊',
  pride: '😎',
  realization: '💡',
  relief: '😌',
  remorse: '😔',
  sadness: '😢',
  surprise: '😲',
  neutral: '😐',
};

export const listAvatars = (id: string) =>
  api.get<{ avatars: AvatarItem[] }>(`/api/characters/${enc(id)}/avatars`);

export const uploadPortrait = (id: string, blob: Blob) =>
  api.upload<{ ok: boolean }>(
    `/api/characters/${enc(id)}/portrait`,
    new File([blob], 'portrait.png', { type: blob.type || 'image/png' }),
  );

export const uploadLook = (id: string, blob: Blob) =>
  api.upload<{ avatars: AvatarItem[] }>(
    `/api/characters/${enc(id)}/looks`,
    new File([blob], 'look.png', { type: blob.type || 'image/png' }),
  );

export const uploadExpression = (id: string, blob: Blob, label: string) =>
  api.upload<{ avatars: AvatarItem[] }>(
    `/api/characters/${enc(id)}/avatars?label=${enc(label)}`,
    new File([blob], 'expression.png', { type: blob.type || 'image/png' }),
  );

export const importExpressionZip = (id: string, file: File) =>
  api.upload<{ added: number; unrecognized: number; avatars: AvatarItem[] }>(
    `/api/characters/${enc(id)}/expressions/import-zip`,
    file,
  );

export type StudioReady = {
  ready: boolean;
  line?: string;
  primary?: string;
  mode?: string;
  reachable?: boolean;
};

export const studioReady = () => api.get<StudioReady>('/api/image/studio/ready');

export type GenerateResult = { image: string; savedPath?: string; filename?: string };

/** One portrait render (the desktop's `isPortrait: true`). */
export const generatePortrait = (prompt: string) =>
  api.post<GenerateResult>('/api/image/generate', { prompt, isPortrait: true });

export const portraitUrl = (id: string, version: number) =>
  `/api/characters/${enc(id)}/avatar?w=512&v=${version}`;

/** A data URL as a File the upload routes accept. */
export async function dataUrlToFile(dataUrl: string): Promise<File> {
  const res = await fetch(dataUrl);
  const blob = await res.blob();
  return new File([blob], 'portrait.png', { type: blob.type || 'image/png' });
}
