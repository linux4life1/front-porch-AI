// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stop sequence list editor and reorderable output sanitizer rule editor.

import { useState, type DragEvent } from 'react';

export interface SanitizerRule {
  id: number;
  find: string;
  replace: string;
  stop_after_match?: boolean;
}

function AddCircleIcon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm5 11h-4v4h-2v-4H7v-2h4V7h2v4h4v2z" />
    </svg>
  );
}

function RemoveCircleIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="10" />
      <line x1="15" y1="9" x2="9" y2="15" />
      <line x1="9" y1="9" x2="15" y2="15" />
    </svg>
  );
}

function moveItem<T>(items: T[], fromIdx: number, toIdx: number): T[] {
  if (fromIdx === toIdx || fromIdx < 0 || toIdx < 0 || fromIdx >= items.length || toIdx >= items.length) {
    return items;
  }
  const next = [...items];
  const [moved] = next.splice(fromIdx, 1);
  next.splice(toIdx, 0, moved);
  return next;
}

export function StringListEditor({
  title,
  hint,
  values,
  onChange,
  placeholder,
}: {
  title: string;
  hint: string;
  values: string[];
  onChange: (next: string[]) => void;
  placeholder: string;
}) {
  const [newVal, setNewVal] = useState('');

  const handleAdd = () => {
    if (newVal.length > 0 && !values.includes(newVal)) {
      onChange([...values, newVal]);
      setNewVal('');
    }
  };

  const handleItemChange = (idx: number, text: string) => {
    const next = [...values];
    next[idx] = text;
    onChange(next);
  };

  return (
    <div className="stop-sequence-editor" style={{ marginTop: 16 }}>
      <h4 style={{ margin: '0 0 4px' }}>{title}</h4>
      <p className="muted small" style={{ marginBottom: 8 }}>{hint}</p>

      <div className="stop-sequence-box">
        <div className="stop-sequence-input-row">
          <input
            className="stop-sequence-input"
            value={newVal}
            placeholder={placeholder}
            onChange={(e) => setNewVal(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                handleAdd();
              }
            }}
          />
          <button
            type="button"
            className="icon-btn stop-sequence-add-btn"
            title="Add sequence"
            onClick={handleAdd}
          >
            <AddCircleIcon size={20} />
          </button>
        </div>

        {values.length > 0 && (
          <div className="stop-sequence-list">
            {values.map((s, i) => (
              <div key={i} className="stop-sequence-item">
                <input
                  className="stop-sequence-inline-input"
                  value={s}
                  placeholder={placeholder}
                  onChange={(e) => handleItemChange(i, e.target.value)}
                />
                <button
                  type="button"
                  className="icon-btn circle-remove-btn"
                  title="Remove stop sequence"
                  onClick={() => onChange(values.filter((_, idx) => idx !== i))}
                >
                  <RemoveCircleIcon />
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export function SanitizerRulesEditor({
  rules,
  onChange,
}: {
  rules: SanitizerRule[];
  onChange: (rules: SanitizerRule[]) => void;
}) {
  const [findInput, setFindInput] = useState('');
  const [replaceInput, setReplaceInput] = useState('');
  const [duplicateWarning, setDuplicateWarning] = useState(false);
  const [draggedIdx, setDraggedIdx] = useState<number | null>(null);
  const [dragOverIdx, setDragOverIdx] = useState<number | null>(null);

  const nextId = () => rules.reduce((m, r) => Math.max(m, r.id), -1) + 1;

  const handleAdd = () => {
    if (!findInput) return;
    if (rules.some((r) => r.find === findInput && r.replace === replaceInput)) {
      setDuplicateWarning(true);
      return;
    }
    setDuplicateWarning(false);
    onChange([
      ...rules,
      {
        id: nextId(),
        find: findInput,
        replace: replaceInput,
        stop_after_match: false,
      },
    ]);
    setFindInput('');
    setReplaceInput('');
  };

  const handleToggleStop = (idx: number) => {
    onChange(
      rules.map((r, i) =>
        i === idx ? { ...r, stop_after_match: !r.stop_after_match } : r,
      ),
    );
  };

  const handleRuleChange = (idx: number, patch: Partial<SanitizerRule>) => {
    onChange(rules.map((r, i) => (i === idx ? { ...r, ...patch } : r)));
  };

  const handleMove = (idx: number, delta: number) => {
    const next = moveItem(rules, idx, idx + delta);
    if (next !== rules) onChange(next);
  };

  const handleDragStart = (e: DragEvent, idx: number) => {
    if (e.target instanceof HTMLElement && e.target.closest('input, button')) {
      e.preventDefault();
      return;
    }
    setDraggedIdx(idx);
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', String(idx));
  };

  const handleDragOver = (e: DragEvent, idx: number) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (dragOverIdx !== idx) setDragOverIdx(idx);
  };

  const handleDrop = (e: DragEvent, targetIdx: number) => {
    e.preventDefault();
    if (draggedIdx !== null && draggedIdx !== targetIdx) {
      onChange(moveItem(rules, draggedIdx, targetIdx));
    }
    setDraggedIdx(null);
    setDragOverIdx(null);
  };

  const clearDrag = () => {
    setDraggedIdx(null);
    setDragOverIdx(null);
  };

  return (
    <div className="sanitizer-rule-editor" style={{ marginTop: 12 }}>
      <div className="sanitizer-box">
        <div className="sanitizer-input-row">
          <input
            className="sanitizer-find-input"
            placeholder="Find..."
            value={findInput}
            onChange={(e) => {
              if (duplicateWarning) setDuplicateWarning(false);
              setFindInput(e.target.value);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleAdd();
            }}
          />
          <div className="sanitizer-input-divider" />
          <input
            className="sanitizer-replace-input"
            placeholder="Replace with..."
            value={replaceInput}
            onChange={(e) => {
              if (duplicateWarning) setDuplicateWarning(false);
              setReplaceInput(e.target.value);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleAdd();
            }}
          />
          <button
            type="button"
            className="icon-btn sanitizer-add-btn"
            title="Add replacement rule"
            onClick={handleAdd}
          >
            <AddCircleIcon size={22} />
          </button>
        </div>
        {duplicateWarning && (
          <p className="sanitizer-warn-text">Rule already exists</p>
        )}

        <div className="sanitizer-rules-list">
          {rules.length === 0 ? (
            <div className="sanitizer-empty">No rules configured</div>
          ) : (
            rules.map((rule, idx) => {
              const isDragging = draggedIdx === idx;
              const isDragOver = dragOverIdx === idx;
              return (
                <div
                  key={rule.id}
                  className={`sanitizer-rule-row${isDragging ? ' dragging' : ''}${isDragOver ? ' drag-over' : ''}`}
                  draggable
                  onDragStart={(e) => handleDragStart(e, idx)}
                  onDragOver={(e) => handleDragOver(e, idx)}
                  onDragLeave={() => {
                    if (dragOverIdx === idx) setDragOverIdx(null);
                  }}
                  onDrop={(e) => handleDrop(e, idx)}
                  onDragEnd={clearDrag}
                >
                  <span className="sanitizer-drag-handle" title="Drag to reorder">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                      <line x1="4" y1="9" x2="20" y2="9" />
                      <line x1="4" y1="15" x2="20" y2="15" />
                    </svg>
                  </span>

                  <button
                    type="button"
                    className="reorder-btn"
                    title="Move up"
                    disabled={idx === 0}
                    onClick={() => handleMove(idx, -1)}
                    aria-label="Move rule up"
                  >
                    ▲
                  </button>
                  <button
                    type="button"
                    className="reorder-btn"
                    title="Move down"
                    disabled={idx === rules.length - 1}
                    onClick={() => handleMove(idx, 1)}
                    aria-label="Move rule down"
                  >
                    ▼
                  </button>

                  <button
                    type="button"
                    className={`icon-btn stop-circle-btn${rule.stop_after_match ? ' on' : ''}`}
                    title={rule.stop_after_match ? 'Stop after match (on)' : 'Stop after match (off)'}
                    onClick={() => handleToggleStop(idx)}
                  >
                    <svg width="18" height="18" viewBox="0 0 24 24" fill={rule.stop_after_match ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" aria-hidden="true">
                      <circle cx="12" cy="12" r="10" />
                      <rect x="9" y="9" width="6" height="6" fill={rule.stop_after_match ? 'var(--card)' : 'currentColor'} />
                    </svg>
                  </button>

                  <div className="sanitizer-rule-inputs">
                    <input
                      className="sanitizer-inline-input"
                      value={rule.find}
                      placeholder="Find"
                      onChange={(e) => handleRuleChange(idx, { find: e.target.value })}
                    />
                    <span className="muted" style={{ margin: '0 4px' }}>→</span>
                    <input
                      className="sanitizer-inline-input"
                      value={rule.replace}
                      placeholder="Replace"
                      onChange={(e) => handleRuleChange(idx, { replace: e.target.value })}
                    />
                  </div>

                  <button
                    type="button"
                    className="icon-btn circle-remove-btn"
                    title="Remove rule"
                    onClick={() => onChange(rules.filter((_, i) => i !== idx))}
                  >
                    <RemoveCircleIcon />
                  </button>
                </div>
              );
            })
          )}
        </div>

        <div className="sanitizer-summary">
          <span>{rules.length === 0 ? 'No rules configured' : `${rules.length} rule${rules.length === 1 ? '' : 's'}`}</span>
          {rules.length > 0 && <span className="muted">Rules execute in top-to-bottom order</span>}
        </div>
      </div>
    </div>
  );
}
