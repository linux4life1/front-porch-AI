// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Moments (docs/design/boons-and-bogies.md §7): the MOMENTS section of the
// Boons & Bogies line and its header dot — the web twin of
// lib/ui/widgets/milestone/moments_section.dart. One read
// (GET /api/chat/tools/growth/moments) feeds both; it re-reads when the
// sidebar's refresh key moves (a reply, a card opening) and after an answer.

import { useCallback, useEffect, useState } from 'react';

import { api } from '../../api/client';
import { postMilestoneAction } from './MilestoneModal';
import type { MilestoneViewJson, MomentsResponse } from './milestoneTypes';

export function useMoments(query: string, refreshKey: unknown, enabled: boolean) {
  const [moments, setMoments] = useState<MilestoneViewJson[]>([]);
  const reload = useCallback(async () => {
    if (!enabled) {
      setMoments([]);
      return;
    }
    try {
      const r = await api.get<MomentsResponse>(`/api/chat/tools/growth/moments${query}`);
      setMoments(r.moments ?? []);
    } catch {
      /* no active chat — the section stays empty */
    }
  }, [query, enabled]);
  useEffect(() => {
    void reload();
  }, [reload, refreshKey]);
  return { moments, reload };
}

/** "2 new" — the unread dot on the Boons & Bogies header. */
export function MomentsUnreadDot({ moments }: { moments: MilestoneViewJson[] }) {
  const unread = moments.filter((m) => !m.seen || m.status === 'pending').length;
  if (unread === 0) return null;
  return <span className="ms-unread">{unread} new</span>;
}

function detail(m: MilestoneViewJson): string {
  return [
    m.text,
    m.statusLabel,
    m.receipt.replace(/^(Seen|Coped) in /, ''),
  ]
    .filter(Boolean)
    .join(' · ');
}

export function MomentsSection({
  moments,
  query,
  onChanged,
}: {
  moments: MilestoneViewJson[];
  query: string;
  onChanged: () => void;
}) {
  const [notice, setNotice] = useState<string | null>(null);
  if (moments.length === 0) return null;
  const act = (
    action: 'milestoneAnswer' | 'milestoneReplay',
    body: Record<string, unknown>,
    owner: string,
  ) =>
    void postMilestoneAction(action, body, query)
      .then((res) => {
        if ((res as { milestoneOutcome?: string } | null)?.milestoneOutcome === 'bogeyCapFull') {
          setNotice(`${owner || 'This character'} already carries three bogies — overcome one first.`);
        } else {
          setNotice(null);
        }
        onChanged();
      })
      .catch(() => {});
  return (
    <div className="bb-group ms-moments">
      <div className="bb-group-head">
        <span>Moments</span>
      </div>
      {notice && <p className="muted small">{notice}</p>}
      {moments.map((m) => {
        const pending = m.status === 'pending';
        const unread = !m.seen || pending;
        return (
          <div key={m.id} className="ms-moment">
            <i className={unread ? 'ms-dot' : 'ms-dot ms-dot-seen'} aria-hidden="true" />
            <div className="ms-moment-what">
              <span>
                {pending && <span className="ms-asks">ASKS</span>}
                {m.title}
              </span>
              <small>{detail(m)}</small>
            </div>
            {pending ? (
              <>
                <button
                  className="ms-pill-btn"
                  onClick={() => act('milestoneAnswer', { momentId: m.id, accept: false }, m.ownerName)}
                >
                  Reject
                </button>
                <button
                  className="ms-pill-btn ms-pill-gold"
                  onClick={() => act('milestoneAnswer', { momentId: m.id, accept: true }, m.ownerName)}
                >
                  Accept
                </button>
              </>
            ) : (
              <button
                className="ms-pill-btn"
                onClick={() => act('milestoneReplay', { momentId: m.id }, m.ownerName)}
              >
                Replay
              </button>
            )}
          </div>
        );
      })}
    </div>
  );
}
