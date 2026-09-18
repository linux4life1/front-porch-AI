// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Memory half of the chat-tools sidebar: wiki pick, RAG / embedding, journal,
// growth, and the "Where we are" recap. Desktop twin is chat_tools_facade.memory.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { ExpandableText } from './ExpandableText';
import { GrowthPanel } from './GrowthPanel';
import { JournalPanel } from './JournalPanel';
import { SummaryRecapField } from './SummaryRecapField';
import {
  NumField,
  Toggle,
  type ToolsApply,
  type ToolsSettings,
  type ToolsState,
  type ToolsToggle,
} from './ChatToolsShared';

function wikiHostLabel(url: string): string {
  try {
    const u = new URL(url.includes('://') ? url : `https://${url}`);
    const path = u.pathname.replace(/\/$/, '');
    if (!path) return u.host || url;
    return `${u.host}${path}`;
  } catch {
    return url;
  }
}

export function ChatToolsWiki({
  t,
  q,
  apply,
}: {
  t: ToolsState;
  q: string;
  apply: ToolsApply;
}) {
  return (
    <WikiPicker
      value={t.wikiBaseUrl ?? ''}
      saved={t.wikiSavedUrls ?? []}
      onSave={(url) => apply(api.post<ToolsState>(`/api/chat/tools/wiki${q}`, { wikiBaseUrl: url }))}
    />
  );
}

function WikiPicker({
  value,
  saved,
  onSave,
}: {
  value: string;
  saved: string[];
  onSave: (url: string) => void;
}) {
  const urls = [...saved];
  if (value && !urls.includes(value)) urls.unshift(value);
  if (urls.length === 0 && !value) return null;
  return (
    <details className="tool-section" data-testid="wiki-picker" open>
      <summary>Wiki</summary>
      <div className="tool-body">
        <p className="muted small">Looks up this wiki only (MediaWiki / Fandom). Not Google.</p>
        <label className="tool-toggle">
          <span>None (off for this chat)</span>
          <input
            type="radio"
            name="wiki-pick"
            checked={!value}
            onChange={() => onSave('')}
          />
        </label>
        {urls.map((url) => (
          <label key={url} className="tool-toggle">
            <span>{wikiHostLabel(url)}</span>
            <input
              type="radio"
              name="wiki-pick"
              checked={value === url}
              onChange={() => onSave(url)}
            />
          </label>
        ))}
      </div>
    </details>
  );
}

function EmbeddingStatus({ t }: { t: ToolsState }) {
  const e = t.memory.embedding;
  if (!e) {
    return (
      <p className="muted small">
        Memory setup runs on the desktop app (one ~550&nbsp;MB local model).
      </p>
    );
  }
  if (e.available) {
    return <p className="muted small">Memory engine ready — private on this computer.</p>;
  }
  if (e.settingUp) {
    const pct =
      typeof e.setupProgress === 'number' && e.setupProgress >= 0
        ? Math.round(e.setupProgress * 100)
        : null;
    return (
      <div className="rag-engine-status">
        <p className="muted small">{e.setupStatus || 'Setting up memory…'}</p>
        <div className="rag-progress-track" aria-hidden>
          <div
            className="rag-progress-fill"
            style={pct == null ? { width: '30%', opacity: 0.5 } : { width: `${pct}%` }}
          />
        </div>
        {pct != null && <p className="muted small">{pct}%</p>}
      </div>
    );
  }
  if (e.setupError || e.lastEngineError) {
    return (
      <p className="muted small rag-engine-error">
        Setup failed: {e.setupError || e.lastEngineError}. Use the desktop app to
        retry the download.
      </p>
    );
  }
  if (!e.modelOnDisk) {
    return (
      <p className="muted small">
        Memory model not installed yet. Open this chat on the desktop app and turn
        Memory on to download it (~550&nbsp;MB, one time).
      </p>
    );
  }
  return <p className="muted small">Starting memory engine…</p>;
}

function LastRagReceipt({ t }: { t: ToolsState }) {
  const r = t.memory.lastRagReceipt;
  const status = r?.status ?? 'ok';
  const counts = r
    ? [
        r.budget_trimmed > 0 ? `${r.budget_trimmed} trimmed for space` : null,
        r.journal_deduped > 0 ? `${r.journal_deduped} already covered by the journal` : null,
      ].filter(Boolean)
    : [];
  const suffix = counts.length ? ` (${counts.join(', ')})` : '';
  let summary: string;
  if (!r) {
    summary = 'Last reply: nothing had scrolled out of view — no lookup needed.';
  } else if (status === 'error') {
    summary =
      'Last reply: tried to search the archive but the memory engine hit an error — nothing was brought back.';
  } else if (status === 'not_operational') {
    summary =
      'Last reply: older messages had scrolled out of view, but the memory engine is not ready — install/start Memory on the desktop host to look them up.';
  } else if (r.injected.length === 0) {
    summary = `Last reply: searched the archive — nothing relevant enough to bring back.${suffix}`;
  } else {
    summary = `Last reply: ${r.injected.length} ${r.injected.length === 1 ? 'memory' : 'memories'} woven in.${suffix}`;
  }
  return (
    <div className="rag-receipt">
      <p className="muted small">{summary}</p>
      {status === 'ok' && r?.injected.map((line, i) => (
        <div key={i} className="rag-receipt-line">
          <strong>{line.other_chat ? 'another chat' : line.day != null ? `Day ${line.day}` : ''}</strong>{' '}
          <ExpandableText text={line.preview} lines={4} className="muted small" />
        </div>
      ))}
    </div>
  );
}

export function ChatToolsMemory({
  t,
  focusedId,
  reloadKey,
  settings,
}: {
  t: ToolsState;
  focusedId?: string | null;
  reloadKey: number;
  settings: ToolsSettings;
}) {
  return (
    <>
      <details className="tool-section">
        <summary>Memory</summary>
        <div className="tool-body">
          <Toggle label="Use memory (RAG)" value={t.memory.ragEnabled} onChange={(v) => settings({ ragEnabled: v })} />
          {t.memory.ragEnabled && (
            <>
              <EmbeddingStatus t={t} />
              <NumField
                label="Past moments per reply"
                value={t.memory.ragRetrievalCount}
                onCommit={(v) => settings({ ragRetrievalCount: v })}
              />
              <p className="muted small">How many old moments to weave into each reply (0 = all strong matches).</p>
              <NumField
                label="Messages per moment"
                value={t.memory.ragWindowSize}
                onCommit={(v) => settings({ ragWindowSize: v })}
              />
              <p className="muted small">How much of each past scene to keep (3–10 messages).</p>
              <LastRagReceipt t={t} />
            </>
          )}
          <Toggle label="Journal (memories + recap)" value={t.memory.journalEnabled} onChange={(v) => settings({ journalEnabled: v })} />
          {t.memory.journalEnabled ? (
            <>
              <NumField label="Every (msgs)" value={t.memory.journalInterval} onCommit={(v) => settings({ journalInterval: v })} />
              <Toggle
                label="Review journal before it applies"
                value={t.memory.journalReviewFirst ?? false}
                onChange={(v) => settings({ journalReviewFirst: v })}
              />
              <JournalPanel focusedId={focusedId} reloadKey={reloadKey} />
            </>
          ) : (
            <p className="muted small">
              Journal off: long-term memory AND the &quot;Where we are&quot; recap are
              paused — the character only remembers what still fits in the
              context window.
            </p>
          )}
          <Toggle
            label="Import Mafia game nights"
            value={t.memory.importLlmertaPorchMemories ?? true}
            onChange={(v) => settings({ importLlmertaPorchMemories: v })}
          />
          <p className="muted small">
            Plant LLMerta Mafia nights into The Journal when you open a matching
            chat; the character brings up the night on their next reply.
          </p>
        </div>
      </details>

      <details className="tool-section">
        <summary>Growth 🌱</summary>
        <div className="tool-body">
          <Toggle label="Character growth" value={t.memory.growthEnabled} onChange={(v) => settings({ growthEnabled: v })} />
          {!t.memory.growthEnabled && (
            <p className="muted small">
              Characters grow small, evidence-backed &quot;rings&quot; as you chat — the
              original card is always preserved.
            </p>
          )}
          {t.memory.growthEnabled && (
            <>
              <NumField label="Check every (msgs)" value={t.memory.growthInterval} onCommit={(v) => settings({ growthInterval: v })} />
              <Toggle
                label="Review growth before it applies"
                value={t.memory.growthReviewFirst}
                onChange={(v) => settings({ growthReviewFirst: v })}
              />
              <GrowthPanel focusedId={focusedId} reloadKey={reloadKey} />
            </>
          )}
        </div>
      </details>
    </>
  );
}

export function ChatToolsRecap({
  t,
  q,
  apply,
  toggle,
  reloadKey,
}: {
  t: ToolsState;
  q: string;
  apply: ToolsApply;
  toggle: ToolsToggle;
  reloadKey: number;
}) {
  const [editingRecap, setEditingRecap] = useState(false);
  useEffect(() => {
    setEditingRecap(false);
  }, [reloadKey]);

  return (
      <details className="tool-section">
        <summary>Where we are</summary>
        <div className="tool-body">
          <SummaryRecapField
            value={t.summary.text}
            editing={editingRecap}
            onCommit={(text) => apply(api.post<ToolsState>(`/api/chat/tools/summary${q}`, { text }))}
            onStartEditing={() => setEditingRecap(true)}
            onStopEditing={() => setEditingRecap(false)}
          />
          <div className="tool-row">
            {t.summary.text.trim() !== '' && (
              <button
                type="button"
                onClick={() => setEditingRecap((v) => !v)}
              >
                {editingRecap ? 'Done' : 'Edit'}
              </button>
            )}
            <button
              className="primary"
              disabled={t.summary.isGenerating}
              onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/summary${q}`, { action: 'regenerate' }))}
            >
              {t.summary.isGenerating ? 'Generating…' : 'Regenerate'}
            </button>
          </div>
          <Toggle label="Pause journal updates" value={t.summary.paused} onChange={(v) => toggle('summaryPaused', v)} />
        </div>
      </details>
  );
}
