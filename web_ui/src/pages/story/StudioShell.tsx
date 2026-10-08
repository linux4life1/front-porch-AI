// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story studio shell (sketch M): the header with its 4px progress bar, the
// sidebar (a strip under 760px) and whichever screen is open. Nothing is ever
// laid over the screen while a run is on; the active section streams in place.
// Mirrors StoryDashboardPage's shell + StudioSidebar on the desktop.

import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import type { StoryProject, StoryStatus } from '../../storyTypes';
import { StudioHeader } from './StudioHeader';
import { orderedScenes, scenesWritten } from './storyShape';
import { useShelfState } from './useShelfState';
import '../../styles/studio.css';

export type StudioSection =
  | 'overview' | 'structure' | 'write' | 'read' | 'director'
  | 'cast' | 'relationships' | 'lore' | 'log';

const NAV: { key: StudioSection; label: string; group: string; path: (id: string) => string }[] = [
  { key: 'overview', label: 'Overview', group: 'Story', path: (id) => `/stories/${id}` },
  { key: 'structure', label: 'Structure', group: 'Story', path: (id) => `/stories/${id}/structure` },
  { key: 'write', label: 'Write', group: 'Story', path: (id) => `/stories/${id}/write` },
  { key: 'read', label: 'Read', group: 'Story', path: (id) => `/stories/${id}/read` },
  { key: 'director', label: 'Director', group: 'Story', path: (id) => `/stories/${id}/director` },
  { key: 'cast', label: 'Cast', group: 'World', path: (id) => `/stories/${id}/cast` },
  { key: 'relationships', label: 'Relationships', group: 'World', path: (id) => `/stories/${id}/relationships` },
  { key: 'lore', label: 'Lore & continuity', group: 'World', path: (id) => `/stories/${id}/lore` },
  { key: 'log', label: 'Run log', group: 'Engine', path: (id) => `/stories/${id}/log` },
];

export function studioPath(id: string, section: StudioSection): string {
  return NAV.find((n) => n.key === section)!.path(id);
}

/** The mono count on a sidebar item: scenes written of planned, cast size, continuity facts. */
export function navCount(p: StoryProject, key: StudioSection): string | null {
  switch (key) {
    case 'structure': {
      const total = orderedScenes(p).length;
      return total > 0 ? `${scenesWritten(p)}/${total}` : null;
    }
    case 'cast': return p.cast.length > 0 ? `${p.cast.length}` : null;
    case 'lore': return (p.continuity ?? []).length > 0 ? `${(p.continuity ?? []).length}` : null;
    default: return null;
  }
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
  const running = status?.running ?? false;
  const shelf = useShelfState(id, p, running, status?.step);
  const fraction = Math.min(Math.max(shelf?.fraction ?? 0, 0), 1);

  return (
    <div className="studio-scope studio">
      <StudioHeader id={id} project={p} shelf={shelf} status={status} onStop={onStop} />
      <div className={`studio-progress${shelf?.done ? ' done' : ''}`} role="progressbar" aria-label="Story progress"
        aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(fraction * 100)}>
        <i style={{ width: `${fraction * 100}%` }} />
      </div>
      <nav className="studio-side" aria-label="Story screens">
        {['Story', 'World', 'Engine'].map((group) => (
          <div key={group} style={{ display: 'contents' }}>
            <div className="h">{group}</div>
            {NAV.filter((n) => n.group === group).map((n) => {
              const count = navCount(p, n.key);
              return (
                <button key={n.key} type="button" className={`studio-nav${n.key === section ? ' on' : ''}`}
                  data-testid={`studio-nav-${n.key}`} aria-current={n.key === section ? 'page' : undefined}
                  onClick={() => navigate(n.path(id))}>
                  {n.label}
                  {count && <span className="cnt">{count}</span>}
                </button>
              );
            })}
          </div>
        ))}
      </nav>
      <main className="studio-main">
        {error && <p className="s-error">{error}</p>}
        {children}
      </main>
    </div>
  );
}

/** What a studio page shows until its project has loaded (or why it could not). */
export function StudioLoading({ error }: { error?: string }) {
  return (
    <div className="studio-scope s-loading">
      {error ? <p className="s-error">{error}</p> : <p className="s-muted">Loading…</p>}
    </div>
  );
}

/** A small pill with one of the shared tones. */
export function Chip({ tone = '', children, title }: { tone?: string; children: ReactNode; title?: string }) {
  return <span className={`s-chip ${tone}`} title={title}>{children}</span>;
}
