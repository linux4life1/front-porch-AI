// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story studio shell: title with progress, the progress card with Stop,
// the sidebar (a strip on phones), and whichever screen is open. Mirrors the
// desktop StoryDashboardPage shell + StudioSidebar.

import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import type { StoryProject, StoryStatus } from '../../storyTypes';
import { groupThousands, nextUnfinished, ROMAN, wordCount } from './storyShape';
import '../../styles/studio.css';

export type StudioSection =
  | 'overview' | 'structure' | 'write' | 'read' | 'director'
  | 'cast' | 'relationships' | 'lore' | 'log';

const NAV: { key: StudioSection; label: string; group: string; icon: string; path: (id: string) => string }[] = [
  { key: 'overview', label: 'Overview', group: 'Story', icon: '▤', path: (id) => `/stories/${id}` },
  { key: 'structure', label: 'Structure', group: 'Story', icon: '⌁', path: (id) => `/stories/${id}/structure` },
  { key: 'write', label: 'Write', group: 'Story', icon: '✎', path: (id) => `/stories/${id}/write` },
  { key: 'read', label: 'Read', group: 'Story', icon: '▣', path: (id) => `/stories/${id}/read` },
  { key: 'director', label: 'Director', group: 'Story', icon: '☷', path: (id) => `/stories/${id}/director` },
  { key: 'cast', label: 'Cast', group: 'World', icon: '☺', path: (id) => `/stories/${id}/cast` },
  { key: 'relationships', label: 'Relationships', group: 'World', icon: '∞', path: (id) => `/stories/${id}/relationships` },
  { key: 'lore', label: 'Lore & continuity', group: 'World', icon: '✦', path: (id) => `/stories/${id}/lore` },
  { key: 'log', label: 'Run log', group: 'Engine', icon: '≡', path: (id) => `/stories/${id}/log` },
];

export function studioPath(id: string, section: StudioSection): string {
  return NAV.find((n) => n.key === section)!.path(id);
}

function isNew(p: StoryProject, key: StudioSection): boolean {
  switch (key) {
    case 'director': return !p.director_plan;
    case 'relationships': return (p.relationships ?? []).length === 0;
    case 'lore': return (p.continuity ?? []).length === 0;
    case 'log': return p.acts.length === 0;
    default: return false;
  }
}

export function StudioProgress({ status, onStop }: { status: StoryStatus | null; onStop: () => void }) {
  if (!status?.running) return null;
  return (
    <div className="card s-progress" aria-live="polite">
      <div className="spinner small" />
      <div className="s-grow">
        <strong>{status.step || 'Working'}</strong>
        <span className="muted small">{status.status}{status.tokens ? ` · ${status.tokens} tokens` : ''}</span>
      </div>
      <button className="s-btn-quiet" disabled={!!status.stopping} onClick={onStop} data-testid="story-stop">
        {status.stopping ? 'Stopping…' : 'Stop'}
      </button>
    </div>
  );
}

export function StudioShell({
  id, project: p, section, status, error, onStop, children,
}: {
  id: string;
  project: StoryProject;
  section: StudioSection;
  status: StoryStatus | null;
  error?: string;
  onStop: () => void;
  children: ReactNode;
}) {
  const navigate = useNavigate();
  const words = wordCount(p);
  const next = nextUnfinished(p);
  const actLabel = p.acts.length === 0
    ? 'Setting up'
    : `Act ${ROMAN[(next?.act ?? p.acts.length - 1) + 1] ?? ''}`;
  const progress = p.engine_mode === 'studio'
    ? `${groupThousands(words)} / ${groupThousands(p.target_words ?? 80000)} words`
    : `${groupThousands(words)} words`;

  return (
    <div className="studio">
      <div className="studio-head">
        <button className="ghost" onClick={() => navigate('/stories')}>← Stories</button>
        <div>
          <h2>{p.title}</h2>
          <div className="studio-sub">{actLabel} · {progress}</div>
        </div>
        <span className="spacer" />
        {status?.running && (
          <button className="s-btn-quiet" disabled={!!status.stopping} onClick={onStop}>
            {status.stopping ? 'Stopping…' : 'Stop'}
          </button>
        )}
        <button className="ghost small" onClick={() => navigate(`/stories/${id}/setup`)}>Edit setup</button>
      </div>
      <nav className="studio-side" aria-label="Story screens">
        {['Story', 'World', 'Engine'].map((group) => (
          <div key={group} style={{ display: 'contents' }}>
            <div className="h">{group}</div>
            {NAV.filter((n) => n.group === group).map((n) => (
              <button key={n.key} className={`studio-nav${n.key === section ? ' on' : ''}`}
                data-testid={`studio-nav-${n.key}`}
                onClick={() => navigate(n.path(id))}>
                <span aria-hidden="true">{n.icon}</span>{n.label}
                {isNew(p, n.key) && <span className="new">new</span>}
              </button>
            ))}
          </div>
        ))}
      </nav>
      <main className="studio-main">
        <StudioProgress status={status} onStop={onStop} />
        {error && <p className="error">{error}</p>}
        {children}
      </main>
    </div>
  );
}

/** A small pill with one of the shared tones. */
export function Chip({ tone = '', children, title }: { tone?: string; children: ReactNode; title?: string }) {
  return <span className={`s-chip ${tone}`} title={title}>{children}</span>;
}
