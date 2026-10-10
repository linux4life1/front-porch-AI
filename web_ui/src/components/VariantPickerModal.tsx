// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared greet / regenerated-swipe picker. One GET lists cards; tapping a
// card POSTs select-variant and closes (commit-once). Expand/copy do not
// commit.

import { FormEvent, useEffect, useState } from 'react';
import { api } from '../api/client';
import { describeActionFailure } from '../pages/chat/chatActionError';

interface VariantRow {
  index: number;
  snippet: string;
  text?: string;
  charCount: number;
  tokenCount?: number;
  current: boolean;
  kind?: string;
  /** Desktop's row label ("Original", "Regen 1", "Greet"); older apps omit it. */
  label?: string;
}

export function variantKindLabel(kind?: string): string {
  return kind === 'greet' ? 'Greet' : 'Regen';
}

function approxTokens(chars: number): number {
  return chars <= 0 ? 0 : Math.ceil(chars / 4);
}

interface Payload {
  kind: string;
  title: string;
  currentIndex: number;
  variants: VariantRow[];
}

export function VariantPickerModal({
  messageIndex,
  onClose,
  onPicked,
}: {
  messageIndex: number;
  onClose: () => void;
  onPicked: () => void;
}) {
  const [payload, setPayload] = useState<Payload | null>(null);
  const [err, setErr] = useState('');
  const [expanded, setExpanded] = useState<number | null>(null);
  const [jump, setJump] = useState('1');

  useEffect(() => {
    let cancelled = false;
    api
      .get<Payload>(`/api/chat/variants?messageIndex=${messageIndex}`)
      .then((p) => {
        if (cancelled) return;
        setPayload(p);
        setJump(String((p.currentIndex ?? 0) + 1));
      })
      .catch(() => {
        if (!cancelled) setErr('Could not load variants.');
      });
    return () => {
      cancelled = true;
    };
  }, [messageIndex]);

  const pick = async (variantIndex: number) => {
    setErr('');
    try {
      await api.post('/api/chat/select-variant', { messageIndex, variantIndex });
    } catch (e) {
      setErr(describeActionFailure('switch to that version', e));
      return;
    }
    onPicked();
  };

  const go = (e: FormEvent) => {
    e.preventDefault();
    if (!payload || payload.variants.length === 0) return;
    const n = Number.parseInt(jump, 10);
    if (!Number.isFinite(n)) return;
    const last = payload.variants.length;
    const index = Math.min(last, Math.max(1, n)) - 1;
    void pick(index);
  };

  const copy = async (row: VariantRow) => {
    const body = (row.text || row.snippet || '').trim();
    if (!body) return;
    try {
      await navigator.clipboard.writeText(body);
    } catch {
      /* clipboard can be denied; the card still works */
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div
        className="modal variant-picker-modal"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="drawer-head">
          <span>{payload?.title ?? 'Select variant'}</span>
          <button className="link-btn" onClick={onClose} aria-label="Close">
            ×
          </button>
        </div>
        {err && <p className="muted small">{err}</p>}
        {!payload && !err && <p className="muted small">Loading…</p>}
        {payload && (
          <>
            <ul className="variant-picker-list" role="listbox">
              {payload.variants.map((v) => {
                const preview = v.text || v.snippet || '(empty)';
                const tokens = v.tokenCount ?? approxTokens(v.charCount);
                const open = expanded === v.index;
                return (
                  <li key={v.index}>
                    <div
                      className={`variant-card${v.current ? ' current' : ''}${open ? ' expanded' : ''}`}
                      role="option"
                      aria-selected={v.current}
                      onClick={() => void pick(v.index)}
                    >
                      <header className="variant-card-head">
                        <span className="variant-card-id">
                          #{v.index + 1}
                          {v.current && (
                            <span className="variant-current-mark">Current</span>
                          )}
                        </span>
                        <span className="variant-card-meta">
                          {v.label ?? variantKindLabel(v.kind ?? payload.kind)} · {v.charCount} characters · {tokens}t
                        </span>
                        <span
                          className="variant-card-tools"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <button
                            type="button"
                            className="icon-btn"
                            title={open ? 'Collapse' : 'Expand'}
                            onClick={() =>
                              setExpanded(open ? null : v.index)
                            }
                          >
                            {open ? '▴' : '▾'}
                          </button>
                          <button
                            type="button"
                            className="icon-btn"
                            title="Copy"
                            onClick={() => void copy(v)}
                          >
                            ⧉
                          </button>
                        </span>
                      </header>
                      <p className={`variant-card-preview${open ? ' open' : ''}`}>
                        {preview}
                      </p>
                    </div>
                  </li>
                );
              })}
            </ul>
            <form className="variant-jump" onSubmit={go}>
              <label htmlFor="variant-jump-field">
                {payload.kind === 'greet' ? 'Greet #' : 'Swipe #'}
              </label>
              <input
                id="variant-jump-field"
                type="number"
                min={1}
                max={payload.variants.length}
                value={jump}
                onChange={(e) => setJump(e.target.value)}
              />
              <button type="submit" className="variant-jump-go">
                Go
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
