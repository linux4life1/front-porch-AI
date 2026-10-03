// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The stories shelf: every story as a book, "New story" and "From a chat" as
// the only ways in. Status line and genre line come from the relay verbatim
// (it computes them with the same Dart helpers as the desktop shelf). Web twin
// of lib/ui/pages/story_home_view.dart.

import { useCallback, useEffect, useState, type KeyboardEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import type { StoryListItem } from '../storyTypes';
import { renameStory } from '../hooks/useStory';
import { formatRelativeTime } from './story/relativeTime';
import { ChatSourcePicker } from './story/setup/ChatSourcePicker';
import {
  Avatar, Chip, ConfirmDialog, Dialog, MenuButton, useNarrow, type MenuEntry,
} from './story/setup/primitives';
import { groupThousands } from './story/storyShape';
import '../styles/studio.css';

const message = (e: unknown, fallback: string) => (e instanceof ApiError ? e.message : fallback);

/** Studio amber, Quick plain, or honey "Setup" while the first steps are unfinished. */
function EngineChip({ s }: { s: StoryListItem }) {
  if (s.shelf.setup) return <Chip tone="honey">Setup</Chip>;
  return s.engine === 'studio' ? <Chip tone="amber">Studio</Chip> : <Chip>Quick</Chip>;
}

function ProgressBar({ s }: { s: StoryListItem }) {
  return (
    <div className={`s-bar${s.shelf.done ? ' done' : ''}`} role="progressbar" aria-valuemin={0} aria-valuemax={100}
      aria-valuenow={Math.round(s.shelf.fraction * 100)}>
      <i style={{ width: `${Math.round(s.shelf.fraction * 100)}%` }} />
    </div>
  );
}

/** Enter or Space on the card opens it, like a tap. */
const activate = (open: () => void) => (e: KeyboardEvent) => {
  if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
    e.preventDefault();
    open();
  }
};

export function StoriesPage() {
  const navigate = useNavigate();
  const narrow = useNarrow();
  const [stories, setStories] = useState<StoryListItem[] | null>(null);
  const [error, setError] = useState('');
  const [picking, setPicking] = useState(false);
  const [renaming, setRenaming] = useState<StoryListItem | null>(null);
  const [title, setTitle] = useState('');
  const [deleting, setDeleting] = useState<StoryListItem | null>(null);

  const load = useCallback(() => {
    api.get<{ stories: StoryListItem[] }>('/api/stories')
      .then((r) => setStories([...r.stories].sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt))))
      .catch((e) => setError(message(e, 'Could not load your stories.')));
  }, []);
  useEffect(load, [load]);

  /** Setup still open → the wizard where it stopped; otherwise the studio. */
  const open = (s: StoryListItem) => navigate(s.shelf.setup ? `/stories/${s.id}/setup` : `/stories/${s.id}`);
  const newStory = () => navigate('/stories/new');

  const rename = async () => {
    const target = renaming;
    const next = title.trim();
    setRenaming(null);
    if (!target || !next) return;
    try {
      await renameStory(target.id, next);
      load();
    } catch (e) {
      setError(message(e, 'Could not rename the story.'));
    }
  };

  const remove = async () => {
    const target = deleting;
    setDeleting(null);
    if (!target) return;
    try {
      await api.post(`/api/stories/${target.id}/delete`);
      load();
    } catch (e) {
      setError(message(e, 'Could not delete the story.'));
    }
  };

  const entries = (s: StoryListItem): MenuEntry[] => [
    { label: 'Open', onSelect: () => open(s) },
    { label: 'Read', disabled: s.wordCount <= 0, onSelect: () => navigate(`/stories/${s.id}/read`) },
    { label: 'Rename', onSelect: () => { setTitle(s.title); setRenaming(s); } },
    { label: 'Delete story…', danger: true, divider: true, onSelect: () => setDeleting(s) },
  ];

  const count = stories?.length ?? 0;
  const words = deleting?.wordCount ?? 0;

  return (
    <div className="studio-scope" data-testid="story-shelf">
      <header className="studio-head">
        <span className="t">Porch Stories</span>
        <span className="s">{count === 0 ? 'no stories yet' : `${count} ${count === 1 ? 'story' : 'stories'}`}</span>
        <span className="spacer" />
        {!narrow && (
          <button type="button" className="s-btn-quiet" data-testid="story-from-chat" onClick={() => setPicking(true)}>From a chat</button>
        )}
        <button type="button" className="s-btn-primary" data-testid="story-new" onClick={newStory}>
          + {narrow ? 'New' : 'New story'}
        </button>
      </header>

      <div className="studio-main">
        {error && <p className="s-error" role="alert">{error}</p>}
        {stories === null ? (
          error ? null : <div className="spinner" aria-label="Loading" />
        ) : stories.length === 0 ? (
          <div className="s-card s-empty" style={{ maxWidth: 420, margin: '48px auto 0', width: '100%' }} data-testid="story-empty">
            <b>No stories yet</b>
            <span className="s-muted">Start with an idea, or turn a chat you've had into a book. The bible, the structure and the prose follow.</span>
            <div><button type="button" className="s-btn-primary" onClick={newStory}>New story</button></div>
          </div>
        ) : narrow ? (
          <>
            {stories.map((s) => (
              <div key={s.id} className="s-card tap" role="link" tabIndex={0} data-testid={`story-book-${s.id}`}
                onClick={() => open(s)} onKeyDown={activate(() => open(s))}>
                <div className="s-row nowrap">
                  <Avatar name={s.title} />
                  <div className="s-grow">
                    <b className="s-ell" style={{ display: 'block' }}>{s.title}</b>
                    <span className="s-muted s-small" style={{ display: 'block' }}>{s.shelf.status}</span>
                  </div>
                  <EngineChip s={s} />
                  <MenuButton entries={entries(s)} label="Story actions" />
                </div>
                <ProgressBar s={s} />
              </div>
            ))}
            <button type="button" className="s-btn-ghost" style={{ justifyContent: 'center' }} onClick={() => setPicking(true)}>From a chat…</button>
          </>
        ) : (
          <div className="s-shelf">
            {stories.map((s) => (
              <div key={s.id} className="s-book" role="link" tabIndex={0} data-testid={`story-book-${s.id}`}
                onClick={() => open(s)} onKeyDown={activate(() => open(s))}>
                <div className="s-cover">
                  <span className="ttl">{s.title}</span>
                  <span className="kb"><EngineChip s={s} /></span>
                </div>
                <div className="s-row nowrap" style={{ gap: 4 }}>
                  <b className="s-grow s-ell">{s.title}</b>
                  <MenuButton entries={entries(s)} label="Story actions" />
                </div>
                <span className="s-muted s-small s-ell">{s.genreLine}</span>
                <ProgressBar s={s} />
                <div className="s-row nowrap s-muted s-small">
                  <span className="s-grow s-ell">{s.shelf.status}</span>
                  <span>{formatRelativeTime(s.updatedAt)}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {picking && (
        <ChatSourcePicker onClose={() => setPicking(false)}
          onPick={(fromChat) => { setPicking(false); navigate('/stories/new', { state: { fromChat } }); }} />
      )}
      {renaming && (
        <Dialog title="Rename" onClose={() => setRenaming(null)} actions={(
          <>
            <button type="button" className="s-btn-ghost" onClick={() => setRenaming(null)}>Cancel</button>
            <button type="button" className="s-btn-primary" onClick={() => void rename()}>Rename</button>
          </>
        )}>
          <input type="text" autoFocus placeholder="Title" value={title} data-testid="story-rename"
            onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void rename(); }} />
        </Dialog>
      )}
      {deleting && (
        <ConfirmDialog destructive confirmLabel="Delete" title={`Delete ${deleting.title}?`}
          body={words > 0
            ? `${groupThousands(words)} words, its bible and its run log will be removed. This cannot be undone.`
            : 'Its setup and bible will be removed. This cannot be undone.'}
          onCancel={() => setDeleting(null)} onConfirm={() => void remove()} />
      )}
    </div>
  );
}
