// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Small, related modal dialogs for the library: a text prompt (create/rename
// folder), a confirm (delete), and a folder picker (move). They share the
// existing `drawer-backdrop center` + `modal` styling so there's no new modal
// shell.

import { useMemo, useState } from 'react';
import type { LibFolder } from '../../hooks/useLibrary';

export function PromptDialog({
  title,
  initial,
  confirmLabel,
  onConfirm,
  onClose,
}: {
  title: string;
  initial?: string;
  confirmLabel: string;
  onConfirm: (value: string) => void;
  onClose: () => void;
}) {
  const [value, setValue] = useState(initial ?? '');
  const submit = () => {
    const v = value.trim();
    if (!v) return;
    onConfirm(v);
    onClose();
  };
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>{title}</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <input
          className="search"
          autoFocus
          value={value}
          maxLength={100}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit();
          }}
        />
        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" disabled={!value.trim()} onClick={submit}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

export function ConfirmDialog({
  title,
  message,
  confirmLabel,
  danger,
  onConfirm,
  onClose,
}: {
  title: string;
  message: string;
  confirmLabel: string;
  danger?: boolean;
  onConfirm: () => void;
  onClose: () => void;
}) {
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>{title}</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="muted dialog-msg">{message}</p>
        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button
            className={danger ? 'danger-btn' : 'primary'}
            onClick={() => {
              onConfirm();
              onClose();
            }}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * The severe "type DELETE to confirm" gate for mass-destructive actions (bulk
 * character delete, delete-folder-with-characters) — web mirror of the desktop
 * TypeDeleteDialog. A plain confirm is too easy to click through when the blast
 * radius is 100+ characters and their chat histories, so the delete button
 * stays disabled until the keyword is typed exactly.
 */
export function TypeConfirmDialog({
  title,
  message,
  confirmLabel,
  keyword = 'DELETE',
  onConfirm,
  onClose,
}: {
  title: string;
  message: string;
  confirmLabel: string;
  keyword?: string;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const [typed, setTyped] = useState('');
  const matches = typed.trim() === keyword;
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal danger-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>⚠️ {title}</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="muted dialog-msg">{message}</p>
        <label className="type-confirm-label">
          Type {keyword} to confirm:
          <input
            className="search"
            autoFocus
            value={typed}
            placeholder={keyword}
            onChange={(e) => setTyped(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && matches) {
                onConfirm();
                onClose();
              }
            }}
          />
        </label>
        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button
            className="danger-btn"
            disabled={!matches}
            onClick={() => {
              onConfirm();
              onClose();
            }}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

interface FolderRow {
  folder: LibFolder;
  depth: number;
}

/** Move picker: a flat, depth-indented folder list plus a "No folder (root)"
 *  target. [excludeId] hides a folder from being moved into itself. */
export function MoveToFolderDialog({
  folders,
  onPick,
  onClose,
}: {
  folders: LibFolder[];
  onPick: (folderId: string | null) => void;
  onClose: () => void;
}) {
  const rows = useMemo<FolderRow[]>(() => {
    const byParent = new Map<string | null, LibFolder[]>();
    for (const f of folders) {
      const key = f.parentId ?? null;
      const list = byParent.get(key) ?? [];
      list.push(f);
      byParent.set(key, list);
    }
    for (const list of byParent.values()) {
      list.sort((a, b) => a.name.localeCompare(b.name));
    }
    const out: FolderRow[] = [];
    const walk = (parent: string | null, depth: number) => {
      for (const folder of byParent.get(parent) ?? []) {
        out.push({ folder, depth });
        walk(folder.id, depth + 1);
      }
    };
    walk(null, 0);
    return out;
  }, [folders]);

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Move to folder</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <div className="move-list">
          <button className="move-row" onClick={() => onPick(null)}>
            <span aria-hidden>🏠</span> No folder (root)
          </button>
          {rows.map(({ folder, depth }) => (
            <button
              key={folder.id}
              className="move-row"
              style={{ paddingLeft: 12 + depth * 16 }}
              onClick={() => onPick(folder.id)}
            >
              <span aria-hidden>📁</span> {folder.name}
            </button>
          ))}
          {rows.length === 0 && <p className="muted dialog-msg">No folders yet. Create one first.</p>}
        </div>
      </div>
    </div>
  );
}
