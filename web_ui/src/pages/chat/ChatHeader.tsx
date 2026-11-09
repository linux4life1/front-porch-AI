// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat page's top bar, the desktop window's at every width (PR 1a wide,
// PR 1b phone and tablet): Back, the cast's stacked avatars (or the one
// chat's portrait), the chat's name with its group line, and one sidebar
// button at the far right. The model, Persona, Theme, Conversations, Edit
// and Stats left the header for the composer row and the sidebar. Below
// 1024 the sidebar button opens the drawer; at 1024 and up it shows or
// hides the column.

import { SmartImg } from '../../components/ChatAvatar';
import type { CastMember } from '../../components/CastBar';

/** Stack at most this many member circles, as the desktop window does. */
const STACK_MAX = 6;

export function ChatHeader({
  title,
  focused,
  isGroupMode,
  expressionLabel,
  characterId,
  cast,
  groupLine,
  onBack,
  onToggleSidebar,
}: {
  title: string;
  focused: CastMember | undefined;
  isGroupMode: boolean;
  expressionLabel: string | undefined;
  characterId: string | undefined;
  /** The cast, for the group header's stacked avatars. */
  cast: CastMember[];
  /** Second header line for groups, e.g. `4 characters • Round Robin`. */
  groupLine: string | undefined;
  onBack: () => void;
  onToggleSidebar: () => void;
}) {
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
        // The window's initial circle replaces it when nothing loads.
        <SmartImg
          primary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
          fallback={
            focused.placeholderPortrait
              ? undefined
              : `/api/characters/${focused.dbId ?? characterId ?? ''}/avatar`
          }
          className="chat-header-avatar"
          initial={focused.name}
        />
      ) : (
        <SmartImg
          primary={focused.placeholderPortrait ? '' : focused.avatarUrl ?? ''}
          className="chat-header-avatar"
          initial={focused.name}
        />
      )
    ) : null;

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
