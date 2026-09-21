// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library kebab/right-click menus. Extracted from CharactersPage so that page
// stays under the file-size cap while Chat History lands after Start new chat.

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
    onDuplicate: () => void;
    onExportPng: () => void;
    onExportJson: () => void;
    onMove: () => void;
    onRemoveFolder: () => void;
    onDelete: () => void;
  },
): CardMenuItem[] {
  return [
    { label: 'Start new chat', icon: '💬', onClick: a.onNewChat },
    { label: 'Chat History', icon: '📂', onClick: a.onHistory },
    { label: 'Edit', icon: '✏️', onClick: a.onEdit },
    { label: 'AI Enhance', icon: '✨', onClick: a.onEnhance },
    { label: 'Duplicate', icon: '⧉', onClick: a.onDuplicate },
    { label: 'Export PNG', icon: '🖼', onClick: a.onExportPng },
    { label: 'Export JSON', icon: '📄', onClick: a.onExportJson },
    { label: 'Move to folder…', icon: '📁', onClick: a.onMove },
    ...(a.inFolder
      ? [{ label: 'Remove from folder', icon: '📤', onClick: a.onRemoveFolder }]
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
    onExportPng: () => void;
    onExtract: () => void;
    onMove: () => void;
    onRemoveFolder: () => void;
    onDelete: () => void;
  },
): CardMenuItem[] {
  return [
    { label: 'Start new chat', icon: '💬', onClick: a.onNewChat },
    { label: 'Chat History', icon: '📂', onClick: a.onHistory },
    { label: 'Export Group PNG', icon: '🖼', onClick: a.onExportPng },
    { label: 'Extract characters', icon: '👥', onClick: a.onExtract },
    { label: 'Move to folder…', icon: '📁', onClick: a.onMove },
    ...(a.inFolder
      ? [{ label: 'Remove from folder', icon: '📤', onClick: a.onRemoveFolder }]
      : []),
    { label: 'Delete', icon: '🗑', danger: true, onClick: a.onDelete },
  ];
}

export function folderCardMenu(
  _f: LibFolder,
  a: {
    onRename: () => void;
    onNewSubfolder: () => void;
    onDeleteFolder: () => void;
    onDeleteDeep: () => void;
  },
): CardMenuItem[] {
  return [
    { label: 'Rename', icon: '✏️', onClick: a.onRename },
    { label: 'New subfolder', icon: '📂', onClick: a.onNewSubfolder },
    { label: 'Delete folder only', icon: '🗑', onClick: a.onDeleteFolder },
    {
      label: 'Delete folder + characters',
      icon: '💥',
      danger: true,
      onClick: a.onDeleteDeep,
    },
  ];
}

export function importCardMenu(a: {
  onImportCards: () => void;
  onImportFolder: () => void;
  onImportByaf: () => void;
}): CardMenuItem[] {
  return [
    { label: 'Import cards…', icon: '🖼', onClick: a.onImportCards },
    { label: 'Import a folder…', icon: '📁', onClick: a.onImportFolder },
    {
      label: 'Import Backyard AI (.byaf)…',
      icon: '📦',
      onClick: a.onImportByaf,
    },
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
}
