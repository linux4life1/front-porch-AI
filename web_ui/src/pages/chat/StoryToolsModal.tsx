// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Turn Into a Story" for the desktop composer's Chat Management folder
// (PR 1a). The same three controls the flat Chat Tools "Our story" fold
// carries — milestones, the group Lead pick, and the to-story button with
// its result line — lifted into a modal so the desktop header can stay the
// window's. The fold stays for phone/tablet untouched.

import { useState } from 'react';
import { api } from '../../api/client';
import { MilestonesPanel } from '../../components/MilestonesPanel';

export function StoryToolsModal({
  onClose,
  focusedId,
  reloadKey,
  roster,
}: {
  onClose: () => void;
  focusedId: string | null;
  reloadKey: number;
  /** Group members with a library id; empty in a 1:1 (no Lead pick). */
  roster: { name: string; dbId: string | null }[];
}) {
  const [storyLead, setStoryLead] = useState('');
  const [storyMsg, setStoryMsg] = useState<string | null>(null);

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <div
        className="sessions-drawer story-modal"
        role="dialog"
        aria-label="Turn Into a Story"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="drawer-head">
          <span>📖 Turn Into a Story</span>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        <MilestonesPanel focusedId={focusedId} reloadKey={reloadKey} />
        {roster.length > 0 && (
          <div className="tool-row">
            <label>
              Lead{' '}
              <select
                data-testid="story-lead"
                aria-label="Story lead"
                value={storyLead}
                onChange={(e) => setStoryLead(e.target.value)}
              >
                {roster.map((c, i) => (
                  <option key={c.dbId ?? i} value={i === 0 ? '' : c.dbId ?? ''}>{c.name}</option>
                ))}
                <option value="persona">You</option>
              </select>
            </label>
          </div>
        )}
        <div className="tool-row">
          <button
            data-testid="story-from-chat"
            onClick={async () => {
              setStoryMsg(null);
              try {
                const r = await api.post<{ id: string; title: string }>(
                  '/api/chat/tools/to-story',
                  storyLead ? { lead: storyLead } : {},
                );
                setStoryMsg(`Created "${r.title}" — open Stories to run it.`);
              } catch {
                setStoryMsg('Needs a chat with a character or a group.');
              }
            }}
          >
            📖 Turn this chat into a story
          </button>
        </div>
        {storyMsg && <p className="muted milestones-empty">{storyMsg}</p>}
      </div>
    </div>
  );
}
