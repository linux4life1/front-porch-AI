// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draft key building and storage round-trips. An empty write removes the
// key (a cleared box must not haunt the reopen), and a denied storage
// call is swallowed — the PWA simply loses the draft.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  composerDraftOwnerKey,
  composerDraftSessionKey,
  loadComposerDraft,
  persistComposerDraft,
  saveComposerDraft,
} from './composerDraft';

afterEach(() => {
  localStorage.clear();
  vi.restoreAllMocks();
});

describe('composer draft persistence', () => {
  it('keys session and owner drafts apart', () => {
    expect(composerDraftSessionKey('1730000000000')).toBe(
      'fpai.draft.s.1730000000000',
    );
    expect(composerDraftOwnerKey('nina.png')).toBe('fpai.draft.o.nina.png');
    expect(composerDraftOwnerKey('group_abc')).toBe('fpai.draft.o.group_abc');
  });

  it('round-trips a draft through storage', () => {
    const key = composerDraftSessionKey('42');
    saveComposerDraft(key, 'half a thought');
    expect(loadComposerDraft(key)).toBe('half a thought');
  });

  it('an empty write removes the key, not stores it', () => {
    const key = composerDraftOwnerKey('nina.png');
    saveComposerDraft(key, 'typed');
    saveComposerDraft(key, '');
    expect(localStorage.getItem(key)).toBeNull();
    expect(loadComposerDraft(key)).toBe('');
  });

  it('a denied storage call loses the draft, not the app', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('full');
    });
    expect(() => saveComposerDraft('fpai.draft.s.x', 'text')).not.toThrow();
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('denied');
    });
    expect(loadComposerDraft('fpai.draft.s.x')).toBe('');
  });

  it('persist routes text to the active key only', () => {
    const box = {
      sessionKey: 'fpai.draft.s.9',
      ownerKey: 'fpai.draft.o.nina.png',
    };
    persistComposerDraft(box, box.ownerKey, 'in the mailbox');
    expect(loadComposerDraft(box.ownerKey)).toBe('in the mailbox');
    expect(loadComposerDraft(box.sessionKey)).toBe('');
  });

  it('a cleared box empties BOTH keys', () => {
    const box = {
      sessionKey: 'fpai.draft.s.9',
      ownerKey: 'fpai.draft.o.nina.png',
    };
    localStorage.setItem(box.sessionKey, 'stale session line');
    localStorage.setItem(box.ownerKey, 'stale mailbox line');
    persistComposerDraft(box, box.sessionKey, '');
    expect(localStorage.getItem(box.sessionKey)).toBeNull();
    expect(localStorage.getItem(box.ownerKey)).toBeNull();
  });
});
