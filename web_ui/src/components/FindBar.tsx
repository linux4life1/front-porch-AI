// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// ⌘F find-in-chat bar — desktop-parity overlay (docs/design/mockups/
// chat-find-bar.html): input, Aa / .* toggles, honest counter, prev/next,
// close. Counts come from the server scan; Enter / Shift+Enter step, Esc
// closes. Bad regex glows red and says "bad pattern"; a regex the server
// gave up on (timeout) says "too slow".

import { useEffect, useRef } from 'react';

export type FindBarProps = {
  value: string;
  onValue: (v: string) => void;
  regexOn: boolean;
  onToggleRegex: () => void;
  caseOn: boolean;
  onToggleCase: () => void;
  waiting: boolean;
  bad: boolean;
  slow?: boolean;
  counter: string;
  wildcardChip: boolean;
  onStep: (dir: number) => void;
  onClose: () => void;
};

export function FindBar(props: FindBarProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);
  // A click on a toggle or arrow must leave focus in the input: Enter on a
  // focused button would press it again (Aa flipped back off), and the
  // Enter / Esc handlers live on the input.
  const keepFocus = (e: { preventDefault(): void }) => e.preventDefault();
  const modeChip = props.regexOn && props.value.trim()
    ? '.* regex'
    : props.wildcardChip
      ? '✱ word wildcard'
      : null;
  return (
    <div className="find-bar" role="search">
      <div className="find-row">
        <input
          ref={inputRef}
          className={props.bad || props.slow ? 'find-input bad' : 'find-input'}
          type="text"
          placeholder={props.waiting ? 'Waiting for older history…' : 'Find in chat…'}
          value={props.value}
          spellCheck={false}
          autoComplete="off"
          onChange={(e) => props.onValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              props.onStep(e.shiftKey ? -1 : 1);
            } else if (e.key === 'Escape') {
              e.preventDefault();
              props.onClose();
            }
          }}
        />
        <button
          type="button"
          onMouseDown={keepFocus}
          className={props.caseOn ? 'find-toggle on' : 'find-toggle'}
          title="Match case"
          onClick={props.onToggleCase}
        >
          Aa
        </button>
        <button
          type="button"
          onMouseDown={keepFocus}
          className={props.regexOn ? 'find-toggle on' : 'find-toggle'}
          title="Regular expression"
          onClick={props.onToggleRegex}
        >
          .*
        </button>
        <span className={props.bad || props.slow || (props.counter === 'No matches' && props.value.trim()) ? 'find-count none' : 'find-count'}>
          {props.waiting ? <span className="find-spinner" aria-label="Loading" /> : props.slow ? 'too slow' : props.bad ? 'bad pattern' : props.value.trim() ? props.counter : ''}
        </span>
        <button
          type="button"
          onMouseDown={keepFocus}
          className="find-btn"
          title="Previous (⇧↵)"
          onClick={() => props.onStep(-1)}
        >
          ↑
        </button>
        <button
          type="button"
          onMouseDown={keepFocus}
          className="find-btn"
          title="Next (↵)"
          onClick={() => props.onStep(1)}
        >
          ↓
        </button>
        <button
          type="button"
          onMouseDown={keepFocus}
          className="find-btn"
          title="Close (Esc)"
          onClick={props.onClose}
        >
          ✕
        </button>
      </div>
      {(modeChip || props.waiting) && (
        <div className="find-subrow">
          {modeChip && <span className="find-chip">{modeChip}</span>}
          <span className="find-hint">↵ next · ⇧↵ prev · Esc close</span>
        </div>
      )}
    </div>
  );
}
