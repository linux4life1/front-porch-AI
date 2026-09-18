// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared chat-tools snapshot type and the two tiny field widgets every
// section uses. Lives beside the shell so Memory / Realism / Objectives
// do not circular-import ChatTools.tsx.

import { useEffect, useState } from 'react';
import { type GroupBlock } from './GroupSettings';
import { type ObjectiveView } from './ObjectivesPanel';

export interface ToolsState {
  wikiBaseUrl?: string;
  wikiSavedUrls?: string[];
  realismEnabled: boolean;
  needsEnabled: boolean;
  realismOneShotEval: boolean;
  // Tri-state One-Shot mode (2026-08-10). Optional: absent on an older
  // facade, in which case the legacy bool still tells us on-vs-not.
  realismOneShotMode?: 'auto' | 'on' | 'off';
  memory: {
    ragEnabled: boolean;
    ragRetrievalCount: number;
    ragWindowSize: number;
    journalEnabled: boolean;
    journalInterval: number;
    journalReviewFirst?: boolean;
    importLlmertaPorchMemories?: boolean;
    growthEnabled: boolean;
    growthInterval: number;
    growthReviewFirst: boolean;
    // Host embedding-engine status (additive). Download only runs on desktop.
    embedding?: {
      available?: boolean;
      modelOnDisk?: boolean;
      settingUp?: boolean;
      setupProgress?: number;
      setupStatus?: string;
      setupError?: string | null;
      lastEngineError?: string | null;
    } | null;
    // The last reply's retrieval receipt (additive, 2026-08-10 — absent on
    // older facades; null when that reply needed no retrieval). Desktop
    // sidebar parity: what memory found / dropped / actually injected.
    lastRagReceipt?: {
      status?: 'ok' | 'error' | 'not_operational';
      found: number;
      journal_deduped: number;
      budget_trimmed: number;
      injected: Array<{
        pos: number;
        day?: number | null;
        other_chat: boolean;
        preview: string;
      }>;
    } | null;
  };
  // The Journal's per-chat recap ("Where we are") — key kept as `summary`
  // to match the facade block name.
  summary: {
    text: string;
    paused: boolean;
    isGenerating: boolean;
    lastIndex: number;
  };
  chaos: { enabled: boolean; nsfwEnabled: boolean; pressure: number; hasPendingEvent: boolean };
  nsfw: { cooldownEnabled: boolean; cooldownTurnsRemaining: number; arousalLevel: number; arousalTier: string };
  // Ambitions (Living Time §6, additive — absent on older facades).
  // `step` is the open quest climbing this ambition (v46); null when none.
  standingMood?: string;
  ambitions?: Array<{ text: string; progress: number; stage: string; step?: string | null }>;
  // Pockets & Wardrobe (additive, null when the switch is off). set_aside:
  // parked in the scene, still theirs — clothing entries expire at the next
  // story morning server-side, so what arrives here is always current.
  pockets?: {
    worn?: Array<{ name: string; state?: string }>;
    carrying?: Array<{ name: string; state?: string }>;
    set_aside?: Array<{ name: string; state?: string; clothing?: boolean; day?: number }>;
  } | null;
  time: {
    timeOfDay: string;
    dayCount: number;
    weekday: string;
    passageEnabled: boolean;
    // Additive: absent on older hosts. Fallback is realismEnabled (the old gate).
    clockRunning?: boolean;
    // Living Time story weather (additive — absent on older facades, null
    // when the feature is off).
    weather?: {
      condition: string;
      temp: string;
      season: string;
      label: string;
      emoji: string;
      // Intra-day fields (additive — absent on older facades). label/emoji
      // already lead with the current day-part; these expose the raw pieces.
      segment?: string | null;
      segmentCondition?: string | null;
      tempC?: number | null;
      tempF?: number | null;
      unit?: string | null;
      dayLabel?: string | null;
      // Deterministic forecast (additive — absent on older facades). The
      // desktop engine's walk is prefix-stable, so this is exactly what the
      // next story day will be.
      tomorrow?: {
        condition: string;
        temp: string;
        season: string;
        label: string;
        emoji: string;
      } | null;
    } | null;
    // Story Calendar (additive — absent on older facades).
    clock?: string;
    date?: string;
    dateLong?: string;
    storyClock?: string;
    storyStartDate?: string;
    presence?: string | null;
    todaySentence?: string | null;
  };
  objectives: {
    primary: ObjectiveView | null;
    secondary: ObjectiveView[];
    isChecking: boolean;
    // Additive: absent on older hosts — treat missing as on (legacy always-on).
    enabled?: boolean;
  };
  focusedId?: string | null;
  group?: GroupBlock | null;
}

export type ToolsApply = (p: Promise<unknown>) => void;
export type ToolsSettings = (fields: Record<string, unknown>) => void;
export type ToolsToggle = (name: string, value: boolean, extra?: Record<string, unknown>) => void;

/** Small labelled on/off switch. */
export function Toggle({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="tool-toggle">
      <span>{label}</span>
      <input type="checkbox" checked={value} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

/** Number field that commits on blur / Enter (avoids a save per keystroke). */
export function NumField({
  label,
  value,
  onCommit,
}: {
  label: string;
  value: number;
  onCommit: (v: number) => void;
}) {
  const [draft, setDraft] = useState(String(value));
  useEffect(() => setDraft(String(value)), [value]);
  const commit = () => {
    const n = parseInt(draft, 10);
    if (!Number.isNaN(n) && n !== value) onCommit(n);
  };
  return (
    <label className="tool-num">
      <span>{label}</span>
      <input
        type="number"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => e.key === 'Enter' && commit()}
      />
    </label>
  );
}
