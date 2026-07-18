// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group-only chat settings — gated by the caller on the presence of a group
// block (i.e. a group chat). Turn order is applied live via the /turnorder
// command; the rest save to the group's settings (name / prompts / scenario /
// first message / per-member overrides). Extracted from ChatTools to keep that
// file under the size cap; the directorMode switch is the shared GROUP
// turn-director (unrelated to the realism Director/Verifier).

import { useEffect, useState } from 'react';
import { api } from '../api/client';

export interface GroupBlock {
  name: string;
  turnOrder: string;
  directorMode: boolean;
  systemPrompt: string;
  scenario: string;
  firstMessage: string;
  members: { id: string; name: string; prompt: string }[];
}

export function GroupSettings({
  group,
  groupId,
  onCommand,
  onToggleDirector,
}: {
  group: GroupBlock;
  groupId: string;
  onCommand?: (cmd: string) => void;
  onToggleDirector: (v: boolean) => void;
}) {
  const [systemPrompt, setSystemPrompt] = useState(group.systemPrompt);
  const [scenario, setScenario] = useState(group.scenario);
  const [firstMessage, setFirstMessage] = useState(group.firstMessage);
  const [prompts, setPrompts] = useState<Record<string, string>>(
    Object.fromEntries(group.members.map((m) => [m.id, m.prompt])),
  );
  useEffect(() => {
    setSystemPrompt(group.systemPrompt);
    setScenario(group.scenario);
    setFirstMessage(group.firstMessage);
    setPrompts(Object.fromEntries(group.members.map((m) => [m.id, m.prompt])));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groupId]);

  const save = (fields: Record<string, unknown>) =>
    void api.post(`/api/groups/${groupId}/settings`, fields).catch(() => {});

  return (
    <details className="tool-section">
      <summary>Group settings</summary>
      <div className="tool-body">
        <div className="tool-row">
          <span className="muted small">Turn order:</span>
          <button
            className={group.turnOrder === 'roundRobin' ? 'primary small' : 'small'}
            onClick={() => onCommand?.('/turnorder roundrobin')}
          >
            Round-robin
          </button>
          <button
            className={group.turnOrder === 'random' ? 'primary small' : 'small'}
            onClick={() => onCommand?.('/turnorder random')}
          >
            Random
          </button>
        </div>
        <label className="tool-toggle">
          <span>Director mode</span>
          <input
            type="checkbox"
            checked={group.directorMode}
            onChange={(e) => onToggleDirector(e.target.checked)}
          />
        </label>
        <label>
          Group system prompt
          <textarea rows={3} value={systemPrompt} onChange={(e) => setSystemPrompt(e.target.value)} onBlur={() => save({ systemPrompt })} />
        </label>
        <label>
          Group scenario
          <textarea rows={2} value={scenario} onChange={(e) => setScenario(e.target.value)} onBlur={() => save({ scenario })} />
        </label>
        <label>
          Group first message
          <textarea rows={2} value={firstMessage} onChange={(e) => setFirstMessage(e.target.value)} onBlur={() => save({ firstMessage })} />
        </label>
        <h4 className="section-label">Per-member prompt overrides</h4>
        {group.members.map((m) => (
          <label key={m.id}>
            {m.name}
            <textarea
              rows={2}
              value={prompts[m.id] ?? ''}
              onChange={(e) => setPrompts({ ...prompts, [m.id]: e.target.value })}
              onBlur={() => save({ characterSystemPrompts: prompts })}
              placeholder="Extra instructions just for this member…"
            />
          </label>
        ))}
      </div>
    </details>
  );
}
