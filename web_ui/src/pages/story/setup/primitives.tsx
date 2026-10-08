// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The small studio pieces the shelf and New Story share: chips, segmented
// control, toggle and radio rows, avatar, menu and dialog. Web twins of
// lib/ui/story_studio/studio_widgets.dart + studio_cards.dart; every look
// comes from studio.css (.s-chip, .s-seg, .s-tog, .s-menu, .s-dialog …).

import { useEffect, useRef, useState, type ReactNode } from 'react';

/** True under the studio's phone breakpoint (same 760px as studio.css). */
export function useNarrow(): boolean {
  const query = '(max-width: 760px)';
  const [narrow, setNarrow] = useState(() => typeof window !== 'undefined' && window.matchMedia(query).matches);
  useEffect(() => {
    const mq = window.matchMedia(query);
    const on = () => setNarrow(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  return narrow;
}

/** A plain or accent chip (tone: amber, honey, teal, bad, terra). */
export function Chip({ tone = '', children }: { tone?: string; children: ReactNode }) {
  return <span className={`s-chip ${tone}`.trim()}>{children}</span>;
}

/** A tappable chip; `on` is the amber-filled selection. */
export function PickChip({ on, onClick, children, testid }: {
  on: boolean; onClick: () => void; children: ReactNode; testid?: string;
}) {
  return (
    <button type="button" className={`s-chip pick${on ? ' on' : ''}`} aria-pressed={on}
      data-testid={testid} onClick={onClick}>{children}</button>
  );
}

/** A row of pick chips: single choice, or any number when `multi`. */
export function ChipRow({ options, selected, onToggle, testid }: {
  options: Record<string, string>;
  selected: string[];
  onToggle: (value: string, on: boolean) => void;
  testid?: string;
}) {
  return (
    <div className="s-chips" data-testid={testid}>
      {Object.entries(options).map(([value, label]) => {
        const on = selected.includes(value);
        return <PickChip key={value} on={on} onClick={() => onToggle(value, !on)}>{label}</PickChip>;
      })}
    </div>
  );
}

export function Segmented({ options, selected, onSelect, testid }: {
  options: Record<string, string>;
  selected: string;
  onSelect: (value: string) => void;
  testid?: string;
}) {
  return (
    <div className="s-seg" role="group" data-testid={testid}>
      {Object.entries(options).map(([value, label]) => (
        <button key={value} type="button" className={selected === value ? 'on' : ''}
          aria-pressed={selected === value} onClick={() => onSelect(value)}>{label}</button>
      ))}
    </div>
  );
}

/** Switch + label (+ muted detail underneath). Without `onChange` it is inert and the tap passes to the card. */
export function ToggleRow({ on, onChange, label, detail, testid }: {
  on: boolean; onChange?: (on: boolean) => void; label: string; detail?: string; testid?: string;
}) {
  return (
    <label className={`s-tog-row${onChange ? '' : ' inert'}`} data-testid={testid}>
      <span className={`s-tog${on ? ' on' : ''}`}>
        <input type="checkbox" checked={on} readOnly={!onChange} tabIndex={onChange ? 0 : -1}
          onChange={onChange ? (e) => onChange(e.target.checked) : undefined} />
      </span>
      <span className="s-grow">{label}{detail && <span className="d">{detail}</span>}</span>
    </label>
  );
}

export function RadioRow({ selected, onSelect, title, detail, testid }: {
  selected: boolean; onSelect: () => void; title: string; detail?: string; testid?: string;
}) {
  return (
    <label className="s-radio-row" data-testid={testid}>
      <input type="radio" checked={selected} onChange={onSelect} />
      <span className={`s-radio${selected ? ' on' : ''}`} />
      <span className="s-grow"><b>{title}</b>{detail && <span className="d">{detail}</span>}</span>
    </label>
  );
}

export function KeyLabel({ children }: { children: ReactNode }) {
  return <span className="s-key">{children}</span>;
}

/** A labelled block inside a step card: key label (+ faint hint), then the control. */
export function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="s-col" style={{ gap: 6 }}>
      <span className="s-row" style={{ gap: 6 }}>
        <KeyLabel>{label}</KeyLabel>
        {hint && <span className="s-faint" style={{ fontSize: 11 }}>{hint}</span>}
      </span>
      {children}
    </div>
  );
}

/** Muted one-line explanation under a control. */
export function Note({ children }: { children: ReactNode }) {
  return <span className="s-muted s-small">{children}</span>;
}

/** The pick field: looks like a field, ends with ▾, opens a sheet. */
export function PickField({ value, placeholder, onClick, testid }: {
  value: string; placeholder?: string; onClick: () => void; testid?: string;
}) {
  return (
    <button type="button" className={`s-field s-pick${value ? '' : ' empty'}`} data-testid={testid} onClick={onClick}>
      <span>{value || placeholder || ''}</span>
    </button>
  );
}

export function initials(name: string): string {
  return name.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
}

/** Portrait (when there is one) or the honey initials on the portrait gradient. */
export function Avatar({ name, src, large }: { name: string; src?: string; large?: boolean }) {
  const [broken, setBroken] = useState<string | null>(null);
  return (
    <span className={`s-avatar${large ? ' lg' : ''}`} aria-hidden="true">
      {src && src !== broken ? <img src={src} alt="" onError={() => setBroken(src)} /> : initials(name)}
    </span>
  );
}

const openDialogs: object[] = [];

/** A warm dialog: card fill, 15/700 title, body, actions. Esc or a tap outside closes it. */
export function Dialog({ title, onClose, actions, children, sheet, wide, testid }: {
  title: string;
  onClose: () => void;
  actions?: ReactNode;
  children?: ReactNode;
  /** The model-picker sheet: 480px, with a ✕ in the corner. */
  sheet?: boolean;
  /** A list dialog (cast, chats, models): 460px instead of 380px. */
  wide?: boolean;
  testid?: string;
}) {
  const token = useRef({});
  useEffect(() => {
    const me = token.current;
    openDialogs.push(me);
    const onKey = (e: KeyboardEvent) => {
      // Only the topmost dialog answers Esc (a picker opens over the sheet).
      if (e.key !== 'Escape' || openDialogs[openDialogs.length - 1] !== me) return;
      e.stopPropagation();
      onClose();
    };
    document.addEventListener('keydown', onKey, true);
    return () => {
      document.removeEventListener('keydown', onKey, true);
      openDialogs.splice(openDialogs.indexOf(me), 1);
    };
  }, [onClose]);
  return (
    <div className="s-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className={sheet ? 's-sheet' : `s-dialog${wide ? ' wide' : ''}`} role="dialog" aria-modal="true" aria-label={title} data-testid={testid}>
        <div className="s-row nowrap">
          <span className="t s-grow">{title}</span>
          {sheet && <button type="button" className="s-btn-ico ghost" aria-label="Close" onClick={onClose}>✕</button>}
        </div>
        {children}
        {actions && <div className="actions">{actions}</div>}
      </div>
    </div>
  );
}

/** Confirm with what will be lost; destructive confirms use the danger button. */
export function ConfirmDialog({ title, body, confirmLabel, destructive, onConfirm, onCancel }: {
  title: string; body: string; confirmLabel: string; destructive?: boolean;
  onConfirm: () => void; onCancel: () => void;
}) {
  return (
    <Dialog title={title} onClose={onCancel} actions={(
      <>
        <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
        <button type="button" className={destructive ? 's-btn-danger' : 's-btn-primary'} data-testid="story-confirm" onClick={onConfirm}>
          {confirmLabel}
        </button>
      </>
    )}>
      <div className="body">{body}</div>
    </Dialog>
  );
}

export interface MenuEntry {
  label: string;
  onSelect: () => void;
  disabled?: boolean;
  danger?: boolean;
  /** A hairline above this entry. */
  divider?: boolean;
}

/** The ⋯ button and its menu. Taps stay inside it, so a card around it does not open. */
export function MenuButton({ entries, label = 'More', testid }: { entries: MenuEntry[]; label?: string; testid?: string }) {
  const [open, setOpen] = useState(false);
  const wrap = useRef<HTMLSpanElement | null>(null);
  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => { if (!wrap.current?.contains(e.target as Node)) setOpen(false); };
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', away);
    document.addEventListener('keydown', key);
    return () => {
      document.removeEventListener('mousedown', away);
      document.removeEventListener('keydown', key);
    };
  }, [open]);
  return (
    <span className="s-menu-wrap" ref={wrap} onClick={(e) => e.stopPropagation()}>
      <button type="button" className="s-btn-ico ghost" aria-label={label} aria-haspopup="menu" aria-expanded={open}
        data-testid={testid} onClick={() => setOpen(!open)}>⋯</button>
      {open && (
        <div className="s-menu" role="menu">
          {entries.map((e) => (
            <div key={e.label} style={{ display: 'contents' }}>
              {e.divider && <hr />}
              <button type="button" role="menuitem" className={e.danger ? 'danger' : ''} disabled={e.disabled}
                onClick={() => { setOpen(false); e.onSelect(); }}>{e.label}</button>
            </div>
          ))}
        </div>
      )}
    </span>
  );
}
