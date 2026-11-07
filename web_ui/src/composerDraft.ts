// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Composer drafts on the web: a half-typed message the user left in the
// box when they closed the chat comes back when they reopen it. Desktop
// keeps the draft on the sessions row (v65 sessions.composer_draft);
// the PWA has no direct DB access, so it mirrors the desktop's routing
// on this device: a session that already has a user message (the point
// where the desktop row materializes) keys by session, and a never-sent
// new chat keys by owner — the same split the desktop store applies.
// Storage failures are silent: a draft that won't survive a reload is
// the old behavior, not an error.

/** Session-backed key: the chat has sent at least one message. */
export function composerDraftSessionKey(sessionId: string): string {
  return `fpai.draft.s.${sessionId}`;
}

/** Owner key: the last never-sent draft for this character or group.
 *  Mirrors the desktop's `composer_draft.<stableGroupId>` /
 *  `composer_draft.group_<id>` mailbox. */
export function composerDraftOwnerKey(ownerId: string): string {
  return `fpai.draft.o.${ownerId}`;
}

export function loadComposerDraft(key: string): string {
  try {
    return localStorage.getItem(key) ?? '';
  } catch {
    /* private mode / blocked storage */
    return '';
  }
}

/** Write the draft; an empty text removes the key instead of storing ''. */
export function saveComposerDraft(key: string, text: string): void {
  try {
    if (text === '') localStorage.removeItem(key);
    else localStorage.setItem(key, text);
  } catch {
    /* storage full / disabled — the draft just won't survive a reload */
  }
}

/** Put a box's text away for the chat it belongs to. A cleared box
 *  (a send) clears BOTH keys — a mailbox holding the old key would
 *  replay the sent line into the next new chat. Non-empty text rides
 *  the active key only: a saved chat's line never overwrites another
 *  chat's mailbox letter. Mirrors ComposerDraftStore.saveDraft. */
export function persistComposerDraft(
  box: { sessionKey: string; ownerKey: string },
  activeKey: string | null,
  text: string,
): void {
  if (text === '') {
    saveComposerDraft(box.sessionKey, '');
    saveComposerDraft(box.ownerKey, '');
  } else if (activeKey) {
    saveComposerDraft(activeKey, text);
  }
}
