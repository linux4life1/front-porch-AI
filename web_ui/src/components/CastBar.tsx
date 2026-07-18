// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unified cast roster for the chat — the web mirror of Rawhide's single
// participant roster (one chat, changing cast). Shows every present speaker
// (host + scene guests in 1:1; members in a group), lets you focus one to
// scope the sidebar, and exposes the cast actions. Actions are driven by the
// in-chat slash commands (which route through ChatService), so behavior matches
// the desktop exactly.

export interface CastMember {
  id: string;
  dbId: string | null;
  name: string;
  isHost: boolean;
  isLite: boolean;
  realismEnabled: boolean;
  emotion: string | null;
  isNext: boolean;
  hasAvatar: boolean;
  avatarUrl: string;
}

export function CastBar({
  cast,
  focusedId,
  busy,
  guestStatus,
  guestIsError,
  pendingDetection,
  onFocus,
  onAdd,
  onCommand,
}: {
  cast: CastMember[];
  focusedId: string | null;
  busy: boolean;
  guestStatus: string | null;
  guestIsError: boolean;
  pendingDetection: string | null;
  onFocus: (id: string) => void;
  onAdd: () => void;
  onCommand: (cmd: string) => void;
}) {
  // A lone host is the classic 1:1 — no roster chrome needed.
  const soloHost = cast.length <= 1;
  const hasLiteGuest = cast.some((c) => c.isLite);

  return (
    <div className="cast-bar">
      <div className="cast-row">
        {cast.map((c) => (
          <div
            key={c.id}
            className={`cast-chip${c.id === focusedId ? ' focused' : ''}${c.isNext ? ' next' : ''}`}
          >
            <button className="cast-chip-main" onClick={() => onFocus(c.id)} title="Focus this character">
              <span className="cast-name">{c.name}</span>
              <span className="cast-role">
                {c.isHost ? 'host' : c.isLite ? 'guest' : 'member'}
                {c.emotion ? ` · ${c.emotion}` : ''}
              </span>
            </button>
            {!c.isHost && (
              <span className="cast-actions">
                <button className="icon-btn" title="Speak now" disabled={busy} onClick={() => onCommand(`/speak ${c.name}`)}>🗣</button>
                <button className="icon-btn" title="Remove from scene" disabled={busy} onClick={() => onCommand(`/exit ${c.name}`)}>✕</button>
              </span>
            )}
          </div>
        ))}
        <button className="cast-add" disabled={busy} onClick={onAdd} title="Add a character to the scene">＋</button>
      </div>

      <div className="cast-controls">
        {hasLiteGuest && (
          <button className="ghost small" disabled={busy} onClick={() => onCommand('/promote')} title="Make everyone a full group member">
            Promote to group
          </button>
        )}
        {!soloHost && (
          <button className="ghost small" disabled={busy} onClick={() => onCommand('/scan')} title="Scan the scene for a new character to add">
            Scan scene
          </button>
        )}
      </div>

      {guestStatus && (
        <div className={`cast-banner${guestIsError ? ' error' : ''}`}>{guestStatus}</div>
      )}
      {pendingDetection && (
        <div className="cast-banner detect">
          <span>New character mentioned: <strong>{pendingDetection}</strong></span>
          <button className="ghost small" disabled={busy} onClick={() => onCommand(`/create ${pendingDetection}: a character in the scene`)}>
            Add to scene
          </button>
        </div>
      )}
    </div>
  );
}
