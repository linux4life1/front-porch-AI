// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat sidebar below 1024px (PR 1b): the same ChatSidebar card tree as
// the wide column, in an overlay. On a phone it fills the screen; on a
// tablet it slides over from the right at 380px and dims the chat. A top bar
// carries the chat's title and a Close button.
//
// It mounts on the first open and then stays mounted, hidden with
// `visibility: hidden`, so the card tree keeps its scroll position (and its
// loaded tools snapshot) when closed and reopened. `visibility` keeps the
// hidden tree out of the tab order and the accessibility tree.

import { useEffect, useRef, useState, type ReactNode } from 'react';

export function ChatSidebarDrawer({
  open,
  title,
  mode,
  onClose,
  children,
}: {
  open: boolean;
  /** The chat's title, as the wide header shows it. */
  title: string;
  /** `full` fills a phone's screen; `slide` is the tablet's 380px panel. */
  mode: 'full' | 'slide';
  onClose: () => void;
  children: ReactNode;
}) {
  // Mount on the first open; keep it after that for the scroll position.
  const [mounted, setMounted] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (open) setMounted(true);
  }, [open]);
  useEffect(() => {
    if (open) closeRef.current?.focus();
  }, [open]);
  if (!mounted) return null;
  return (
    <div
      className={`drawer-backdrop chat-sidebar-backdrop ${mode}${open ? '' : ' closed'}`}
      aria-hidden={open ? undefined : true}
      onClick={open ? onClose : undefined}
    >
      <div
        className={`chat-sidebar-drawer ${mode}`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="chat-sidebar-drawer-head">
          <span className="chat-sidebar-drawer-title">{title}</span>
          <button
            ref={closeRef}
            type="button"
            className="icon-btn chat-sidebar-close"
            aria-label="Close"
            title="Close"
            onClick={onClose}
          >
            ✕
          </button>
        </div>
        <div className="chat-sidebar-drawer-body chat-sidebar">{children}</div>
      </div>
    </div>
  );
}
