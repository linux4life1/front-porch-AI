// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Porch Stories dashboard: list projects, create (→ setup wizard), delete.

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import type { StoryListItem } from '../storyTypes';

export function StoriesPage() {
  const navigate = useNavigate();
  const [stories, setStories] = useState<StoryListItem[] | null>(null);
  const [error, setError] = useState('');
  const [creating, setCreating] = useState(false);

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
            <div key={s.id} className="card story-card" onClick={() => navigate(`/stories/${s.id}`)}>
              <h3>{s.title}</h3>
              <p className="muted clamp-2">{s.concept || 'No concept yet'}</p>
              <div className="story-meta">
                <span>{s.actCount} act{s.actCount === 1 ? '' : 's'}</span>
                {s.hasProse && <span className="chip up">has prose</span>}
              </div>
              <button
                className="ghost small story-del"
                onClick={(e) => { e.stopPropagation(); void del(s.id, s.title); }}
              >
                Delete
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
