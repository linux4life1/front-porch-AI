// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Context Budget modal — web parity with the desktop ContextViewerDialog:
// what the model was actually sent last turn, section by section, with the
// REAL text behind every row (capped + scrollable so Chat History can't
// blow the modal up) and a copy button. Reopening a chat restores the last
// saved send; Refresh builds a live estimate.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

// Mirrors ContextViewerDialog.sectionColors on desktop.
const SECTION_COLORS: Record<string, string> = {
  'System Prompt': '#3B82F6',
  Lorebook: '#8B5CF6',
  Persona: '#06B6D4',
  Scenario: '#10B981',
  Examples: '#F59E0B',
  'Chat History': '#6366F1',
  'Post-History': '#EF4444',
  Journal: '#F97316',
  'Realism Mode': '#EC4899',
  Memories: '#14B8A6',
  'Speaker Card': '#7C3AED',
};
const FALLBACK_COLOR = '#9CA3AF';

interface BudgetSection {
  label: string;
  tokens: number;
  text: string;
}
interface Budget {
  contextLimit: number;
  source?: string;
  assembledAt?: string | null;
  sections: BudgetSection[];
}

function sourceLabel(source?: string): string {
  if (source === 'lastSend') return 'Last send';
  if (source === 'estimate') return 'Estimate (now)';
  return '';
}

function fmtTime(iso?: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function ContextBudgetModal({ onClose }: { onClose: () => void }) {
  const [budget, setBudget] = useState<Budget | null>(null);
  const [failed, setFailed] = useState(false);
  const [openLabel, setOpenLabel] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(() => {
    setFailed(false);
    return api
      .get<Budget>('/api/chat/context-budget')
      .then(setBudget)
      .catch(() => setFailed(true));
  }, []);

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
  const total = sections.reduce((a, s) => a + s.tokens, 0);
  const limit = budget?.contextLimit ?? 0;
  const usage = limit > 0 ? total / limit : 0;
  const usageColor = usage >= 0.9 ? '#f87171' : usage >= 0.7 ? '#fbbf24' : '#4ade80';
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
            <button
              className="link-btn"
              onClick={() => void refresh()}
              disabled={refreshing}
              title="Refresh estimate from this chat"
            >
              {refreshing ? '…' : 'Refresh'}
            </button>
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
                          {s.text || '(Empty in this snapshot.)'}
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
