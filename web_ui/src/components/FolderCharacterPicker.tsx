// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The ONE folder-aware character browser for "pick characters" surfaces — the
// web twin of lib/ui/widgets/folder_character_picker.dart. First consumer is
// CreateGroupChatPage's Members step; any future pick surface should reuse
// this component rather than growing its own flat grid.
//
// Same rules as the desktop picker (and the home grid): browsing shows
// subfolder tiles + the characters directly at the current level ('' folderId
// = root); folders with no eligible characters anywhere below are hidden;
// searching hides folders and matches ALL eligible characters by name so
// nothing nested is unfindable.

import { useMemo, useState } from 'react';
import { api } from '../api/client';

export interface PickerChar {
  id: string;
  name: string;
  hasAvatar: boolean;
  /** Only the flat no-portrait colour (from /api/characters); draw the initial. */
  placeholderPortrait?: boolean;
  avatarVersion?: number;
  /** Owning folder id, '' at the root. */
  folderId: string;
}

export interface PickerFolder {
  id: string;
  name: string;
  parentId?: string;
}

export function FolderCharacterPicker({
  chars,
  folders,
  selected,
  onToggle,
}: {
  /** Eligible candidates only — the caller excludes anyone not pickable. */
  chars: PickerChar[];
  folders: PickerFolder[];
  selected: string[];
  onToggle: (id: string) => void;
}) {
  const [search, setSearch] = useState('');
  const [folderId, setFolderId] = useState<string | null>(null);
  const searching = search.trim().length > 0;

  // folder id -> eligible character count anywhere below it (drives the tile
  // badge and hides folders with nothing to pick).
  const eligibleCounts = useMemo(() => {
    const parentOf = new Map(folders.map((f) => [f.id, f.parentId ?? null]));
    const counts = new Map<string, number>();
    for (const c of chars) {
      let cur: string | null = c.folderId || null;
      // Walk up the ancestor chain so nested characters count for every level.
      while (cur) {
        counts.set(cur, (counts.get(cur) ?? 0) + 1);
        cur = parentOf.get(cur) ?? null;
      }
    }
    return counts;
  }, [chars, folders]);

  const subfolders = useMemo(
    () =>
      folders
        .filter((f) => (f.parentId ?? null) === folderId)
        .filter((f) => (eligibleCounts.get(f.id) ?? 0) > 0)
        .sort((a, b) => a.name.localeCompare(b.name)),
    [folders, folderId, eligibleCounts],
  );

  const visibleChars = useMemo(() => {
    let list: PickerChar[];
    if (searching) {
      const q = search.trim().toLowerCase();
      list = chars.filter((c) => c.name.toLowerCase().includes(q));
    } else {
      list = chars.filter((c) => (c.folderId || null) === folderId);
    }
    return [...list].sort((a, b) => a.name.localeCompare(b.name));
  }, [chars, searching, search, folderId]);

  const folderName = folders.find((f) => f.id === folderId)?.name;
  const parentId = folders.find((f) => f.id === folderId)?.parentId ?? null;

  return (
    <>
      <input
        className="grp-search"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Search characters…"
      />
      {!searching && folderId !== null && (
        <div className="picker-crumb">
          <button type="button" className="link-btn" onClick={() => setFolderId(parentId)}>
            ← Back
          </button>
          <span className="picker-crumb-name">📁 {folderName ?? 'Folder'}</span>
        </div>
      )}
      <div className="grp-grid">
        {!searching &&
          subfolders.map((f) => (
            <button
              type="button"
              key={f.id}
              className="grp-card picker-folder"
              onClick={() => setFolderId(f.id)}
            >
              <span className="grp-initial">📁</span>
              <span className="grp-name">
                {f.name} ({eligibleCounts.get(f.id) ?? 0})
              </span>
            </button>
          ))}
        {visibleChars.map((c) => (
          <button
            type="button"
            key={c.id}
            className={`grp-card${selected.includes(c.id) ? ' on' : ''}`}
            onClick={() => onToggle(c.id)}
          >
            {c.hasAvatar && !c.placeholderPortrait ? (
              <img
                src={api.avatarUrl(`/api/characters/${c.id}/avatar`, 256, c.avatarVersion)}
                alt={c.name}
                loading="lazy"
              />
            ) : (
              <span className="grp-initial">{c.name.charAt(0).toUpperCase()}</span>
            )}
            <span className="grp-name">{c.name}</span>
            {selected.includes(c.id) && <span className="grp-check">✓</span>}
          </button>
        ))}
      </div>
      {subfolders.length === 0 && visibleChars.length === 0 && (
        <p className="muted small">
          {searching ? `No characters match “${search.trim()}”.` : 'Nothing here.'}
        </p>
      )}
    </>
  );
}
