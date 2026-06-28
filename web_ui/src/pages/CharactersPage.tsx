// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character library: folders, groups, and characters with full desktop parity
// (create/rename/delete folders, per-card menu with edit/duplicate/export/
// move/remove/delete, multi-select bulk move + delete, drag-and-drop into
// folders, folder-scoped search, import cards/folder + online browsers, grid
// size + import-date sort, and group export/extract). The page is a thin shell;
// data + actions live in useLibrary and the library/* components.

import { useEffect, useRef, useState, type CSSProperties, type MouseEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { InstallHint } from '../components/InstallHint';
import { useLayout } from '../hooks/useBreakpoint';
import { useLibrary, type LibChar, type LibFolder, type LibGroup } from '../hooks/useLibrary';
import { CardMenu, type CardMenuItem, type MenuState } from '../components/library/CardMenu';
import { CharacterCard, FolderCard, GroupCard } from '../components/library/LibraryCards';
import { LibraryToolbar, SelectionBar } from '../components/library/LibraryToolbar';
import {
  ConfirmDialog,
  MoveToFolderDialog,
  PromptDialog,
} from '../components/library/LibraryDialogs';

type Dialog =
  | { kind: 'newFolder' }
  | { kind: 'renameFolder'; folder: LibFolder }
  | { kind: 'deleteFolder'; folder: LibFolder }
  | { kind: 'deleteChar'; char: LibChar }
  | { kind: 'deleteGroup'; group: LibGroup }
  | { kind: 'deleteSelected'; ids: string[] }
  | { kind: 'extractGroup'; group: LibGroup }
  | { kind: 'move'; ids: string[] }
  | null;

export function CharactersPage() {
  const lib = useLibrary();
  const navigate = useNavigate();
  const { wide } = useLayout();
  const [menu, setMenu] = useState<MenuState | null>(null);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const folderInputRef = useRef<HTMLInputElement>(null);

  // `webkitdirectory` (whole-folder import) isn't a typed JSX attribute, so set
  // it on the element directly once it mounts.
  useEffect(() => {
    const el = folderInputRef.current;
    if (el) {
      el.setAttribute('webkitdirectory', '');
      el.setAttribute('directory', '');
    }
  }, []);

  const openMenu = (e: MouseEvent, items: CardMenuItem[]) =>
    setMenu({ x: e.clientX, y: e.clientY, items });

  // ── Menu item builders (one CardMenu serves every surface) ───────────────
  const charMenu = (c: LibChar): CardMenuItem[] => [
    { label: 'Edit', icon: '✏️', onClick: () => lib.editCharacter(c.id) },
    { label: 'Duplicate', icon: '⧉', onClick: () => lib.duplicateCharacter(c.id) },
    { label: 'Export PNG', icon: '🖼', onClick: () => lib.exportPng(c.id) },
    { label: 'Export JSON', icon: '📄', onClick: () => lib.exportJson(c.id) },
    { label: 'Move to folder…', icon: '📁', onClick: () => setDialog({ kind: 'move', ids: [c.id] }) },
    ...(lib.folderId
      ? [
          {
            label: 'Remove from folder',
            icon: '📤',
            onClick: () => lib.moveToFolder([c.id], null),
          },
        ]
      : []),
    { label: 'Delete', icon: '🗑', danger: true, onClick: () => setDialog({ kind: 'deleteChar', char: c }) },
  ];

  const folderMenu = (f: LibFolder): CardMenuItem[] => [
    { label: 'Rename', icon: '✏️', onClick: () => setDialog({ kind: 'renameFolder', folder: f }) },
    { label: 'Delete', icon: '🗑', danger: true, onClick: () => setDialog({ kind: 'deleteFolder', folder: f }) },
  ];

  const groupMenu = (g: LibGroup): CardMenuItem[] => [
    { label: 'Export Group PNG', icon: '🖼', onClick: () => lib.exportGroupPng(g) },
    { label: 'Extract characters', icon: '👥', onClick: () => setDialog({ kind: 'extractGroup', group: g }) },
    { label: 'Delete', icon: '🗑', danger: true, onClick: () => setDialog({ kind: 'deleteGroup', group: g }) },
  ];

  const importMenu = (): CardMenuItem[] => [
    { label: 'Import cards…', icon: '🖼', onClick: () => fileRef.current?.click() },
    { label: 'Import a folder…', icon: '📁', onClick: () => folderInputRef.current?.click() },
    {
      label: 'Browse AI Character Cards ↗',
      icon: '🌐',
      onClick: () => window.open('https://aicharactercards.com/', '_blank', 'noopener'),
    },
    {
      label: 'Browse Chub.ai ↗',
      icon: '🌐',
      onClick: () => window.open('https://chub.ai/', '_blank', 'noopener'),
    },
  ];

  // ── Drag-and-drop (desktop/tablet only; phone uses the menu's Move action) ─
  const dropOnFolder = (folderId: string | null) => {
    if (draggedId) lib.moveToFolder([draggedId], folderId);
    setDraggedId(null);
  };

  const gridStyle = { ['--lib-card-min']: `${lib.gridMin}px` } as CSSProperties;
  const showGroups = !lib.searching && lib.folderId === null && lib.groups.length > 0;
  const showSubfolders = !lib.searching && lib.subfolders.length > 0;

  return (
    <div className="page library">
      <InstallHint />
      <LibraryToolbar
        search={lib.search}
        setSearch={lib.setSearch}
        sort={lib.sort}
        setSort={lib.setSort}
        scope={lib.scope}
        setScope={lib.setScope}
        searching={lib.searching}
        gridMin={lib.gridMin}
        setGridMin={lib.setGridMin}
        importing={lib.importing}
        onNewFolder={() => setDialog({ kind: 'newFolder' })}
        onCreate={() => navigate('/create')}
        onAiCreate={() => navigate('/create-ai')}
        onNewGroup={() => navigate('/create-group')}
        onImportMenu={(e) => openMenu(e, importMenu())}
        onStartSelect={lib.startSelecting}
      />
      {/* Hidden import inputs (cards + whole folder). */}
      <input
        ref={fileRef}
        type="file"
        accept=".png,.byaf,.json,image/png,application/json"
        multiple
        hidden
        onChange={(e) => {
          void lib.importFiles(e.target.files);
          e.target.value = '';
        }}
      />
      <input
        ref={folderInputRef}
        type="file"
        hidden
        onChange={(e) => {
          void lib.importFiles(e.target.files);
          e.target.value = '';
        }}
      />

      {lib.selecting && (
        <SelectionBar
          count={lib.selectedIds.size}
          onMove={() => setDialog({ kind: 'move', ids: Array.from(lib.selectedIds) })}
          onDelete={() => setDialog({ kind: 'deleteSelected', ids: Array.from(lib.selectedIds) })}
          onCancel={lib.cancelSelecting}
        />
      )}

      {lib.error && <p className="error">{lib.error}</p>}

      {!lib.searching && lib.folderId !== null && (
        <div className="breadcrumb">
          <button
            className="link-btn crumb-drop"
            onClick={() => lib.setFolderId(null)}
            onDragOver={(e) => e.preventDefault()}
            onDrop={() => dropOnFolder(null)}
          >
            Home
          </button>
          {lib.trail.map((f) => (
            <span key={f.id}>
              <span className="crumb-sep">/</span>
              <button className="link-btn" onClick={() => lib.setFolderId(f.id)}>
                {f.name}
              </button>
            </span>
          ))}
        </div>
      )}

      {showSubfolders && (
        <div className="lib-grid" style={gridStyle}>
          {lib.subfolders.map((f) => (
            <FolderCard
              key={f.id}
              folder={f}
              onOpen={() => lib.setFolderId(f.id)}
              onMenu={(e) => openMenu(e, folderMenu(f))}
              onDropChars={() => dropOnFolder(f.id)}
            />
          ))}
        </div>
      )}

      {showGroups && (
        <>
          <h3 className="section-label">Group chats</h3>
          <div className="lib-grid" style={gridStyle}>
            {lib.groups.map((g) => (
              <GroupCard
                key={g.id}
                group={g}
                onOpen={() => lib.openGroup(g)}
                onMenu={(e) => openMenu(e, groupMenu(g))}
              />
            ))}
          </div>
        </>
      )}

      {lib.loading ? (
        <div className="centered">
          <div className="spinner" />
        </div>
      ) : (
        <>
          {(showSubfolders || showGroups) && <h3 className="section-label">Characters</h3>}
          {lib.chars.length === 0 ? (
            <p className="muted">No characters here.</p>
          ) : (
            <div className="lib-grid" style={gridStyle}>
              {lib.chars.map((c) => (
                <CharacterCard
                  key={c.id}
                  char={c}
                  selecting={lib.selecting}
                  selected={lib.selectedIds.has(c.id)}
                  onOpen={() => lib.openCharacter(c)}
                  onToggleSelect={() => lib.toggleSelect(c.id)}
                  onMenu={(e) => openMenu(e, charMenu(c))}
                  dndEnabled={wide}
                  onDragStart={() => setDraggedId(c.id)}
                />
              ))}
            </div>
          )}
        </>
      )}

      {menu && <CardMenu menu={menu} onClose={() => setMenu(null)} />}

      {dialog?.kind === 'newFolder' && (
        <PromptDialog
          title={lib.folderId ? 'New subfolder' : 'New folder'}
          confirmLabel="Create"
          onConfirm={(name) => lib.createFolder(name, lib.folderId)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'renameFolder' && (
        <PromptDialog
          title="Rename folder"
          initial={dialog.folder.name}
          confirmLabel="Rename"
          onConfirm={(name) => lib.renameFolder(dialog.folder.id, name)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'deleteFolder' && (
        <ConfirmDialog
          title="Delete folder"
          message={`Delete "${dialog.folder.name}"? Subfolders are also removed and the characters inside move back to the root (the characters themselves are kept).`}
          confirmLabel="Delete folder"
          danger
          onConfirm={() => lib.deleteFolder(dialog.folder.id)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'deleteChar' && (
        <ConfirmDialog
          title="Delete character"
          message={`Permanently delete "${dialog.char.name}" and its card, image and chat history? This cannot be undone.`}
          confirmLabel="Delete"
          danger
          onConfirm={() => lib.deleteCharacter(dialog.char.id)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'deleteSelected' && (
        <ConfirmDialog
          title="Delete selected"
          message={`Permanently delete ${dialog.ids.length} selected character${dialog.ids.length === 1 ? '' : 's'} and their chat history? This cannot be undone.`}
          confirmLabel="Delete"
          danger
          onConfirm={() => lib.bulkDelete(dialog.ids)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'deleteGroup' && (
        <ConfirmDialog
          title="Delete group"
          message={`Delete group "${dialog.group.name}"? This removes the group and its chats (the member characters are not deleted).`}
          confirmLabel="Delete group"
          danger
          onConfirm={() => lib.deleteGroup(dialog.group)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'extractGroup' && (
        <ConfirmDialog
          title="Extract characters"
          message={`Copy every member of "${dialog.group.name}" into your library as independent characters?`}
          confirmLabel="Extract"
          onConfirm={() => lib.extractGroup(dialog.group)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'move' && (
        <MoveToFolderDialog
          folders={lib.folders}
          onPick={(folderId) => {
            lib.moveToFolder(dialog.ids, folderId);
            setDialog(null);
          }}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  );
}
