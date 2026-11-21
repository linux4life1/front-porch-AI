// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unified cast roster for the chat — the web mirror of Rawhide's single
// participant roster (one chat, changing cast). Shows every present speaker
// (host + scene guests in 1:1; members in a group), lets you focus one to
// scope the sidebar, and exposes the cast actions. Actions are driven by the
// in-chat slash commands (which route through ChatService), so behavior matches
// the desktop exactly.

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { placeInSafeArea } from '../utils/safeArea';

export interface CastMember {
  id: string;
  dbId: string | null;
  name: string;
  isHost: boolean;
  isLite: boolean;
  realismEnabled: boolean;
  emotion: string | null;
  isNext: boolean;
  /** Held for the next turn by the user (chip Next pill / Director cue),
   *  not the rotation preview. Additive; absent = not held. */
  queued?: boolean;
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

/** Right-click / hold menu, the desktop chip menu's twin. Bonus shortcut:
 *  the chip itself carries the Next pill, so nothing here is hidden-only. */
function ChipMenu({
  member,
  x,
  y,
  busy,
  onQueue,
  onAway,
  onPromote,
  onClose,
}: {
  member: CastMember;
  x: number;
  y: number;
  busy: boolean;
  onQueue: () => void;
  onAway: (away: boolean) => void;
  onPromote: () => void;
  onClose: () => void;
}) {
  useEffect(() => {
    const off = () => onClose();
    window.addEventListener('click', off);
    window.addEventListener('keydown', off);
    return () => {
      window.removeEventListener('click', off);
      window.removeEventListener('keydown', off);
    };
  }, [onClose]);
  // Opened at the finger; moved once it has a size so it never runs off an
  // edge or under the notch or home bar.
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState({ left: x, top: y });
  useLayoutEffect(() => {
    const box = ref.current?.getBoundingClientRect();
    if (box) setPos(placeInSafeArea(x, y, box.width, box.height));
  }, [x, y]);
  return (
    <div
      ref={ref}
      className="cast-menu"
      style={pos}
      onClick={(e) => e.stopPropagation()}
    >
      <div className="cast-menu-head">{member.name}</div>
      <button onClick={onQueue} disabled={busy}>
        {member.queued ? 'Cancel queued turn' : 'Queue to speak next'}
      </button>
      {member.presence === 'withYou' && !member.isLite && (
        <button onClick={() => onAway(true)} disabled={busy}>
          Send away
        </button>
      )}
      {member.presence === 'away' && !member.isLite && (
        <button onClick={() => onAway(false)} disabled={busy}>
          Bring back
        </button>
      )}
      {member.isLite && (
        <button onClick={onPromote} disabled={busy}>
          Promote to full member
        </button>
      )}
    </div>
  );
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
  onQueue,
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
  /** A group member's Away / Back, reachable from the chip's menu. */
  onSetAway?: (id: string, away: boolean) => void;
  /** Hold a member (full or lite) for the next turn; false cancels.
   *  Desktop's Next pill, same slot. Absent = no pill (older server). */
  onQueue?: (id: string, queue: boolean) => void;
  /** Kept for callers; removing a member is Edit group's Cast, as on desktop. */
  canRemoveMember?: boolean;
}) {
  // The desktop cast strip (cast_roster_chip.dart), face for face: a round
  // avatar (the picture, else the initial) ringed when focused and ringed
  // amber when queued, the name, the honest presence word (status only —
  // the toggle moved to the menu), then Promote for a guest and the Next
  // pill last: the hold sits at one height for every face. The GUEST
  // label is gone: the wider chip with a Promote button is the guest's
  // own sign.
  const focused = focusedId ?? cast[0]?.id ?? null;
  const [menu, setMenu] = useState<{ member: CastMember; x: number; y: number } | null>(null);
  // Phone twin of desktop's onLongPress: iOS Safari fires contextmenu
  // late or not at all, so hold a finger on the face to open the menu.
  // A drag (cast-row scroll) cancels; a fired hold swallows the click
  // that release would otherwise deliver, so focus does not ride along.
  const HOLD_MS = 500;
  const HOLD_MOVE_PX = 10;
  const holdTimer = useRef<number | null>(null);
  const holdFired = useRef(false);
  const holdStart = useRef<{ x: number; y: number } | null>(null);
  const clearHold = () => {
    if (holdTimer.current !== null) window.clearTimeout(holdTimer.current);
    holdTimer.current = null;
    holdStart.current = null;
  };
  useEffect(() => clearHold, []);
  return (
    <div className="cast-bar">
      <div className="cast-row">
        {cast.map((c) => {
          const isFocused = c.id === focused;
          const showPicture = c.hasAvatar && !c.placeholderPortrait && !!c.avatarUrl;
          const showWord = !c.isLite && !!c.presence && onSetAway !== undefined;
          const canQueue = !!onQueue;
          return (
            <div
              key={c.id}
              className={`cast-chip${isFocused ? ' focused' : ''}${c.isLite ? ' lite' : ''}${
                c.presence && c.presence !== 'withYou' ? ' away' : ''
              }${c.queued ? ' queued' : ''}`}
              onContextMenu={(e) => {
                e.preventDefault();
                setMenu({ member: c, x: e.clientX, y: e.clientY });
              }}
              onPointerDown={(e) => {
                if (e.pointerType !== 'touch') return;
                // A long-press whose release produced no click (iOS
                // callout eats it) must not leave the suppression flag
                // armed for the NEXT chip the user taps.
                holdFired.current = false;
                const { clientX: x, clientY: y } = e;
                clearHold();
                holdStart.current = { x, y };
                holdTimer.current = window.setTimeout(() => {
                  holdTimer.current = null;
                  holdStart.current = null;
                  holdFired.current = true;
                  setMenu({ member: c, x, y });
                }, HOLD_MS);
              }}
              onPointerMove={(e) => {
                const start = holdStart.current;
                if (!start) return;
                if (
                  Math.abs(e.clientX - start.x) > HOLD_MOVE_PX ||
                  Math.abs(e.clientY - start.y) > HOLD_MOVE_PX
                ) {
                  clearHold();
                }
              }}
              onPointerUp={clearHold}
              onPointerCancel={clearHold}
              onClickCapture={(e) => {
                if (holdFired.current) {
                  holdFired.current = false;
                  e.stopPropagation();
                }
              }}
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
              {showWord && (
                <span
                  className={`cast-word ${c.presence === 'withYou' ? 'here' : 'gone'}`}
                  title="Status only — right-click (or long-press) to send away or bring back"
                >
                  {c.presence === 'withYou' ? 'With you' : c.presence === 'away' ? 'Away' : 'At work'}
                </span>
              )}
              {c.isLite && (
                <button
                  className="cast-promote"
                  disabled={busy}
                  onClick={() => onCommand(`/promote ${c.name}`)}
                >
                  Promote
                </button>
              )}
              {canQueue && (
                <button
                  className={`cast-next${c.queued ? ' on' : ''}`}
                  onClick={() => onQueue!(c.id, !c.queued)}
                  title={c.queued ? 'Queued to speak next — tap to cancel' : `Queue ${c.name} to answer the next turn`}
                >
                  {c.queued ? '✓ NEXT' : '⏭ Next'}
                </button>
              )}
            </div>
          );
        })}
      </div>

      {menu && (
        <ChipMenu
          member={menu.member}
          x={menu.x}
          y={menu.y}
          busy={busy || settling}
          onQueue={() => {
            onQueue?.(menu.member.id, !menu.member.queued);
            setMenu(null);
          }}
          onAway={(away) => {
            onSetAway?.(menu.member.id, away);
            setMenu(null);
          }}
          onPromote={() => {
            onCommand(`/promote ${menu.member.name}`);
            setMenu(null);
          }}
          onClose={() => setMenu(null)}
        />
      )}

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
