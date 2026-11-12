// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chaos, pockets/wardrobe, and NSFW — the realism-adjacent tool sections.
// Scene & time stays in ChatTools.tsx: ChatTools.clock.test.tsx reads that
// file for the clockRunning chevron pin. Exported as three pieces so the
// shell can keep desktop section order (pockets before chaos, NSFW last).

import { api } from '../api/client';
import { PocketAddRow } from './PocketAddRow';
import { Toggle, type ToolsState, type ToolsToggle } from './ChatToolsShared';

export function ChatToolsPockets({
  t,
  toggle,
  pocketRemove,
  pocketAdd,
}: {
  t: ToolsState;
  toggle: ToolsToggle;
  pocketRemove: (section: string, index: number) => void;
  pocketAdd: (section: string, name: string, gift: boolean, correction?: boolean) => void;
}) {
  // v64 (pockets-wardrobe-chat-toggle.md): the switch is the web twin of
  // the desktop's PocketsGateLine. A host that sends the new keys keeps
  // the section UP when the feature is off — the switch is how it turns
  // back on, and "retained, not tracked" is said aloud. An older host
  // sends none: the panel keeps its old absent-when-off shape, so a new
  // PWA on an old app cannot show a switch that does nothing.
  const knows = typeof t.pocketsSwitch === 'boolean';
  if (!t.pockets && !knows) return null;
  const allowed = t.pocketsAllowed !== false;
  const on = typeof t.pocketsSwitch === 'boolean' ? t.pocketsSwitch : true;
  const who = (t.pocketsName ?? 'your character').trim() || 'your character';
  const set = (v: boolean) => {
    // Turning OFF is the guarded direction — the same freeze warning the
    // desktop dialog shows, in the PWA's established window.confirm
    // shape. Dismiss reads No: nothing is posted, the box stays checked.
    if (!v) {
      const ok = window.confirm(
        `Turn off Pockets & Wardrobe for ${who}? There is no catch-up ` +
          'mechanic implemented. If you turn this off, their current ' +
          'inventory and wardrobe will be retained but no longer ' +
          'tracked — changes in the chat will not be reflected when you ' +
          'turn it back on. Are you sure you want to do this?',
      );
      if (!ok) return;
    }
    toggle(t.pocketsMemberId ? 'memberPockets' : 'pockets', v, t.pocketsMemberId ? { id: t.pocketsMemberId } : undefined);
  };
  const worn = t.pockets?.worn ?? [];
  const carrying = t.pockets?.carrying ?? [];
  // Parked in the scene, still theirs — greyed so "not on them" reads
  // at a glance (the desktop sidebar's Set aside group, same rules;
  // the server already filtered out clothing that expired overnight).
  const setAside = t.pockets?.set_aside ?? [];
  const label = (i: { name: string; state?: string }) =>
    i.state ? `${i.name} (${i.state})` : i.name;
  return (
    <details className="tool-section" open>
      <summary>Pockets &amp; Wardrobe</summary>
      <div className="tool-body">
        {knows && (
          // The needs row's shape (ChatTools.tsx): the box greys under a
          // Porch Life veto at the chat's own choice, and the note says
          // the choice is kept.
          <label className="tool-toggle">
            <span>Pockets &amp; Wardrobe</span>
            <input
              type="checkbox"
              aria-label="Pockets & Wardrobe"
              checked={on}
              disabled={!allowed}
              onChange={(e) => set(e.target.checked)}
            />
          </label>
        )}
        {knows && !allowed && (
          <div className="muted small">
            Off in Porch Life, so no chat tracks pockets. This chat&apos;s choice
            is kept.
          </div>
        )}
        {knows && allowed && !on && (
          <div className="muted small">
            {who}&apos;s inventory is retained, not tracked. Turn it back
            on to follow the story again.
          </div>
        )}
        {t.pockets && (
          <>
            <div className="muted small side-quest-label">Wearing</div>
            <div className="pocket-items">
              {worn.length === 0 ? (
                <span className="pocket-empty">Put clothes on</span>
              ) : (
                worn.map((i, n) => (
                  <span className="pocket-item" key={`w${n}`}>
                    {label(i)}
                    <button
                      className="pocket-x"
                      title="Remove from the record"
                      onClick={() => pocketRemove('worn', n)}
                    >
                      ×
                    </button>
                  </span>
                ))
              )}
            </div>
            {carrying.length > 0 && (
              <>
                <div className="muted small side-quest-label">Carrying</div>
                <div className="pocket-items">
                  {carrying.map((i, n) => (
                    <span className="pocket-item" key={`c${n}`}>
                      {label(i)}
                      <button
                        className="pocket-x"
                        title="Remove from the record"
                        onClick={() => pocketRemove('carrying', n)}
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              </>
            )}
            {setAside.length > 0 && (
              <>
                <div className="muted small side-quest-label">Set aside</div>
                <div className="pocket-items">
                  {setAside.map((i, n) => (
                    <span className="pocket-item pocket-item-aside" key={`s${n}`}>
                      {label(i)}
                      <button
                        className="pocket-x"
                        title="Remove from the record"
                        onClick={() => pocketRemove('set_aside', n)}
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              </>
            )}
            <PocketAddRow onAdd={pocketAdd} />
          </>
        )}
      </div>
    </details>
  );
}

// PR 5b (docs/design/chaos-per-character.md): in a group the snapshot's
// chaos block speaks for the FOCUSED member — the header names them, the
// toggles and the spin carry their id, and an event belongs to them alone.
// Without a member id this is the 1:1 chat-level card, unchanged.
export function ChatToolsChaos({ t, toggle }: { t: ToolsState; toggle: ToolsToggle }) {
  const mid = t.chaos.memberId ?? null;
  const who = mid ? t.chaos.cast?.find((c) => c.memberId === mid)?.name ?? null : null;
  return (
    <details className="tool-section">
      <summary>
        Chaos mode{who ? ` · ${who}` : ''}{t.chaos.enabled ? ` · ${t.chaos.pressure}%` : ''}
      </summary>
      <div className="tool-body">
        <Toggle
          label="Chaos mode"
          value={t.chaos.enabled}
          onChange={(v) => toggle(mid ? 'memberChaos' : 'chaos', v, mid ? { id: mid } : undefined)}
        />
        {t.chaos.enabled && (
          <>
            <div className="stat-line"><span>Pressure</span><span className="muted">{t.chaos.pressure}%{t.chaos.hasPendingEvent ? ' · event ready' : ''}</span></div>
            {t.chaos.adultAllowed && (
              <Toggle
                label="Allow NSFW events"
                value={t.chaos.nsfwEnabled}
                onChange={(v) =>
                  toggle(mid ? 'memberChaosNsfw' : 'chaosNsfw', v, mid ? { id: mid } : undefined)
                }
              />
            )}
            <button
              disabled={t.chaos.hasPendingEvent}
              onClick={() => {
                void api.post('/api/chat/chance-time/spin', mid ? { memberId: mid } : {}).catch(() => {});
              }}
            >
              {t.chaos.hasPendingEvent ? 'EVENT PENDING' : 'SPIN NOW'}
            </button>
            <div className="stat-line">
              <span className="muted">
                {(t.chaos.cooldownTurns ?? 0) > 0
                  ? `Settling down: no events for ${t.chaos.cooldownTurns} more ${t.chaos.cooldownTurns === 1 ? 'message' : 'messages'}.`
                  : `Base: ${t.chaos.base ?? 5}% · +${t.chaos.growth ?? 5}% per turn · cap: 100%`}
              </span>
            </div>
          </>
        )}
      </div>
    </details>
  );
}

// This chat's own Afterglow switch, shown while Porch Life (with 18+) allows
// Afterglow, as on the desktop's Afterglow line; Lust and recovery show while
// it runs. An older desktop sends no afterglowAllowed: the section then shows
// only while Afterglow runs, with no switch. Like the desktop's Afterglow line,
// it is absent while the chat's Realism is off.
export function ChatToolsNsfw({ t, toggle }: { t: ToolsState; toggle: ToolsToggle }) {
  if (!t.realismEnabled) return null;
  const allowed = t.nsfw.afterglowAllowed;
  if (!allowed && !t.nsfw.cooldownEnabled) return null;
  return (
    <details className="tool-section">
      <summary>Afterglow</summary>
      <div className="tool-body">
        {allowed && (
          <Toggle
            label="Afterglow"
            value={t.nsfw.afterglowSwitch ?? t.nsfw.cooldownEnabled}
            onChange={(v) => toggle('nsfwCooldown', v)}
          />
        )}
        {/* In a group, each member's own switch, while the chat's is on
            (desktop Group Settings → Realism, each member's card). */}
        {allowed && t.nsfw.afterglowSwitch && (t.nsfw.members ?? []).map((m) => (
          <Toggle
            key={m.id}
            label={m.name}
            value={m.afterglow}
            onChange={(v) => toggle('memberAfterglow', v, { id: m.id })}
          />
        ))}
        {t.nsfw.cooldownEnabled && (
          <div className="stat-line"><span>Lust</span><span className="muted">{t.nsfw.arousalTier} · {t.nsfw.arousalLevel}</span></div>
        )}
        {t.nsfw.cooldownEnabled && t.nsfw.refractoryMinutesRemaining > 0 && (
          <div className="stat-line"><span className="muted">{t.nsfw.refractoryLabel}</span></div>
        )}
      </div>
    </details>
  );
}
