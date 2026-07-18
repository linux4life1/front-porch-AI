// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library toolbar (search / sort / scope / grid size / create / import / select)
// and the bulk-selection bar. Presentational — every action is a callback.

import type { MouseEvent } from 'react';
import type { SearchScope } from '../../hooks/useLibrary';

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
  onNewFolder,
  onCreate,
  onAiCreate,
  onNewGroup,
  onImportMenu,
  onStartSelect,
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
  onNewFolder: () => void;
  onCreate: () => void;
  onAiCreate: () => void;
  onNewGroup: () => void;
  onImportMenu: (e: MouseEvent) => void;
  onStartSelect: () => void;
}) {
  return (
    <div className="search-row">
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
      <button className="ghost import-btn" onClick={onNewFolder} title="New folder">
        📁＋
      </button>
      <button className="ghost import-btn" onClick={onStartSelect} title="Select multiple">
        ☑ Select
      </button>
      <button className="primary import-btn" onClick={onCreate} title="Create a new character">
        ＋ Create
      </button>
      <button className="ghost import-btn" onClick={onAiCreate} title="Generate a character with AI">
        ✨ AI Create
      </button>
      <button className="ghost import-btn" onClick={onNewGroup} title="Create a new group chat">
        👥 New Group
      </button>
      <button
        className="ghost import-btn"
        disabled={importing}
        onClick={onImportMenu}
        title="Import a character card"
      >
        {importing ? 'Importing…' : '⬆ Import ▾'}
      </button>
    </div>
  );
}

export function SelectionBar({
  count,
  onMove,
  onDelete,
  onCancel,
}: {
  count: number;
  onMove: () => void;
  onDelete: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="selection-bar">
      <span className="sel-count">{count} selected</span>
      <div className="sel-actions">
        <button className="ghost small" disabled={count === 0} onClick={onMove}>
          📁 Move to folder
        </button>
        <button className="danger-btn small" disabled={count === 0} onClick={onDelete}>
          🗑 Delete
        </button>
        <button className="ghost small" onClick={onCancel}>
          Cancel
        </button>
      </div>
    </div>
  );
}
