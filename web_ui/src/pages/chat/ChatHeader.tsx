// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat page's top bar. Desktop (≥1024) matches the desktop window:
// Back, the cast's stacked avatars (or the one chat's portrait), the chat's
// name with its group line, and a sidebar toggle at the far right — the
// model, Persona, Theme, Conversations, Edit and Stats leave the header for
// the composer row and the sidebar (PR 1a). A tablet keeps the wide row of
// buttons it has always had. A phone keeps one line: model chip, Stats,
// Conversations and a ⋯ menu holding Edit, Persona and Theme (the library's
// own popover menu, so it looks and closes the same way).

import { useEffect, useRef, useState } from 'react';
import { SmartImg } from '../../components/ChatAvatar';
import type { CastMember } from '../../components/CastBar';
import { CardMenu, type CardMenuItem, type MenuState } from '../../components/library/CardMenu';
import { ChatModelSwitcher } from './ChatModelSwitcher';

/** Menu width in CardMenu; the menu's right edge lines up with the ⋯ button. */
const MENU_WIDTH = 210;

/** Stack at most this many member circles, as the desktop window does. */
const STACK_MAX = 6;

export function ChatHeader({
  title,
  focused,
  isGroupMode,
  expressionLabel,
  characterId,
  isPhone,
  isDesktop,
  hasStats,
  cast,
  groupLine,
  onBack,
  onToggleSidebar,
  onEdit,
  onStats,
  onPersona,
  onTheme,
  onConversations,
}: {
  title: string;
  focused: CastMember | undefined;
  isGroupMode: boolean;
  expressionLabel: string | undefined;
  characterId: string | undefined;
  isPhone: boolean;
  /** The ≥1024 layout: full-width chat, desktop header, sidebar toggle. */
  isDesktop: boolean;
  hasStats: boolean;
  /** The cast, for the group header's stacked avatars (desktop only). */
  cast: CastMember[];
  /** Second header line for groups, e.g. `4 characters • Round Robin`. */
  groupLine: string | undefined;
  onBack: () => void;
  onToggleSidebar: () => void;
  /** Absent when there is no library character to edit (a group). */
  onEdit: (() => void) | undefined;
  onStats: () => void;
  onPersona: () => void;
  onTheme: () => void;
  onConversations: () => void;
}) {
  const [menu, setMenu] = useState<MenuState | null>(null);
  const moreRef = useRef<HTMLButtonElement>(null);

  // Turning the phone to a wide layout drops the ⋯; its open menu goes too,
  // or turning back would re-show it at the old spot.
  useEffect(() => {
    if (!isPhone) setMenu(null);
  }, [isPhone]);

  const closeMenu = () => {
    setMenu(null);
    moreRef.current?.focus();
  };

  const openMenu = () => {
    const r = moreRef.current?.getBoundingClientRect();
    const items: CardMenuItem[] = [
      ...(onEdit ? [{ label: 'Edit character', icon: '✎', onClick: onEdit }] : []),
      { label: 'Persona', icon: '👤', onClick: onPersona },
      { label: 'Theme', icon: '🎨', onClick: onTheme },
    ];
    setMenu({ x: (r?.right ?? window.innerWidth) - MENU_WIDTH, y: (r?.bottom ?? 0) + 4, items });
  };

  const avatar =
    focused && isGroupMode ? (
      // Groups have no single avatar and member images don't resolve in
      // the cast — show a group glyph rather than a broken image.
      <span className="chat-header-avatar group" aria-hidden>
        👥
      </span>
    ) : focused ? (
      focused.isHost ? (
        // A mood picture still shows; the flat no-portrait colour does not.
        // Wide, the window's initial circle replaces it when nothing loads.
        <SmartImg
          primary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
          fallback={
            focused.placeholderPortrait
              ? undefined
              : `/api/characters/${focused.dbId ?? characterId ?? ''}/avatar`
          }
          className="chat-header-avatar"
          initial={isDesktop ? focused.name : undefined}
        />
      ) : (
        <SmartImg
          primary={focused.placeholderPortrait ? '' : focused.avatarUrl ?? ''}
          className="chat-header-avatar"
          initial={isDesktop ? focused.name : undefined}
        />
      )
    ) : null;

  const stats = hasStats && (
    <button className="link-btn stats-btn" onClick={onStats}>
      Stats ▾
    </button>
  );
  const conversations = (
    <button className="link-btn conversations-btn" onClick={onConversations}>
      Conversations ▾
    </button>
  );

  // Desktop mirrors the window: Back, the cast stack (or the portrait),
  // the name with its group line, and the sidebar toggle at the end.
  // The action buttons have all reached their destinations (PR 1a):
  // Persona + Conversations sit in the composer's icon row, Edit, Model
  // Settings and Chat settings in the sidebar's Main Settings menu.
  if (isDesktop) {
    return (
      <div className="chat-header chat-header-desktop">
        <button className="chat-back-btn" aria-label="Back" title="Back" onClick={onBack}>
          ←
        </button>
        <div className="chat-header-id">
          {isGroupMode ? (
            <span className="chat-header-stack" aria-hidden>
              {cast.slice(0, STACK_MAX).map((m) =>
                m.hasAvatar && !m.placeholderPortrait && m.avatarUrl ? (
                  <img key={m.id} className="chat-stack-avatar" src={m.avatarUrl} alt="" />
                ) : (
                  <span key={m.id} className="chat-stack-avatar initials">
                    {m.name.charAt(0).toUpperCase()}
                  </span>
                ),
              )}
            </span>
          ) : (
            avatar
          )}
          <span className="chat-header-titles">
            <span className="chat-title">{title}</span>
            {isGroupMode && groupLine && <span className="chat-header-sub">{groupLine}</span>}
          </span>
        </div>
        <button
          className="chat-sidebar-toggle"
          aria-label="Toggle sidebar"
          title="Toggle sidebar"
          onClick={onToggleSidebar}
        >
          ❯|
        </button>
      </div>
    );
  }

  return (
    <div className="chat-header">
      <div className="chat-header-id">
        {avatar}
        <span className="chat-title">{title}</span>
      </div>
      {isPhone ? (
        <div className="chat-header-actions">
          <ChatModelSwitcher />
          {stats}
          {conversations}
          <button
            ref={moreRef}
            className="link-btn chat-header-more"
            aria-label="More chat options"
            title="More chat options"
            aria-haspopup="menu"
            aria-expanded={menu !== null}
            onClick={openMenu}
          >
            ⋯
          </button>
          {menu && <CardMenu menu={menu} onClose={closeMenu} />}
        </div>
      ) : (
        <div className="chat-header-actions">
          <ChatModelSwitcher />
          {onEdit && (
            <button className="link-btn" title="Edit character" onClick={onEdit}>
              ✎
            </button>
          )}
          {stats}
          <button className="link-btn" title="Who you are in this chat" onClick={onPersona}>
            Persona
          </button>
          <button className="link-btn" onClick={onTheme}>
            Theme
          </button>
          {conversations}
        </div>
      )}
    </div>
  );
}
