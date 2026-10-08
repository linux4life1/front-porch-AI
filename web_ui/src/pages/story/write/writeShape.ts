// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The words and small decisions behind the Write screen, the same ones the
// desktop's story_writer_page.*.dart make inline: the header subtitle, the
// "Rewrite beat n" label, the phrase-list summary, the scene export. Kept pure
// so the two surfaces can be compared line by line.

import type { StoryLens } from '../../../storyTypes';
import type { ConfirmCopy } from '../confirmCopy';
import { normalizeLensId, type SceneRef } from '../storyShape';
import { safeDownloadStem } from '../storyUtil';

/** A lens the writer made (stored under `custom_lenses`); `prompt` is how to write in it. */
export interface CustomLens {
  id: string;
  name: string;
  context: string;
  prompt: string;
}

/** How many phrases the Phrases-to-avoid card shows before "+ N more". */
export const PHRASE_CHIPS = 10;

export const planBeatsAgainCopy: ConfirmCopy = {
  title: 'Plan the beats again?',
  body: 'The beat list is rebuilt. Prose already written for this scene is kept but may no longer line up with the new beats.',
  confirmLabel: 'Plan again',
};

/** The scenes either side of this one in story order; undefined at the ends. */
export function sceneNeighbours(refs: SceneRef[], act: number, index: number): { prev?: SceneRef; next?: SceneRef } {
  const at = refs.findIndex((r) => r.act === act && r.index === index);
  return {
    prev: at > 0 ? refs[at - 1] : undefined,
    next: at >= 0 && at < refs.length - 1 ? refs[at + 1] : undefined,
  };
}

/** "Beat 3 of 14 · Kinetic action · Caravan yard": where in the scene, the lens (studio only), the place. */
export function sceneSubtitle({ beats, written, lens, location }: {
  beats: number;
  written: number;
  lens?: string;
  location?: string;
}): string {
  const where = beats === 0 ? 'No beats yet' : `Beat ${Math.min(Math.max(written + 1, 1), beats)} of ${beats}`;
  return [where, lens, location].filter((part): part is string => !!part).join(' · ');
}

/** The bottom bar's quiet button always names the last written beat. */
export function rewriteWithNoteLabel(written: number, beats: number): string {
  const n = Math.min(Math.max(written, 1), beats === 0 ? 1 : beats);
  return `Rewrite beat ${n} with a note…`;
}

/** The sentence under the phrase chips: how many the engine noticed, which stay for the whole story. */
export function phrasesSummary(own: string[], auto: string[]): string {
  return [
    auto.length > 0
      ? `${auto.length} of these ${auto.length === 1 ? 'was' : 'were'} noticed by the engine in the last chapter`
      : '',
    own.length > 0
      ? `${auto.length > 0 ? 'the rest are' : 'These are'} yours and stay for the whole story`
      : '',
  ].filter(Boolean).join('; ');
}

/** Every lens a scene can use: the built-in ones (a story's own of the same id replaces it), then the story's own with ✎. */
export function projectLenses(builtIn: StoryLens[], custom: CustomLens[]): StoryLens[] {
  return [
    ...builtIn.filter((l) => !custom.some((c) => c.id === l.id)),
    ...custom.map((c) => ({ id: c.id, name: c.name, context: c.context, glyph: '✎' })),
  ];
}

/** The story's lenses with [lens] added under the id its name normalises to (a lens of that id is replaced). */
export function withCustomLens(custom: CustomLens[], lens: Omit<CustomLens, 'id'>): { lenses: CustomLens[]; id: string } {
  const id = normalizeLensId(lens.name);
  return { id, lenses: [...custom.filter((c) => c.id !== id), { ...lens, id }] };
}

/** One phrase per line, blanks dropped. */
export function parsePhraseList(text: string): string[] {
  return text.split('\n').map((s) => s.trim()).filter(Boolean);
}

/** What "Export scene…" saves: the title as a heading, then the scene's prose. */
export function sceneMarkdown(title: string, text: string): string {
  return `# ${title}\n\n${text}`;
}

/** "3.3_The_wagon_fire.md". */
export function sceneFileName(label: string, title: string): string {
  return `${safeDownloadStem(`${label}_${title.replace(/ /g, '_')}`, 'scene')}.md`;
}
