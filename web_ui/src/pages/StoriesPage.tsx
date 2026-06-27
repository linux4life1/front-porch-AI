// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Porch Stories library: list projects (genre/mood, granular status, tier badge,
// inline Read + Export popup), create (→ setup wizard), delete. Mirrors the
// desktop home cards.

import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import type { StoryListItem } from '../storyTypes';
import { TIER_LABELS } from '../storyTypes';
import { cardStatus, exportText, exportEpub } from './story/storyUtil';
import '../styles/ws-j.css';

export function StoriesPage() {
  const navigate = useNavigate();
  const [stories, setStories] = useState<StoryListItem[] | null>(null);
  const [error, setError] = useState('');
  const [creating, setCreating] = useState(false);
  const [menuFor, setMenuFor] = useState<string | null>(null);

  const load = () => {
    api.get<{ stories: StoryListItem[] }>('/api/stories')
      .then((r) => setStories(r.stories))
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Failed to load'));
  };
  useEffect(load, []);

  const create = async () => {
    setCreating(true);
    try {
      const r = await api.post<{ id: string }>('/api/stories', { title: 'Untitled Story' });
      navigate(`/stories/${r.id}/setup`);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not create story');
      setCreating(false);
    }
  };

  const del = async (id: string, title: string) => {
    if (!confirm(`Delete "${title}"? This cannot be undone.`)) return;
    try {
      await api.post(`/api/stories/${id}/delete`);
      load();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Delete failed');
    }
  };

  const doExport = async (s: StoryListItem, kind: 'text' | 'markdown' | 'epub') => {
    setMenuFor(null);
    try {
      if (kind === 'epub') await exportEpub(s.id, s.title);
      else await exportText(s.id, kind, s.title);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Export failed');
    }
  };

  return (
    <div className="page">
      <div className="page-head">
        <h2>📖 Porch Stories</h2>
        <button className="primary" onClick={create} disabled={creating}>
          {creating ? 'Creating…' : '＋ New story'}
        </button>
      </div>
      {error && <p className="error">{error}</p>}
      {stories === null ? (
        <div className="spinner" aria-label="Loading" />
      ) : stories.length === 0 ? (
        <p className="muted">No stories yet. Create one to start generating a novel.</p>
      ) : (
        <div className="story-grid">
          {stories.map((s) => (
            <StoryCard
              key={s.id}
              s={s}
              menuOpen={menuFor === s.id}
              onOpen={() => navigate(`/stories/${s.id}`)}
              onRead={() => navigate(`/stories/${s.id}/read`)}
              onDelete={() => del(s.id, s.title)}
              onToggleMenu={() => setMenuFor(menuFor === s.id ? null : s.id)}
              onExport={(k) => doExport(s, k)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function StoryCard({
  s, menuOpen, onOpen, onRead, onDelete, onToggleMenu, onExport,
}: {
  s: StoryListItem;
  menuOpen: boolean;
  onOpen: () => void;
  onRead: () => void;
  onDelete: () => void;
  onToggleMenu: () => void;
  onExport: (kind: 'text' | 'markdown' | 'epub') => void;
}) {
  const menuRef = useRef<HTMLDivElement | null>(null);
  const status = cardStatus(s);
  const stop = (e: React.MouseEvent) => e.stopPropagation();

  return (
    <div className="card story-card" onClick={onOpen}>
      <h3>{s.title}</h3>
      {(s.genre || s.mood) && (
        <p className="muted small">{[s.genre, s.mood].filter(Boolean).join(' • ')}</p>
      )}
      <p className="muted clamp-2">{s.concept || 'No concept yet'}</p>
      <div className="story-status" style={{ color: `var(--story-status-${status.tone})` }}>
        <span>{status.icon}</span>
        <span>{status.label}</span>
      </div>
      <span className="story-tier">{TIER_LABELS[s.tier] || s.tier}</span>
      <div className="story-card-actions" onClick={stop}>
        {s.hasProse && (
          <button className="ghost small" onClick={onRead}>Read 📖</button>
        )}
        <div className="export-pop" ref={menuRef}>
          <button className="ghost small" onClick={onToggleMenu}>Export ▾</button>
          {menuOpen && (
            <div className="export-menu">
              <button onClick={() => onExport('text')}>Download .txt</button>
              <button onClick={() => onExport('markdown')}>Download .md</button>
              <button onClick={() => onExport('epub')}>Download .epub</button>
            </div>
          )}
        </div>
        <button className="ghost small story-del" onClick={onDelete}>Delete</button>
      </div>
    </div>
  );
}
