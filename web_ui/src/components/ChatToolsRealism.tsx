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
  pocketRemove,
  pocketAdd,
}: {
  t: ToolsState;
  pocketRemove: (section: string, index: number) => void;
  pocketAdd: (section: string, name: string, gift: boolean, correction?: boolean) => void;
}) {
  // `pockets` is null when the feature is OFF (panel absent) and an
  // EMPTY object when it is on with nothing recorded — the panel still
  // renders then, so the first item can be hand-added (desktop parity).
  if (!t.pockets) return null;
  const worn = t.pockets.worn ?? [];
  const carrying = t.pockets.carrying ?? [];
  // Parked in the scene, still theirs — greyed so "not on them" reads
  // at a glance (the desktop sidebar's Set aside group, same rules;
  // the server already filtered out clothing that expired overnight).
  const setAside = t.pockets.set_aside ?? [];
  const label = (i: { name: string; state?: string }) =>
    i.state ? `${i.name} (${i.state})` : i.name;
  return (
    <details className="tool-section" open>
      <summary>Pockets &amp; Wardrobe</summary>
      <div className="tool-body">
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
      </div>
    </details>
  );
}

export function ChatToolsChaos({ t, toggle }: { t: ToolsState; toggle: ToolsToggle }) {
  return (
    <details className="tool-section">
      <summary>Chaos mode{t.chaos.enabled ? ` · ${t.chaos.pressure}%` : ''}</summary>
      <div className="tool-body">
        <Toggle label="Chaos mode" value={t.chaos.enabled} onChange={(v) => toggle('chaos', v)} />
        {t.chaos.enabled && (
          <>
            <div className="stat-line"><span>Pressure</span><span className="muted">{t.chaos.pressure}%{t.chaos.hasPendingEvent ? ' · event ready' : ''}</span></div>
            {t.chaos.adultAllowed && (
              <Toggle label="Allow NSFW events" value={t.chaos.nsfwEnabled} onChange={(v) => toggle('chaosNsfw', v)} />
            )}
            <button
              disabled={t.chaos.hasPendingEvent}
              onClick={() => {
                void api.post('/api/chat/chance-time/spin').catch(() => {});
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
