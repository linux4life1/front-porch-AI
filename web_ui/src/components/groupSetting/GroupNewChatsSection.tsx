// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings' Realism, Needs and Inherit for the group's NEW chats, and
// the web twin of the desktop Edit Group notice for a group made from a 1:1
// before forks saved that chat's settings. Each switch saves at once, as the
// rest of web Group Settings does, so "Use the chat's settings" saves too.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { useAdultFlags } from '../realism/useAdultThemes';

export interface ForkSource {
  hostName: string | null;
  realismMissing: boolean;
  needsOn: boolean;
  meet: string | null;
}

export interface NewChatsState {
  realism: boolean;
  needs: boolean;
  /** Porch Life's Needs; false greys the switch at the group's own choice
   *  (absent from an older app: allowed). */
  needsAllowed?: boolean;
  /** How new chats start Afterglow (absent on an older desktop). */
  afterglow?: boolean;
  inherit: boolean;
  forkSource: ForkSource | null;
}

/** What a new chat would be missing, as the desktop notice words it. */
export function forkGapLine(s: ForkSource): string {
  const gaps = [
    ...(s.realismMissing ? [`Realism${s.needsOn ? ' and Needs' : ''} off`] : []),
    ...(s.meet ? ['no world'] : []),
  ];
  return `Its settings for new chats were never filled in, so a new chat would start with ${gaps.join(' and ')}. The chats you have now aren't affected.`;
}

export function GroupNewChatsSection({
  groupId,
  onWorldsChanged,
}: {
  groupId: string;
  /** "Use the chat's settings" can set where new chats meet. */
  onWorldsChanged?: () => void;
}) {
  const [state, setState] = useState<NewChatsState | null>(null);
  // Porch Life (with 18+) allows Afterglow: its switch for new chats shows.
  const { afterglow: afterglowAllowed } = useAdultFlags();
  const [dismissed, setDismissed] = useState(false);
  const [saveError, setSaveError] = useState('');

  useEffect(() => {
    let live = true;
    Promise.resolve()
      .then(() => api.get<NewChatsState>(`/api/groups/${groupId}/new-chats`))
      .then((s) => {
        if (live && s && typeof s.realism === 'boolean') setState(s);
      })
      .catch((e) => console.warn('[group] new-chat settings unavailable', e));
    return () => {
      live = false;
    };
  }, [groupId]);

  // A switch moves as soon as it is tapped; the saved state replaces it when
  // the relay answers, and a failed save puts the old state back.
  const save = (body: Record<string, boolean>, worldsMayChange = false) => {
    const before = state;
    if (before && !body.useForkSource) setState({ ...before, ...body });
    void api
      .post<NewChatsState>(`/api/groups/${groupId}/new-chats`, body)
      .then((s) => {
        setSaveError('');
        if (s && typeof s.realism === 'boolean') setState(s);
        if (worldsMayChange) onWorldsChanged?.();
      })
      .catch((e) => {
        console.warn('[group] new-chat settings save failed', e);
        if (before) setState(before);
        setSaveError('Could not save the settings for new chats. Try again.');
      });
  };

  if (!state) return null;
  const source = dismissed ? null : state.forkSource;
  const host = source?.hostName;
  return (
    <div className="gs-section" data-testid="group-new-chats-section">
      {source && (
        <div className="gs-banner" role="status" data-testid="group-fork-notice">
          <strong>
            {host
              ? `This group started from your chat with ${host}.`
              : 'This group started from a 1:1 chat.'}
          </strong>
          {forkGapLine(source)}
          <span className="gs-heading gs-fork-heading">Filled in from that chat</span>
          {source.realismMissing && (
            <div className="gs-fork-row">
              Realism on · Needs {source.needsOn ? 'on' : 'off'}
              <small>Neutral starting values for every member</small>
            </div>
          )}
          {source.meet && (
            <div className="gs-fork-row">
              {source.meet}
              <small>The world the chat is in</small>
            </div>
          )}
          <div className="gs-fork-actions">
            <button type="button" className="small" onClick={() => setDismissed(true)}>
              Leave as is
            </button>
            <button
              type="button"
              className="primary small"
              onClick={() => save({ useForkSource: true }, source.meet != null)}
            >
              Use the chat's settings
            </button>
          </div>
        </div>
      )}
      <h4 className="section-label">
        Realism for new chats <span className="gs-chip">New chats</span>
      </h4>
      <p className="muted small">
        New chats of this group start with these. Each chat keeps its own switches once it has
        started.
      </p>
      {saveError && (
        <p className="error" role="alert">
          {saveError}
        </p>
      )}
      <label className="tool-toggle">
        <span>Realism Engine</span>
        <input
          type="checkbox"
          checked={state.realism}
          onChange={(e) => save({ realism: e.target.checked })}
        />
      </label>
      <label className="tool-toggle">
        <span>Needs</span>
        <input
          type="checkbox"
          checked={state.realism && state.needs}
          disabled={!state.realism || state.needsAllowed === false}
          onChange={(e) => save({ needs: e.target.checked })}
        />
      </label>
      {state.realism && state.needsAllowed === false && (
        <p className="muted small" data-testid="group-needs-off-note">
          Off in Porch Life, so no chat runs Needs. This group&apos;s choice for new chats is kept.
        </p>
      )}
      {afterglowAllowed && state.realism && state.afterglow !== undefined && (
        <label className="tool-toggle">
          <span>
            Afterglow
            <small className="muted gs-sub">
              Lust and recovery in new chats. Chats you already have keep their own switch.
            </small>
          </span>
          <input
            type="checkbox"
            checked={state.afterglow}
            onChange={(e) => save({ afterglow: e.target.checked })}
          />
        </label>
      )}
      <label className="tool-toggle">
        <span>
          {source && host ? `Read ${host}'s lorebook` : 'Inherit character & world lorebooks'}
          <small className="muted gs-sub">
            Turns on Inherit. Chats of this group you have open start reading it too.
          </small>
        </span>
        <input
          type="checkbox"
          checked={state.inherit}
          onChange={(e) => save({ inherit: e.target.checked })}
        />
      </label>
    </div>
  );
}
