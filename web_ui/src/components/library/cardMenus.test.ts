// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library kebab menus put Manage Chats immediately after Start new chat.

import { describe, expect, it } from 'vitest';
import { characterCardMenu, groupCardMenu } from './cardMenus';
import type { LibChar, LibGroup } from '../../hooks/useLibrary';

const noop = () => {};

const char: LibChar = {
  id: 'c1',
  name: 'Misty',
  tags: [],
  hasAvatar: false,
  messageCount: 0,
  folderId: '',
};

const group: LibGroup = {
  id: 'g1',
  name: 'The porch',
  folderId: '',
  memberCount: 2,
  members: [],
};

const charActions = {
  inFolder: false,
  onNewChat: noop,
  onHistory: noop,
  onEdit: noop,
  onEnhance: noop,
  onDuplicate: noop,
  onExportPng: noop,
  onExportJson: noop,
  onMove: noop,
  onRemoveFolder: noop,
  onDelete: noop,
};

describe('library card menus', () => {
  it('puts Manage Chats after Start new chat on a character', () => {
    const labels = characterCardMenu(char, charActions).map((i) => i.label);
    expect(labels.indexOf('Manage Chats')).toBe(labels.indexOf('Start new chat') + 1);
  });

  it('puts Manage Chats after Start new chat on a group', () => {
    const labels = groupCardMenu(group, {
      inFolder: false,
      onNewChat: noop,
      onHistory: noop,
      onExportPng: noop,
      onExtract: noop,
      onMove: noop,
      onRemoveFolder: noop,
      onDelete: noop,
    }).map((i) => i.label);
    expect(labels.indexOf('Manage Chats')).toBe(labels.indexOf('Start new chat') + 1);
  });
});
