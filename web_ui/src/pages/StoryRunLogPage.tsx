// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Run log (sketch U): every model call this story has made, newest first and
// live while a run is on. A row opens the prompt and the reply; Clear asks
// first. Web twin of the desktop RunLogSection.

import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { StoryRunEntry } from '../storyTypes';
import { clearLogCopy } from './story/confirmCopy';
import { RunDialog } from './story/runlog/RunDialog';
import { callsLine, clock, isFailure, roleTone, rowStats, stageLabel, verdictTone } from './story/runlog/runLogShape';
import { useRunLog } from './story/runlog/useRunLog';
import { Segmented } from './story/setup/primitives';
import { Chip, StudioLoading, StudioShell } from './story/StudioShell';
import { useConfirm } from './story/useConfirm';

type Filter = 'all' | 'failures';

export function StoryRunLogPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, stop } = useStory(id);
  const running = status?.running ?? false;
  const log = useRunLog(id, p, running, status?.step, status?.status);
  const [filter, setFilter] = useState<Filter>('all');
  const [opened, setOpened] = useState<StoryRunEntry | null>(null);
  const [failure, setFailure] = useState('');
  const { ask, dialog } = useConfirm();

  if (!p) return <StudioLoading error={error} />;

  const { entries } = log;
  const shown = filter === 'failures' ? entries.filter(isFailure) : entries;
  const clear = () => ask(clearLogCopy(entries.length), async () => {
    try {
      await api.post(`/api/stories/${id}/log/clear`, {});
      setFailure('');
    } catch (e) {
      setFailure(e instanceof ApiError ? e.message : 'The run log could not be cleared');
    }
    log.reload();
  });

  return (
    <StudioShell id={id} project={p} section="log" status={status} error={error} onStop={stop}>
      <div className="s-row">
        <span className="s-muted s-body" data-testid="runlog-count">{callsLine(entries.length)}</span>
        {running && <Chip tone="amber">● live</Chip>}
        <Segmented testid="runlog-filter" options={{ all: 'All', failures: 'Failures' }} selected={filter}
          onSelect={(v) => setFilter(v as Filter)} />
        <button type="button" className="s-btn-ghost" data-testid="runlog-clear" disabled={entries.length === 0 || running} onClick={clear}>Clear…</button>
      </div>
      {(failure || log.error) && <p className="s-error">{failure || log.error}</p>}

      {shown.length > 0 && (
        <section className="s-card s-log-card" data-testid="runlog-list">
          {shown.map((e, i) => {
            const verdict = verdictTone(e.verdict);
            return (
              <button key={`${e.at}-${i}`} type="button" className="s-log-row" onClick={() => setOpened(e)}>
                <span className="s-mono">{clock(e.at)}</span>
                <span className="stage">{stageLabel(e)}</span>
                <span className="meta">
                  <Chip tone={roleTone(e.role)}>{e.role}</Chip>
                  {e.verdict && <Chip tone={verdict}>{e.verdict}</Chip>}
                  <span className="s-mono">{rowStats(e)}</span>
                </span>
              </button>
            );
          })}
        </section>
      )}
      {filter === 'failures' && entries.length > 0 && shown.length === 0 && (
        <span className="s-muted s-small">No failed calls.</span>
      )}

      {opened && <RunDialog entry={opened} onClose={() => setOpened(null)} />}
      {dialog}
    </StudioShell>
  );
}
