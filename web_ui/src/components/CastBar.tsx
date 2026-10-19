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
  /** The picture is only the flat colour a character made without a portrait
   *  carries; draw no picture for it. Absent on older apps. */
  placeholderPortrait?: boolean;
  /** Group members only: where they are. Absent on older apps and in 1:1. */
  presence?: 'withYou' | 'away' | 'atWork' | null;
}

const PRESENCE_WORD = { withYou: 'with you', away: 'away', atWork: 'at work' } as const;

export function CastBar({
  cast,
  focusedId,
  busy,
  settling = false,
  guestStatus,
  guestIsError,
  pendingDetection,
  onFocus,
  onAdd,
  onCommand,
  onSetAway,
  canRemoveMember = true,
}: {
  cast: CastMember[];
  focusedId: string | null;
  busy: boolean;
  /** Post-gen still settling: the server refuses Away / Back until done. */
  settling?: boolean;
  guestStatus: string | null;
  guestIsError: boolean;
  pendingDetection: string | null;
  onFocus: (id: string) => void;
  onAdd: () => void;
  onCommand: (cmd: string) => void;
  /** A group member's Away / Back (desktop's presence word). */
  onSetAway?: (id: string, away: boolean) => void;
  /** False while directing with two characters left (one more exit would
   *  end Director Mode). Guests count too: they are cast members. */
  canRemoveMember?: boolean;
}) {
  // A lone host is the classic 1:1 — no roster chrome needed.
  const soloHost = cast.length <= 1;
  const hasLiteGuest = cast.some((c) => c.isLite);
  const isOneToOne = cast.some((c) => c.isHost);

  return (
    <div className="cast-bar">
      <div className="cast-row">
        {cast.map((c) => (
          <div
            key={c.id}
            className={`cast-chip${c.id === focusedId ? ' focused' : ''}${c.isNext ? ' next' : ''}${c.presence && c.presence !== 'withYou' ? ' away' : ''}`}
          >
            <button className="cast-chip-main" onClick={() => onFocus(c.id)} title="Focus this character">
              <span className="cast-name">{c.name}</span>
              <span className="cast-role">
                {c.isHost ? 'host' : c.isLite ? 'guest' : 'member'}
                {c.emotion ? ` · ${c.emotion}` : ''}
                {c.presence ? ` · ${PRESENCE_WORD[c.presence]}` : ''}
              </span>
            </button>
            {!c.isHost && (
              <span className="cast-actions">
                {onSetAway && (c.presence === 'withYou' || c.presence === 'away') && (
                  <button
                    className="ghost small"
                    disabled={busy || settling}
                    onClick={() => onSetAway(c.id, c.presence === 'withYou')}
                    title={c.presence === 'withYou' ? 'Mark as away' : 'Bring back into the scene'}
                  >
                    {c.presence === 'withYou' ? 'Away' : 'Back'}
                  </button>
                )}
                <button className="icon-btn" title="Speak now" disabled={busy} onClick={() => onCommand(`/speak ${c.name}`)}>🗣</button>
                {c.isLite && (
                  <button
                    className="ghost small"
                    disabled={busy}
                    onClick={() => onCommand(`/promote ${c.name}`)}
                    title="Make this guest a full member"
                  >
                    Promote
                  </button>
                )}
                <button
                  className="icon-btn"
                  title={
                    canRemoveMember
                      ? 'Remove from scene'
                      : 'While you direct, the scene keeps at least two characters'
                  }
                  disabled={busy || !canRemoveMember}
                  onClick={() => onCommand(`/exit ${c.name}`)}
                >
                  ✕
                </button>
              </span>
            )}
          </div>
        ))}
        <button className="cast-add" disabled={busy} onClick={onAdd} title="Add a character to the scene">＋</button>
      </div>

      <div className="cast-controls">
        {hasLiteGuest && isOneToOne && (
          <button className="ghost small" disabled={busy} onClick={() => onCommand('/promote')} title="Turn this scene into a group (guests stay lite until you promote them)">
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
