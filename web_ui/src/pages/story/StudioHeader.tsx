// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The studio header (sketch M): ← Stories, the title (tap to rename) with where
// the story stands, the one Stop while a run is on, Setup, and ⋯ (exports,
// Rename, Delete). Web twin of _buildHeader in story_dashboard_page.shell.dart.
// Under 760px the buttons drop to their own row under the title.

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../../api/client';
import { renameStory } from '../../hooks/useStory';
import type { StoryProject, StoryShelfState, StoryStatus } from '../../storyTypes';
import { deleteStoryCopy } from './confirmCopy';
import { FieldsDialog } from './FieldsDialog';
import { MenuButton } from './setup/primitives';
import { headerSubtitle } from './useShelfState';
import { useConfirm } from './useConfirm';
import { useStoryExports } from './useStoryExports';
import { wordCount } from './storyShape';

export function StudioHeader({
  id, project: p, shelf, status, onStop,
}: {
  id: string;
  project: StoryProject;
  shelf: StoryShelfState | null;
  status: StoryStatus | null;
  onStop: () => void;
}) {
  const navigate = useNavigate();
  const [renaming, setRenaming] = useState(false);
  const [failure, setFailure] = useState('');
  const { ask, dialog } = useConfirm();
  const exports = useStoryExports(id, p.title);
  const running = status?.running ?? false;
  const words = wordCount(p);

  const problem = failure || exports.error;
  const dismiss = () => { setFailure(''); exports.clearError(); };

  const remove = () => ask(deleteStoryCopy(p, words), async () => {
    try {
      await api.post(`/api/stories/${id}/delete`, {});
      navigate('/stories', { replace: true });
    } catch (e) {
      setFailure(e instanceof ApiError ? e.message : 'The story could not be deleted');
    }
  });

  const rename = async (title: string) => {
    setRenaming(false);
    if (title === '' || title === p.title) return;
    try {
      await renameStory(id, title);
    } catch (e) {
      setFailure(e instanceof ApiError ? e.message : 'The story could not be renamed');
    }
  };

  return (
    <div className="studio-head">
      <button type="button" className="s-btn-ghost" data-testid="studio-back" onClick={() => navigate('/stories')}>← Stories</button>
      <div className="studio-titles">
        <h2 className="t s-ell">
          <button type="button" className="studio-title-btn" data-testid="studio-title" disabled={running}
            title={running ? undefined : 'Rename'} onClick={() => setRenaming(true)}>{p.title}</button>
        </h2>
        <div className="s s-ell">{headerSubtitle(shelf, running, p)}</div>
      </div>
      <div className="studio-actions">
        {running && (
          <>
            <span className="s-chip amber" aria-live="polite">
              {status?.stopping ? 'Stopping after this step…' : `● ${status?.step || 'Working'}`}
            </span>
            <button type="button" className="s-btn-quiet" data-testid="story-stop" disabled={!!status?.stopping} onClick={onStop}>Stop</button>
          </>
        )}
        {exports.compiling && (
          <>
            <span className="s-chip honey">Exporting audiobook {Math.round(exports.progress * 100)}%</span>
            <button type="button" className="s-btn-ghost" onClick={exports.abort}>Abort</button>
          </>
        )}
        <button type="button" className="s-btn-ghost" data-testid="studio-setup" disabled={running}
          onClick={() => navigate(`/stories/${id}/setup`)}>Setup</button>
        <MenuButton testid="studio-menu" entries={[
          { label: 'Export eBook (.epub)', disabled: words === 0, onSelect: exports.epub },
          { label: 'Export audiobook (.wav)', disabled: words === 0 || exports.compiling, onSelect: exports.audiobook },
          { label: 'Export text (.md)', disabled: words === 0, onSelect: exports.markdown },
          { label: 'Rename', divider: true, disabled: running, onSelect: () => setRenaming(true) },
          { label: 'Delete story…', danger: true, disabled: running, onSelect: remove },
        ]} />
      </div>
      {problem && (
        <div className="studio-problem s-row" role="alert">
          <span className="s-error">{problem}</span>
          <button type="button" className="s-btn-ghost" onClick={dismiss}>Dismiss</button>
        </div>
      )}
      {renaming && (
        <FieldsDialog title="Rename" confirmLabel="Rename" required="title"
          fields={[{ key: 'title', hint: 'Title', value: p.title, testid: 'story-rename' }]}
          onSubmit={(v) => { void rename(v.title); }} onCancel={() => setRenaming(false)} />
      )}
      {dialog}
    </div>
  );
}
