// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Overview (sketch M): where the story is and what is next, then the bible with
// inline edits, the cast strip, the chat card, the engine card and the story so
// far. Web twin of the desktop StoryDashboardPage's Overview section.

import { useEffect, useRef } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { autopilotCopy, redistillCopy, regenerateBibleCopy, rewriteArcCopy } from './story/confirmCopy';
import { BibleCard } from './story/overview/BibleCard';
import { CastCard, ChatCard, EngineCard, SoFarCard } from './story/overview/SideCards';
import { UpNextCard } from './story/overview/UpNextCard';
import { upNextFor, type UpNextAction } from './story/overview/upNext';
import { StudioLoading, StudioShell, studioPath } from './story/StudioShell';
import { lensNameFor, useLenses } from './story/structure/LensParts';
import { useConfirm } from './story/useConfirm';

export function StoryDashboardPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run, stop, save } = useStory(id);
  const lenses = useLenses();
  const { ask, dialog } = useConfirm();
  // Building the bible first distills the chat; the second stage waits here until the first has finished.
  const queued = useRef<string | null>(null);

  useEffect(() => { if (error) queued.current = null; }, [error]);
  useEffect(() => {
    if (status?.running) return;
    const stage = queued.current;
    if (!stage) return;
    queued.current = null;
    void run(stage);
  }, [status?.running, run]);

  if (!p) return <StudioLoading error={error} />;

  const running = status?.running ?? false;
  const up = upNextFor(p, running, status?.status ?? '', (lens) => lensNameFor(p, lenses, lens));

  const buildBible = () => {
    const distillFirst = p.use_chat_history && p.chat_history_character_ids.length > 0 && !p.distilled_timeline;
    if (distillFirst) {
      queued.current = 'story-architect';
      void run('chat-distiller');
    } else {
      void run('story-architect');
    }
  };

  const act: Record<UpNextAction, () => void> = {
    bible: buildBible,
    acts: () => { void run('act-structure'); },
    continue: () => { void run('write-next'); },
    read: () => navigate(studioPath(id, 'read')),
  };

  const redistill = () => ask(redistillCopy, async () => {
    // The old timeline goes first so the distiller starts from the chat again.
    if (await save({ distilled_timeline: '' })) void run('chat-distiller');
  });

  return (
    <StudioShell id={id} project={p} section="overview" status={status} error={error} onStop={stop}>
      <div className="s-col" style={{ gap: 12 }} data-testid="studio-overview">
        <UpNextCard up={up} running={running} onAction={act[up.action]}
          onAutopilot={() => ask(autopilotCopy(p), () => { void run('autopilot'); })} />
        <div className="s-over-cols">
          <BibleCard p={p} running={running} onSave={(patch) => { void save(patch); }}
            onRegenerate={() => ask(regenerateBibleCopy(p), buildBible)}
            onRewriteArc={p.engine_mode === 'studio' && p.cast.length > 0
              ? () => ask(rewriteArcCopy(p), () => { void run('story-arc'); })
              : undefined} />
          <div className="s-col" style={{ gap: 12 }}>
            <CastCard id={id} p={p} onOpen={() => navigate(studioPath(id, 'cast'))} />
            {p.use_chat_history && <ChatCard p={p} running={running} onRedistill={redistill} />}
            <EngineCard p={p} onChange={() => navigate(`/stories/${id}/setup`)} />
            <SoFarCard p={p} onOpen={() => navigate(studioPath(id, 'lore'))} />
          </div>
        </div>
      </div>
      {dialog}
    </StudioShell>
  );
}
