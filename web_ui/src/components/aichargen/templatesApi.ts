// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Creator templates on the phone (docs/design/creator-templates.md): the
// relay's list read defensively, save, rename and delete, and the name rules
// the desktop has too (slug, problems, summary and saved lines). Both
// surfaces read their vectors from
// test/fixtures/chargen/creator_template_vectors.json.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { ChargenMode } from './chargenForm';

/** The canonical flat form a template file holds (see templateForm.ts). */
export type TemplateForm = Record<string, unknown>;

export type TemplateSummary = {
  mode: ChargenMode;
  perspective: 'first' | 'third';
  tense: 'present' | 'past';
  lore: boolean;
  nsfw: boolean;
  /** A built-in's archetype keywords, comma separated. */
  blurb: string;
};

export type CreatorTemplate = {
  slug: string;
  name: string;
  savedAt: string | null;
  builtIn: boolean;
  /** The file could not be read: the tile offers only Delete. */
  broken: boolean;
  problem: string | null;
  summary: TemplateSummary;
  form: TemplateForm;
};

/** The template the form was loaded from (the Started from pill). */
export type TemplateStart = { slug: string; name: string; builtIn: boolean };

export const TAKEN_PROBLEM = 'Another template already has this name.';
export const REPLACES_CAPTION = 'A template with this name already exists. Saving replaces it.';
const NAME_CAP = 80;
const SLUG_CAP = 48;
const DEVICE_NAMES = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MODE_LABEL: Record<ChargenMode, string> = { quick: 'Quick', guided: 'Guided', automated: 'Automated' };

const str = (v: unknown) => (typeof v === 'string' ? v : '');
const obj = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};

function summaryOf(raw: unknown): TemplateSummary {
  const s = obj(raw);
  return {
    mode: s.mode === 'guided' || s.mode === 'automated' ? s.mode : 'quick',
    perspective: s.perspective === 'third' ? 'third' : 'first',
    tense: s.tense === 'past' ? 'past' : 'present',
    lore: s.lore === true,
    nsfw: s.nsfw === true,
    blurb: str(s.blurb),
  };
}

/** One entry of the relay's answer; null when it names no template. */
export function templateOf(raw: unknown): CreatorTemplate | null {
  const t = obj(raw);
  const slug = str(t.slug);
  if (!slug) return null;
  return {
    slug,
    name: str(t.name) || slug,
    savedAt: str(t.savedAt) || null,
    builtIn: t.builtIn === true,
    broken: t.broken === true,
    problem: str(t.problem) || null,
    summary: summaryOf(t.summary),
    form: obj(t.form),
  };
}

/** GET /api/chargen/templates read defensively: yours newest first, then
 *  the built-ins, as the relay orders them. */
export function templatesOf(raw: unknown): CreatorTemplate[] {
  const list = obj(raw).templates;
  return (Array.isArray(list) ? list : []).map(templateOf).filter((t): t is CreatorTemplate => t !== null);
}

const pathOf = (slug: string) => `/api/chargen/templates/${encodeURIComponent(slug)}`;

export async function listTemplates(): Promise<CreatorTemplate[]> {
  return templatesOf(await api.get<unknown>('/api/chargen/templates'));
}

/** Create or replace the template of this name. The relay merges the keys
 *  sent over the stored file (and over [basedOn]), so keys only the
 *  desktop knows survive a phone save. */
export async function saveTemplate(
  name: string,
  form: TemplateForm,
  basedOn?: string,
): Promise<{ template: CreatorTemplate | null; replaced: boolean }> {
  const body = { name: name.trim(), form, ...(basedOn ? { basedOn } : {}) };
  const r = obj(await api.put<unknown>(pathOf(templateSlug(name)), body));
  return { template: templateOf(r.template), replaced: r.replaced === true };
}

export async function renameTemplate(slug: string, name: string): Promise<CreatorTemplate | null> {
  return templateOf(obj(await api.post<unknown>(`${pathOf(slug)}/rename`, { name: name.trim() })).template);
}

export async function deleteTemplate(slug: string): Promise<void> {
  await api.del<unknown>(pathOf(slug));
}

/** FNV-1a 32-bit over UTF-16 code units, as 8 hex digits. */
function fnv1a32(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

const hasNonAscii = (s: string) => [...s].some((c) => c.charCodeAt(0) > 127);

/** The file name a template's name saves under (the desktop's rule). */
export function templateSlug(name: string): string {
  const lowered = name.trim().toLowerCase();
  const ascii = (lowered.match(/[a-z0-9]+/g) ?? []).join('-').slice(0, SLUG_CAP).replace(/-+$/, '');
  if (ascii === '' || hasNonAscii(lowered)) {
    const hash = fnv1a32(lowered);
    return ascii ? `${ascii}-${hash}` : hash;
  }
  return DEVICE_NAMES.test(ascii) ? `${ascii}-template` : ascii;
}

/** Why this name cannot be saved, or null. A built-in is matched by slug
 *  and named as the app names it. */
export function templateNameProblem(name: string, builtIns: readonly { slug: string; name: string }[]): string | null {
  const trimmed = name.trim();
  if (!trimmed) return 'Give the template a name.';
  if (trimmed.length > NAME_CAP) return 'Keep the name to 80 characters or fewer.';
  const slug = templateSlug(trimmed);
  const builtIn = builtIns.find((b) => b.slug === slug);
  return builtIn ? `${builtIn.name} is a built-in template and can't be changed. Give yours another name.` : null;
}

/** A tile's line: the phone's `{Mode} · lore on · 18+`; wide adds the voice
 *  after the mode, as the desktop does. */
export function summaryLine(s: TemplateSummary, wide = false): string {
  const parts = [MODE_LABEL[s.mode]];
  if (wide) parts.push(`${s.perspective === 'third' ? '3rd' : '1st'} person, ${s.tense}`);
  if (s.lore) parts.push('lore on');
  if (s.nsfw) parts.push('18+');
  return parts.join(' · ');
}

/** A built-in's line: its mode and keywords from the archetype (one on the
 *  phone, two wide), leaving out the archetype's own name. */
export function builtInLine(t: Pick<CreatorTemplate, 'name' | 'summary'>, wide = false): string {
  const words = t.summary.blurb
    .split(',')
    .map((w) => w.trim())
    .filter((w) => w && w.toLowerCase() !== t.name.toLowerCase());
  const blurb = words.slice(0, wide ? 2 : 1).join(', ');
  return blurb ? `${MODE_LABEL[t.summary.mode]} · ${blurb}` : MODE_LABEL[t.summary.mode];
}

/** `Saved 4 Oct`, with the year when it is not this year; '' without a date. */
export function savedLabel(iso: string | null, now: Date = new Date()): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const day = `Saved ${d.getDate()} ${MONTHS[d.getMonth()]}`;
  return d.getFullYear() === now.getFullYear() ? day : `${day} ${d.getFullYear()}`;
}

/** The last tile's label for the built-in count ("All 15 built in"). */
export const builtInLabel = (count: number) => `All ${count} built in`;

/** The list for the creator: loaded on mount, reloaded after a change. A
 *  reload that a newer one overtook is dropped. */
export function useTemplates() {
  const [templates, setTemplates] = useState<CreatorTemplate[] | null>(null);
  const [error, setError] = useState('');
  const ticket = useRef(0);
  const reload = useCallback(async () => {
    const mine = ++ticket.current;
    try {
      const list = await listTemplates();
      if (mine !== ticket.current) return;
      setTemplates(list);
      setError('');
    } catch (e) {
      console.warn('[creator] the templates could not be loaded', e);
      if (mine === ticket.current) setError('The templates could not be loaded. Check the connection, then try again.');
    }
  }, []);
  useEffect(() => {
    void reload();
  }, [reload]);
  return { templates, error, reload };
}
