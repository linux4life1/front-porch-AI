// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure payload/merge logic for AI Enhance (grow an existing character from a
// real chat). Kept out of the components so vitest can pin it — the same rule
// chargenForm.ts follows. The server contract:
//   POST /api/chargen/enhance  {characterId, sessionId, fields, nsfwEnabled}
//   → ws `chargen_enhance_done` {characterId, proposal}
// Apply then rides the EXISTING endpoints: POST /api/characters/<id>/duplicate
// {newName} followed by POST /api/characters/<newId> with the accepted fields.

/** Mirrors the Dart EnhanceSelection JSON shape (chat_grounding.dart). */
export interface EnhanceSelection {
  description: boolean;
  personality: boolean;
  exampleDialogue: boolean;
  scenario: boolean;
  greetings: boolean;
  lorebook: boolean;
  porchLife: boolean;
}

export const DEFAULT_ENHANCE_SELECTION: EnhanceSelection = {
  description: true,
  personality: true,
  exampleDialogue: true,
  scenario: false,
  greetings: false,
  lorebook: false,
  porchLife: true,
};

export function anySelected(s: EnhanceSelection): boolean {
  return (
    s.description ||
    s.personality ||
    s.exampleDialogue ||
    s.scenario ||
    s.greetings ||
    s.lorebook ||
    s.porchLife
  );
}

export interface EnhancePorchLife {
  ambitions: string[];
  likes: string[];
  dislikes: string[];
  worn: string[];
  carrying: string[];
  intimateInto: string[];
  intimateNotInto: string[];
}

/** What `chargen_enhance_done` carries — only the selected keys are present. */
export interface EnhanceProposal {
  description?: string;
  personality?: string;
  mesExample?: string;
  scenario?: string;
  firstMessage?: string;
  alternateGreetings?: string[];
  lorebook?: unknown;
  porchLife?: EnhancePorchLife;
}

/** Per-section "use this" toggles in the review step. */
export interface EnhanceAccepted {
  description: boolean;
  personality: boolean;
  exampleDialogue: boolean;
  scenario: boolean;
  greetings: boolean;
  lorebook: boolean;
  porchLife: boolean;
}

/** Review-step edits (text the user tweaked before applying). */
export interface EnhanceEdits {
  description?: string;
  personality?: string;
  mesExample?: string;
  scenario?: string;
  firstMessage?: string;
  alternateGreetings?: string[];
  porchLife?: EnhancePorchLife;
}

export function buildEnhancePayload(
  characterId: string,
  sessionId: string,
  selection: EnhanceSelection,
  nsfwEnabled: boolean,
  modelId = '',
) {
  return {
    characterId,
    sessionId,
    fields: selection,
    nsfwEnabled,
    // Remote backends only: which model runs THIS enhance (the server resolves
    // it ad-hoc; the app's active model is never switched). '' = active model.
    ...(modelId ? { modelId } : {}),
  };
}

/** True when a proposed text field has something to accept. */
export function hasProposedText(value: string | undefined): boolean {
  return !!value?.trim();
}

/**
 * Per-field Use this defaults for text sections. Empty proposed text
 * starts OFF so a mute model cannot wipe the original. Does not touch
 * porchLife — that already special-cases empty in the review modal.
 */
export function withEmptyTextUseOff(
  selection: EnhanceSelection,
  proposal: EnhanceProposal,
): Pick<
  EnhanceAccepted,
  'description' | 'personality' | 'exampleDialogue' | 'scenario' | 'greetings'
> {
  return {
    description: selection.description && hasProposedText(proposal.description),
    personality: selection.personality && hasProposedText(proposal.personality),
    exampleDialogue: selection.exampleDialogue && hasProposedText(proposal.mesExample),
    scenario: selection.scenario && hasProposedText(proposal.scenario),
    greetings:
      selection.greetings &&
      (hasProposedText(proposal.firstMessage) ||
        (proposal.alternateGreetings?.some((g) => !!g.trim()) ?? false)),
  };
}

function loreEntries(book: unknown): Record<string, unknown>[] {
  if (!book || typeof book !== 'object') return [];
  const entries = (book as { entries?: unknown }).entries;
  if (!Array.isArray(entries)) return [];
  return entries.filter((e): e is Record<string, unknown> => !!e && typeof e === 'object');
}

function loreEntryName(entry: Record<string, unknown>): string {
  const name = typeof entry.name === 'string' ? entry.name.trim() : '';
  if (name) return name;
  return typeof entry.comment === 'string' ? entry.comment.trim() : '';
}

/**
 * Append proposed lore entries onto the original book. Same-name incoming
 * entries replace; never assign the proposal as the whole book.
 */
export function mergeLorebook(original: unknown, incoming: unknown): Record<string, unknown> {
  const origEntries = loreEntries(original);
  const add = loreEntries(incoming);
  const entries = [...origEntries];
  for (const entry of add) {
    const name = loreEntryName(entry);
    const i = name ? entries.findIndex((e) => loreEntryName(e) === name) : -1;
    if (i >= 0) entries[i] = entry;
    else entries.push(entry);
  }
  const rest =
    original && typeof original === 'object' && !Array.isArray(original)
      ? { ...(original as Record<string, unknown>) }
      : {};
  delete rest.entries;
  return { ...rest, entries };
}

/** Authored Porch Life on the duplicate — empty proposed lists keep these. */
export type EnhanceApplyOriginal = {
  lorebook?: unknown;
  ambitions?: string[];
  likes?: string[];
  dislikes?: string[];
  intimateInto?: string[];
  intimateNotInto?: string[];
  inventory?: { worn?: unknown[]; carrying?: unknown[] };
};

/** Keep [authored] when [proposed] is missing or empty. */
export function keepAuthoredIfEmpty(
  proposed: string[] | undefined,
  authored: string[] | undefined,
): string[] {
  return proposed && proposed.length > 0 ? proposed : (authored ?? []);
}

function inventoryNames(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const item of raw) {
    if (typeof item === 'string' && item.trim()) out.push(item);
    else if (item && typeof item === 'object' && typeof (item as { name?: unknown }).name === 'string') {
      const name = ((item as { name: string }).name).trim();
      if (name) out.push(name);
    }
  }
  return out;
}

/**
 * The partial-update body for `POST /api/characters/<newId>`: only accepted
 * sections are included (the duplicate already carries the original for the
 * rest), and a user edit wins over the raw proposal.
 */
export function buildApplyBody(
  proposal: EnhanceProposal,
  accepted: EnhanceAccepted,
  edits: EnhanceEdits = {},
  original: EnhanceApplyOriginal = {},
): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  if (accepted.description && proposal.description !== undefined) {
    body.description = edits.description ?? proposal.description;
  }
  if (accepted.personality && proposal.personality !== undefined) {
    body.personality = edits.personality ?? proposal.personality;
  }
  if (accepted.exampleDialogue && proposal.mesExample !== undefined) {
    body.mesExample = edits.mesExample ?? proposal.mesExample;
  }
  if (accepted.scenario && proposal.scenario !== undefined) {
    body.scenario = edits.scenario ?? proposal.scenario;
  }
  if (accepted.greetings) {
    if (proposal.firstMessage !== undefined) {
      body.firstMessage = edits.firstMessage ?? proposal.firstMessage;
    }
    if (proposal.alternateGreetings !== undefined) {
      body.alternateGreetings = edits.alternateGreetings ?? proposal.alternateGreetings;
    }
  }
  if (accepted.lorebook && proposal.lorebook != null) {
    body.lorebook = mergeLorebook(original.lorebook, proposal.lorebook);
  }
  if (accepted.porchLife && proposal.porchLife) {
    const p = edits.porchLife ?? proposal.porchLife;
    body.ambitions = keepAuthoredIfEmpty(p.ambitions, original.ambitions);
    body.likes = keepAuthoredIfEmpty(p.likes, original.likes);
    body.dislikes = keepAuthoredIfEmpty(p.dislikes, original.dislikes);
    body.intimateInto = keepAuthoredIfEmpty(p.intimateInto, original.intimateInto);
    body.intimateNotInto = keepAuthoredIfEmpty(p.intimateNotInto, original.intimateNotInto);
    body.inventory = {
      worn: keepAuthoredIfEmpty(p.worn, inventoryNames(original.inventory?.worn)),
      carrying: keepAuthoredIfEmpty(p.carrying, inventoryNames(original.inventory?.carrying)),
    };
  }
  return body;
}
