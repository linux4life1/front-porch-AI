// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character library: folders, groups, and characters with full desktop parity
// (create/rename/delete folders, per-card menu with edit/duplicate/export/
// move/remove/delete, multi-select bulk move + delete, drag-and-drop into
// folders, folder-scoped search, import cards/folder + online browsers, grid
// size + import-date sort, and group export/extract). The page is a thin shell;
// data + actions live in useLibrary and the library/* components.

import { useEffect, useMemo, useRef, useState, type CSSProperties, type MouseEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { InstallHint } from '../components/InstallHint';
import { useLayout } from '../hooks/useBreakpoint';
import { useLibrary, type LibChar, type LibFolder, type LibGroup } from '../hooks/useLibrary';
import { useProgressiveList } from '../hooks/useProgressiveList';
import { CardMenu, type CardMenuItem, type MenuState } from '../components/library/CardMenu';
import { CharacterCard, FolderCard, GroupCard } from '../components/library/LibraryCards';
import { LibraryToolbar, SelectionBar } from '../components/library/LibraryToolbar';
import { ChatHistoryModal } from '../components/library/ChatHistoryModal';
import {
  characterCardMenu,
  folderCardMenu,
  groupCardMenu,
  importCardMenu,
} from '../components/library/cardMenus';
import {
  ConfirmDialog,
  ImportNameCollisionDialog,
  MoveToFolderDialog,
  PersonaPickerDialog,
  PromptDialog,
  TypeConfirmDialog,
  type PickerPersona,
} from '../components/library/LibraryDialogs';
import { EnhanceDialog } from '../components/aichargen/EnhanceDialog';
import { EnhanceReviewModal } from '../components/aichargen/EnhanceReviewModal';
import type { EnhanceProposal, EnhanceSelection } from '../components/aichargen/enhanceForm';

type Dialog =
  | { kind: 'newFolder' }
  | { kind: 'renameFolder'; folder: LibFolder }
  | { kind: 'newSubfolder'; folder: LibFolder }
  | { kind: 'deleteFolder'; folder: LibFolder }
  | { kind: 'deleteFolderDeep'; folder: LibFolder }
  | { kind: 'deleteChar'; char: LibChar }
  | { kind: 'deleteGroup'; group: LibGroup }
  | { kind: 'deleteSelected'; ids: string[] }
  | { kind: 'extractGroup'; group: LibGroup }
  | { kind: 'move'; ids: string[] }
  // Step 2 of "Start new chat": persona choice for a fresh session.
  | { kind: 'newChat'; subject: string; target: { characterId?: string; groupId?: string } }
  // AI Enhance: pre-flight (chat pick + field checklist + progress), then the
  // old-vs-new review once the proposal arrives over the socket.
  | { kind: 'aiEnhance'; char: LibChar }
  | { kind: 'enhanceReview'; char: LibChar; proposal: EnhanceProposal; selection: EnhanceSelection }
  | { kind: 'chatHistory'; characterId?: string; groupId?: string }
  | null;

export function CharactersPage() {
  const lib = useLibrary();
  const navigate = useNavigate();
  const { wide } = useLayout();
  const [menu, setMenu] = useState<MenuState | null>(null);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [draggedId, setDraggedId] = useState<string | null>(null);
  // Personas for "Start new chat" step 2. Fetched once when the dialog is
  // first opened (not on page load — most visits never need it).
  const [personas, setPersonas] = useState<PickerPersona[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);
  const folderInputRef = useRef<HTMLInputElement>(null);
  const byafRef = useRef<HTMLInputElement>(null);

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

  // Refresh the persona list whenever the new-chat dialog opens, so a persona
  // added on the desktop (or another tab) shows up without a reload.
  // Depend on the stable `loadPersonas` callback, NEVER on `lib` — useLibrary
  // returns a fresh object literal every render, and setPersonas re-renders
  // this page, so `lib` as a dep re-fires the effect forever while the picker
  // is open (one GET /api/personas per round trip).
  const { loadPersonas } = lib;
  useEffect(() => {
    if (dialog?.kind !== 'newChat') return;
    void loadPersonas().then(setPersonas);
  }, [dialog?.kind, loadPersonas]);

  // ── Menu item builders (one CardMenu serves every surface) ───────────────
  const charMenu = (c: LibChar) =>
    characterCardMenu(c, {
      inFolder: Boolean(lib.folderId),
      onNewChat: () =>
        setDialog({ kind: 'newChat', subject: c.name, target: { characterId: c.id } }),
      onHistory: () => setDialog({ kind: 'chatHistory', characterId: c.id }),
      onEdit: () => lib.editCharacter(c.id),
      onEnhance: () => setDialog({ kind: 'aiEnhance', char: c }),
      onDuplicate: () => lib.duplicateCharacter(c.id),
      onExportPng: () => lib.exportPng(c.id),
      onExportJson: () => lib.exportJson(c.id),
      onMove: () => setDialog({ kind: 'move', ids: [c.id] }),
      onRemoveFolder: () => lib.moveToFolder([c.id], null),
      onDelete: () => setDialog({ kind: 'deleteChar', char: c }),
    });

  const folderMenu = (f: LibFolder) =>
    folderCardMenu(f, {
      onRename: () => setDialog({ kind: 'renameFolder', folder: f }),
      onNewSubfolder: () => setDialog({ kind: 'newSubfolder', folder: f }),
      onDeleteFolder: () => setDialog({ kind: 'deleteFolder', folder: f }),
      onDeleteDeep: () => setDialog({ kind: 'deleteFolderDeep', folder: f }),
    });

  const groupMenu = (g: LibGroup) =>
    groupCardMenu(g, {
      inFolder: Boolean(lib.folderId),
      onNewChat: () =>
        setDialog({ kind: 'newChat', subject: g.name, target: { groupId: g.id } }),
      onHistory: () => setDialog({ kind: 'chatHistory', groupId: g.id }),
      onExportPng: () => lib.exportGroupPng(g),
      onExtract: () => setDialog({ kind: 'extractGroup', group: g }),
      onMove: () => setDialog({ kind: 'move', ids: [g.id] }),
      onRemoveFolder: () => lib.moveToFolder([g.id], null),
      onDelete: () => setDialog({ kind: 'deleteGroup', group: g }),
    });

  const importMenu = () =>
    importCardMenu({
      onImportCards: () => fileRef.current?.click(),
      onImportFolder: () => folderInputRef.current?.click(),
      onImportByaf: () => byafRef.current?.click(),
    });

  // ── Drag-and-drop (desktop/tablet only; phone uses the menu's Move action) ─
  const dropOnFolder = (folderId: string | null) => {
    if (draggedId) lib.moveToFolder([draggedId], folderId);
    setDraggedId(null);
  };

  const gridStyle = { ['--lib-card-min']: `${lib.gridMin}px` } as CSSProperties;

  // Groups follow the folder hierarchy exactly like characters (desktop grid
  // parity): browse shows the current folder's groups ('' folderId = root);
  // searching matches by name — folder-scoped (recursive) unless scope=All.
  const subtreeFolderIds = useMemo(() => {
    const ids = new Set<string>();
    if (!lib.folderId) return ids;
    ids.add(lib.folderId);
    let grew = true;
    while (grew) {
      grew = false;
      for (const f of lib.folders) {
        if (f.parentId && ids.has(f.parentId) && !ids.has(f.id)) {
          ids.add(f.id);
          grew = true;
        }
      }
    }
    return ids;
  }, [lib.folders, lib.folderId]);
  const visibleGroups = useMemo(() => {
    if (lib.searching) {
      const q = lib.search.trim().toLowerCase();
      let gs = lib.groups;
      if (lib.scope !== 'allCharacters' && lib.folderId) {
        gs = gs.filter((g) => subtreeFolderIds.has(g.folderId));
      }
      return gs.filter((g) => g.name.toLowerCase().includes(q));
    }
    return lib.groups.filter((g) => (g.folderId || null) === lib.folderId);
  }, [lib.groups, lib.searching, lib.search, lib.scope, lib.folderId, subtreeFolderIds]);
  const showGroups = visibleGroups.length > 0;
  const showSubfolders = !lib.searching && lib.subfolders.length > 0;

  // Reveal the character grid in chunks so a large library doesn't mount
  // thousands of card nodes at once (folders/groups are bounded, so unwindowed).
  const { visible: visibleChars, sentinelRef, hasMore } = useProgressiveList(lib.chars);

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
      <input
        ref={byafRef}
        type="file"
        accept=".byaf,application/zip"
        multiple
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
            {visibleGroups.map((g) => (
              <GroupCard
                key={g.id}
                group={g}
                selecting={lib.selecting}
                selected={lib.selectedIds.has(g.id)}
                onOpen={() => lib.openGroup(g)}
                onToggleSelect={() => lib.toggleSelect(g.id)}
                onMenu={(e) => openMenu(e, groupMenu(g))}
                dndEnabled={wide}
                onDragStart={() => setDraggedId(g.id)}
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
            <>
              <div className="lib-grid" style={gridStyle}>
                {visibleChars.map((c) => (
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
              {hasMore && (
                <div ref={sentinelRef} className="lib-load-more" aria-hidden>
                  <div className="spinner" />
                </div>
              )}
            </>
          )}
        </>
      )}

      {menu && <CardMenu menu={menu} onClose={() => setMenu(null)} />}

      {dialog?.kind === 'aiEnhance' && (
        <EnhanceDialog
          characterId={dialog.char.id}
          characterName={dialog.char.name}
          defaultNsfw={false}
          onProposal={(proposal, selection) =>
            setDialog({ kind: 'enhanceReview', char: dialog.char, proposal, selection })
          }
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'enhanceReview' && (
        <EnhanceReviewModal
          characterId={dialog.char.id}
          characterName={dialog.char.name}
          proposal={dialog.proposal}
          selection={dialog.selection}
          onApplied={(newId) => {
            setDialog(null);
            navigate(`/edit/${newId}`);
          }}
          onClose={() => setDialog(null)}
        />
      )}

      {dialog?.kind === 'newFolder' && (
        <PromptDialog
          title={lib.folderId ? 'New subfolder' : 'New folder'}
          confirmLabel="Create"
          onConfirm={(name) => lib.createFolder(name, lib.folderId)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'newSubfolder' && (
        <PromptDialog
          title={`New subfolder in "${dialog.folder.name}"`}
          confirmLabel="Create"
          onConfirm={(name) => lib.createFolder(name, dialog.folder.id)}
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
          message={`Delete "${dialog.folder.name}"? Subfolders are also removed and the characters and groups inside move back to the root (the characters and groups themselves are kept).`}
          confirmLabel="Delete folder"
          danger
          onConfirm={() => lib.deleteFolder(dialog.folder.id)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'deleteFolderDeep' && (
        <TypeConfirmDialog
          title="Delete folder + characters"
          message={`This will PERMANENTLY delete the folder "${dialog.folder.name}", its subfolders, and EVERY character inside them — cards, images, and chat histories. Group chats inside are kept and move back to the root. There is no undo and no recycle bin.`}
          confirmLabel="Delete everything"
          onConfirm={() => lib.deleteFolderDeep(dialog.folder.id)}
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
        <TypeConfirmDialog
          title={`Delete ${dialog.ids.length} ${
            dialog.ids.some((id) => id.startsWith('group_'))
              ? `item${dialog.ids.length === 1 ? '' : 's'}`
              : `character${dialog.ids.length === 1 ? '' : 's'}`
          }`}
          message={`This will PERMANENTLY delete the ${dialog.ids.length} selected item${dialog.ids.length === 1 ? '' : 's'} — character cards, images, chat histories, and group chats (deleting a group keeps its member characters). There is no undo and no recycle bin.`}
          confirmLabel={`Delete ${dialog.ids.length}`}
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
      {lib.nameCollision && (
        <ImportNameCollisionDialog
          cardName={lib.nameCollision.name}
          existing={lib.nameCollision.existing}
          onKeepBoth={() => lib.resolveNameCollision('keepBoth')}
          onReplace={(id) => lib.resolveNameCollision('replace', id)}
          onClose={() => lib.resolveNameCollision('cancel')}
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
      {dialog?.kind === 'newChat' && (
        <PersonaPickerDialog
          subject={dialog.subject}
          personas={personas}
          onPick={(personaId) => {
            lib.startFreshChat(dialog.target, personaId);
            setDialog(null);
          }}
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
      {dialog?.kind === 'chatHistory' && (
        <ChatHistoryModal
          characterId={dialog.characterId}
          groupId={dialog.groupId}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  );
}
