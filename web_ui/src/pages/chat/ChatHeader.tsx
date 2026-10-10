// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat page's top bar: avatar, chat name, model chip and the chat's
// buttons. Wide screens show every button in a row. A phone keeps one line:
// model chip, Stats, Conversations and a ⋯ menu holding Edit, Persona and
// Theme (the library's own popover menu, so it looks and closes the same way).

import { useRef, useState } from 'react';
import { SmartImg } from '../../components/ChatAvatar';
import type { CastMember } from '../../components/CastBar';
import { CardMenu, type CardMenuItem, type MenuState } from '../../components/library/CardMenu';
import { ChatModelSwitcher } from './ChatModelSwitcher';

/** Menu width in CardMenu; the menu's right edge lines up with the ⋯ button. */
const MENU_WIDTH = 210;

export function ChatHeader({
  title,
  focused,
  isGroupMode,
  expressionLabel,
  characterId,
  isPhone,
  hasStats,
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
  hasStats: boolean;
  /** Absent when there is no library character to edit (a group). */
  onEdit: (() => void) | undefined;
  onStats: () => void;
  onPersona: () => void;
  onTheme: () => void;
  onConversations: () => void;
}) {
  const [menu, setMenu] = useState<MenuState | null>(null);
  const moreRef = useRef<HTMLButtonElement>(null);

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

  return (
    <div className="chat-header">
      <div className="chat-header-id">
        {focused &&
          (isGroupMode ? (
            // Groups have no single avatar and member images don't resolve in
            // the cast — show a group glyph rather than a broken image.
            <span className="chat-header-avatar group" aria-hidden>
              👥
            </span>
          ) : focused.isHost ? (
            <SmartImg
              primary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
              fallback={`/api/characters/${focused.dbId ?? characterId ?? ''}/avatar`}
              className="chat-header-avatar"
            />
          ) : (
            <SmartImg primary={focused.avatarUrl ?? ''} className="chat-header-avatar" />
          ))}
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
