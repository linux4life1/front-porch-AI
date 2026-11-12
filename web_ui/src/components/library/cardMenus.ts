// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library kebab/right-click menus. Extracted from CharactersPage so that page
// stays under the file-size cap while Manage Chats lands after Start new chat.

import type { CardMenuItem } from './CardMenu';
import type { LibChar, LibFolder, LibGroup } from '../../hooks/useLibrary';

export function characterCardMenu(
  _c: LibChar,
  a: {
    inFolder: boolean;
    onNewChat: () => void;
    onHistory: () => void;
    onEdit: () => void;
    onEnhance: () => void;
    onAvatarGallery: () => void;
    onDuplicate: () => void;
    /** "Use as persona" — omitted when the host can't convert. */
    onUseAsPersona?: () => void;
    onExportPng: () => void;
    onExportJson: () => void;
    onMove: () => void;
    onRemoveFolder: () => void;
    onDelete: () => void;
  },
): CardMenuItem[] {
  return [
    { label: 'Start New Chat', icon: '💬', onClick: a.onNewChat },
    { label: 'Manage Chats', icon: '📂', onClick: a.onHistory },
    { label: 'Edit Character', icon: '✏️', onClick: a.onEdit },
    { label: 'AI Enhance', icon: '✨', onClick: a.onEnhance },
    { label: 'Avatar Gallery', icon: '🖼', onClick: a.onAvatarGallery },
    { label: 'Duplicate Character', icon: '⧉', onClick: a.onDuplicate },
    ...(a.onUseAsPersona
      ? [{ label: 'Use as Persona', icon: '🎭', onClick: a.onUseAsPersona }]
      : []),
    { label: 'Export PNG', icon: '🖼', onClick: a.onExportPng },
    { label: 'Export JSON', icon: '📄', onClick: a.onExportJson },
    { label: 'Move to Folder…', icon: '📁', onClick: a.onMove },
    ...(a.inFolder
      ? [{ label: 'Remove from Folder', icon: '📤', onClick: a.onRemoveFolder }]
      : []),
    { label: 'Delete', icon: '🗑', danger: true, onClick: a.onDelete },
  ];
}

export function groupCardMenu(
  _g: LibGroup,
  a: {
    inFolder: boolean;
    onNewChat: () => void;
    onHistory: () => void;
    onEdit: () => void;
    onDuplicate: () => void;
    onExportPng: () => void;
    onExtract: () => void;
    onMove: () => void;
    onRemoveFolder: () => void;
    onDelete: () => void;
  },
): CardMenuItem[] {
  return [
    { label: 'Start New Chat', icon: '💬', onClick: a.onNewChat },
    { label: 'Manage Chats', icon: '📂', onClick: a.onHistory },
    { label: 'Edit Group', icon: '✏️', onClick: a.onEdit },
    { label: 'Duplicate Group', icon: '⧉', onClick: a.onDuplicate },
    { label: 'Export PNG', icon: '🖼', onClick: a.onExportPng },
    { label: 'Extract Characters', icon: '👥', onClick: a.onExtract },
    { label: 'Move to Folder', icon: '📁', onClick: a.onMove },
    ...(a.inFolder
      ? [{ label: 'Remove from Folder', icon: '📤', onClick: a.onRemoveFolder }]
      : []),
    { label: 'Delete', icon: '🗑', danger: true, onClick: a.onDelete },
  ];
}

export function folderCardMenu(
  _f: LibFolder,
  a: {
    onRename: () => void;
    onNewSubfolder: () => void;
    /** "Delete Folder…" opens the one dialog that offers both deletions. */
    onDelete: () => void;
  },
): CardMenuItem[] {
  return [
    { label: 'Rename Folder', icon: '✏️', onClick: a.onRename },
    { label: 'New Subfolder', icon: '📂', onClick: a.onNewSubfolder },
    { label: 'Delete Folder…', icon: '🗑', danger: true, onClick: a.onDelete },
  ];
}

export function importCardMenu(a: {
  onImportCards: () => void;
  onImportFolder: () => void;
  onImportByaf: () => void;
  /** Front Porch's own .porch / .porchpack files (issue #348). */
  onImportPorch?: () => void;
}): CardMenuItem[] {
  return [
    { label: 'Import Cards', icon: '🖼', onClick: a.onImportCards },
    { label: 'Import Folder', icon: '📁', onClick: a.onImportFolder },
    {
      label: 'Import Backyard AI (.byaf)',
      icon: '📦',
      onClick: a.onImportByaf,
    },
    ...(a.onImportPorch
      ? [{ label: 'Import .porch / .porchpack', icon: '🗂', onClick: a.onImportPorch }]
      : []),
  ];
}
