// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library toolbar (search / sort / scope / grid size / create / import / select)
// and the bulk-selection bar. Presentational — every action is a callback.

import type { MouseEvent } from 'react';
import type { SearchScope } from '../../hooks/useLibrary';
import { HomeModeToggle } from '../HomeModeToggle';

export function LibraryToolbar({
  search,
  setSearch,
  sort,
  setSort,
  scope,
  setScope,
  searching,
  gridMin,
  setGridMin,
  importing,
  inFolder,
  onRefresh,
  onNewFolder,
  onImportMenu,
  onStartSelect,
  onStartOrganize,
}: {
  search: string;
  setSearch: (v: string) => void;
  sort: string;
  setSort: (v: string) => void;
  scope: SearchScope;
  setScope: (v: SearchScope) => void;
  searching: boolean;
  gridMin: number;
  setGridMin: (v: number) => void;
  importing: boolean;
  /** Inside a folder the button makes a subfolder. */
  inFolder: boolean;
  onRefresh: () => void;
  onNewFolder: () => void;
  onImportMenu: (e: MouseEvent) => void;
  onStartSelect: () => void;
  onStartOrganize: () => void;
}) {
  return (
    <div className="search-row">
      <HomeModeToggle mode="chats" />
      <input
        className="search"
        placeholder="Search characters…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      <select
        className="sort-select"
        value={sort}
        onChange={(e) => setSort(e.target.value)}
        aria-label="Sort characters"
      >
        <option value="name">Name</option>
        <option value="recent">Recent</option>
        <option value="messages">Most messages</option>
        <option value="importDate">Import date</option>
      </select>
      {searching && (
        <select
          className="sort-select"
          value={scope}
          onChange={(e) => setScope(e.target.value as SearchScope)}
          aria-label="Search scope"
          title="Where to search"
        >
          <option value="currentFolder">This folder</option>
          <option value="folderRecursive">+ Subfolders</option>
          <option value="allCharacters">Everywhere</option>
        </select>
      )}
      <label className="grid-size" title="Card size">
        <span aria-hidden>🔍</span>
        <input
          type="range"
          min={110}
          max={320}
          step={10}
          value={gridMin}
          onChange={(e) => setGridMin(Number(e.target.value))}
          aria-label="Card size"
        />
      </label>
      <button
        className="ghost import-btn"
        onClick={onRefresh}
        title="Refresh character list (pick up external changes, e.g. Character Card Forge)"
      >
        ⟳
      </button>
      <button
        className="ghost import-btn"
        onClick={onStartSelect}
        title="Multi-select characters (for organizing, moving, etc.)"
      >
        ☑
      </button>
      <button className="ghost import-btn" onClick={onStartOrganize} title="Organize into folders">
        📂
      </button>
      <button
        className="ghost import-btn"
        onClick={onNewFolder}
        title={inFolder ? 'New Subfolder' : 'New Folder'}
      >
        📁＋
      </button>
      <button
        className="ghost import-btn"
        disabled={importing}
        onClick={onImportMenu}
        title="Import or discover characters"
      >
        {importing ? 'Importing…' : '⬆ Import ▾'}
      </button>
    </div>
  );
}

export function SelectionBar({
  count,
  organizing = false,
  onSelectAll,
  onSelectNone,
  onMove,
  onExport,
  exporting = false,
  onDelete,
  onCancel,
}: {
  count: number;
  organizing?: boolean;
  onSelectAll: () => void;
  onSelectNone: () => void;
  onMove: () => void;
  /** Save the selection as a .porch (one) or .porchpack (two or more). */
  onExport?: () => void;
  exporting?: boolean;
  onDelete: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="selection-bar">
      <button className="icon-btn" title="Cancel selection" aria-label="Cancel selection" onClick={onCancel}>
        ✕
      </button>
      <span className="sel-count" data-organizing={organizing || undefined}>
        {count} selected
      </span>
      <button className="link-btn" onClick={onSelectAll}>
        Select all
      </button>
      <button className="link-btn" disabled={count === 0} onClick={onSelectNone}>
        Select none
      </button>
      <div className="sel-actions">
        <button className="ghost small" disabled={count === 0} onClick={onMove}>
          📁 Move to folder
        </button>
        {onExport && (
          <button className="ghost small" disabled={count === 0 || exporting} onClick={onExport}>
            {exporting ? 'Exporting…' : '⬇ Export'}
          </button>
        )}
        <button className="danger-btn small" disabled={count === 0} onClick={onDelete}>
          🗑 Delete
        </button>
      </div>
    </div>
  );
}
