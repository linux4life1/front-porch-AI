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
  /** PR 5b: this member's Chaos Mode is on — the face rides a dice, the
   *  cast bar's answer to "who rolls" at a glance. Group-only, additive. */
  chaos?: boolean | null;
}

export function CastBar({
  cast,
  focusedId,
  busy,
  settling = false,
  guestStatus,
  guestIsError,
  pendingDetection,
  onFocus,
  onCommand,
  onSetAway,
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
  /** Kept for callers; the strip has no add button (the desktop's has none). */
  onAdd?: () => void;
  onCommand: (cmd: string) => void;
  /** A group member's Away / Back (desktop's presence word). */
  onSetAway?: (id: string, away: boolean) => void;
  /** Kept for callers; removing a member is Edit group's Cast, as on desktop. */
  canRemoveMember?: boolean;
}) {
  // The desktop cast strip (cast_roster_chip.dart), face for face: a round
  // avatar (the picture, else the initial) ringed when focused, the name
  // under it, Away / Back for a member, GUEST and Promote for a guest.
  const focused = focusedId ?? cast[0]?.id ?? null;
  return (
    <div className="cast-bar">
      <div className="cast-row">
        {cast.map((c) => {
          const isFocused = c.id === focused;
          const awayControl =
            !!onSetAway && !c.isLite && (c.presence === 'withYou' || c.presence === 'away');
          const showPicture = c.hasAvatar && !c.placeholderPortrait && !!c.avatarUrl;
          return (
            <div
              key={c.id}
              className={`cast-chip${isFocused ? ' focused' : ''}${c.isLite ? ' lite' : ''}${c.presence && c.presence !== 'withYou' ? ' away' : ''}`}
            >
              <button className="cast-chip-main" onClick={() => onFocus(c.id)} title={c.name}>
                <span className="cast-face">
                  {showPicture ? (
                    <img src={c.avatarUrl} alt="" />
                  ) : (
                    <span className="cast-initial" aria-hidden>
                      {(c.name || '?').charAt(0)}
                    </span>
                  )}
                  {c.chaos && (
                    <span className="cast-chaos" title={`${c.name} rolls with Chaos Mode`} aria-label="Chaos Mode on">
                      🎲
                    </span>
                  )}
                </span>
                <span className="cast-name">{c.name}</span>
              </button>
              {awayControl && (
                <button
                  className="cast-away"
                  disabled={busy || settling}
                  onClick={() => onSetAway!(c.id, c.presence === 'withYou')}
                  title={c.presence === 'withYou' ? 'Mark as away' : 'Bring back'}
                >
                  {c.presence === 'withYou' ? 'Away' : 'Back'}
                </button>
              )}
              {c.isLite && (
                <>
                  <span className="cast-guest">GUEST</span>
                  <button
                    className="cast-promote"
                    disabled={busy}
                    onClick={() => onCommand(`/promote ${c.name}`)}
                  >
                    Promote
                  </button>
                </>
              )}
            </div>
          );
        })}
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
