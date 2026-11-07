// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Context Budget modal — web parity with the desktop ContextViewerDialog:
// what the model was actually sent last turn, section by section, with the
// REAL text behind every row (capped + scrollable so Chat History can't
// blow the modal up) and a copy button. Reopening a chat restores the last
// saved send; Refresh builds a live estimate. With `messageIndex` it shows the
// prompt that produced that one reply instead (no Refresh).

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

// Mirrors ContextViewerDialog.sectionColors on desktop.
export const SECTION_COLORS: Record<string, string> = {
  'System Prompt': '#3B82F6', // theme-keep: legend identity colour
  Lorebook: '#8B5CF6', // theme-keep: legend identity colour
  Persona: '#06B6D4', // theme-keep: legend identity colour
  Scenario: '#10B981', // theme-keep: legend identity colour
  Examples: '#F59E0B', // theme-keep: legend identity colour
  'Chat History': '#6366F1', // theme-keep: legend identity colour
  'Post-History': '#EF4444', // theme-keep: legend identity colour
  Journal: '#F97316', // theme-keep: legend identity colour
  'Realism Engine': '#EC4899', // theme-keep: legend identity colour
  // A send saved before the section was renamed keeps its colour.
  'Realism Mode': '#EC4899', // theme-keep: legend identity colour
  Memories: '#14B8A6', // theme-keep: legend identity colour
  'Speaker Card': '#7C3AED', // theme-keep: legend identity colour
};
const FALLBACK_COLOR = '#9CA3AF'; // theme-keep: legend identity colour

interface BudgetSection {
  label: string;
  tokens: number;
  text: string;
}
interface Budget {
  contextLimit: number;
  source?: string;
  assembledAt?: string | null;
  textPruned?: boolean;
  /** Oldest messages left out of Chat History (a count, not tokens). */
  droppedMessages?: number;
  sections: BudgetSection[];
}

// Mirrors droppedMessagesNote on desktop.
export function droppedMessagesNote(count: number): string {
  return `${count} older message${count === 1 ? '' : 's'} not sent — trimmed to fit the context.`;
}

function sourceLabel(source?: string): string {
  if (source === 'lastSend') return 'Last send';
  if (source === 'estimate') return 'Estimate (now)';
  if (source === 'reply') return 'This reply';
  return '';
}

function fmtTime(iso?: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function ContextBudgetModal({
  onClose,
  messageIndex,
}: {
  onClose: () => void;
  messageIndex?: number;
}) {
  const forReply = messageIndex !== undefined;
  const [budget, setBudget] = useState<Budget | null>(null);
  const [failed, setFailed] = useState(false);
  const [openLabel, setOpenLabel] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(() => {
    setFailed(false);
    return api
      .get<Budget>(
        forReply
          ? `/api/chat/context-budget?index=${messageIndex}`
          : '/api/chat/context-budget',
      )
      .then(setBudget)
      .catch(() => setFailed(true));
  }, [forReply, messageIndex]);

  useEffect(() => {
    void load();
  }, [load]);

  const refresh = async () => {
    if (refreshing) return;
    setRefreshing(true);
    setFailed(false);
    try {
      const next = await api.post<Budget>('/api/chat/context-budget/refresh', {});
      setBudget(next);
    } catch {
      setFailed(true);
    } finally {
      setRefreshing(false);
    }
  };

  const sections = budget?.sections ?? [];
  const dropped = budget?.droppedMessages ?? 0;
  const total = sections.reduce((a, s) => a + s.tokens, 0);
  const limit = budget?.contextLimit ?? 0;
  const usage = limit > 0 ? total / limit : 0;
  const usageColor =
    usage >= 0.9 ? 'var(--danger)' : usage >= 0.7 ? 'var(--warn)' : 'var(--ok)';
  const src = sourceLabel(budget?.source);
  const when = fmtTime(budget?.assembledAt);

  const copy = async (s: BudgetSection) => {
    try {
      await navigator.clipboard.writeText(s.text);
      setCopied(s.label);
      setTimeout(() => setCopied(null), 1500);
    } catch {
      setCopied(null);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal ctxb-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <div>
            <div>📊 Context Budget</div>
            {src && (
              <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>
                {when ? `${src} · ${when}` : src}
              </div>
            )}
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            {!forReply && (
              <button
                className="link-btn"
                onClick={() => void refresh()}
                disabled={refreshing}
                title="Refresh estimate from this chat"
              >
                {refreshing ? '…' : 'Refresh'}
              </button>
            )}
            <button className="link-btn" onClick={onClose}>Close</button>
          </div>
        </div>

        {failed && (
          <p className="muted">Couldn’t load the context budget — try again.</p>
        )}
        {!failed && budget === null && (
          <div className="centered"><div className="spinner" /></div>
        )}
        {!failed && budget !== null && sections.length === 0 && (
          <p className="muted">
            No budget for this chat yet. Send a message to save the real
            breakdown, or tap Refresh for a quick estimate.
          </p>
        )}

        {sections.length > 0 && (
          <>
            <div className="ctxb-total" style={{ color: usageColor }}>
              <span>Total: {total} / {limit} tokens</span>
              <span>{(usage * 100).toFixed(1)}%</span>
            </div>
            <div className="ctxb-track">
              <div
                className="ctxb-fill"
                style={{
                  width: `${Math.min(100, usage * 100)}%`,
                  background: usageColor,
                }}
              />
            </div>
            {dropped > 0 && (
              <p className="muted ctxb-dropped" style={{ fontSize: 11 }}>
                {droppedMessagesNote(dropped)}
              </p>
            )}
            {budget?.textPruned && (
              <p className="muted" style={{ fontSize: 11 }}>
                Only the token counts are kept for older replies.
              </p>
            )}
            <div className="ctxb-stack">
              {sections.map((s) => (
                <div
                  key={s.label}
                  title={`${s.label}: ${s.tokens} tokens`}
                  style={{
                    flex: Math.max(1, Math.round((s.tokens / total) * 1000)),
                    background: SECTION_COLORS[s.label] ?? FALLBACK_COLOR,
                  }}
                />
              ))}
            </div>

            {sections.map((s) => {
              const color = SECTION_COLORS[s.label] ?? FALLBACK_COLOR;
              const open = openLabel === s.label;
              return (
                <div key={s.label}>
                  <div
                    className="ctxb-row"
                    role="button"
                    onClick={() => setOpenLabel(open ? null : s.label)}
                  >
                    <span className="ctxb-dot" style={{ background: color }} />
                    <span className="ctxb-label">{s.label}</span>
                    <span className="ctxb-tokens" style={{ color }}>
                      {s.tokens}
                    </span>
                    <span className="ctxb-pct">
                      {total > 0 ? ((s.tokens / total) * 100).toFixed(1) : '0'}%
                    </span>
                    <span className="muted">{open ? '▴' : '▾'}</span>
                  </div>
                  {open && (
                    <div className="ctxb-text-wrap" style={{ borderColor: color }}>
                      <button className="link-btn ctxb-copy" onClick={() => void copy(s)}>
                        {copied === s.label ? 'Copied ✓' : 'Copy'}
                      </button>
                      <div className="ctxb-text">
                        <pre>
                          {s.text ||
                            (budget?.textPruned
                              ? '(Not kept for older replies.)'
                              : '(Empty in this snapshot.)')}
                        </pre>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </>
        )}
      </div>
    </div>
  );
}
