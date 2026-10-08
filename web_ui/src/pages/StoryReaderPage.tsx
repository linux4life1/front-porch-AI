// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Read (sketch P): a section of the studio, not a separate route. The sidebar
// folds away behind ☰ to give the book room; one bar (Book | Scroll, Read
// aloud, Contents, ⋯) serves both the paged book and the continuous scroll, and
// the story remembers which. Web twin of the desktop StoryReaderPage.

import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';
import { BookReader } from './story/BookReader';
import type { ReaderChrome, ReaderMode } from './story/ReaderBar';
import { ScrollReader } from './story/ScrollReader';
import { StudioLoading, StudioShell } from './story/StudioShell';
import { exportText } from './story/storyUtil';
import { useAmbient } from './story/useAmbient';
import '../styles/ws-j.css';

export function StoryReaderPage() {
  const { id = '' } = useParams();
  const { project, status, error, stop, reload } = useStory(id);
  const ambient = useAmbient();
  // Reading starts with the sidebar folded; ☰ brings it back.
  const [sideShown, setSideShown] = useState(false);
  const [problem, setProblem] = useState('');

  if (!project) return <StudioLoading error={error} />;

  const mode: ReaderMode = project.reader_mode === 'scroll' ? 'scroll' : 'book';
  const failure = (e: unknown, fallback: string) => (e instanceof ApiError ? e.message : fallback);
  const chrome: ReaderChrome = {
    title: project.title,
    mode,
    onMode: async (m) => {
      if (m === mode) return;
      try {
        await api.post(`/api/stories/${id}/reading-position`, { mode: m });
        reload();
      } catch (e) {
        setProblem(failure(e, 'The reading mode could not be changed'));
      }
    },
    onToggleSidebar: () => setSideShown((shown) => !shown),
    ambient,
    onExport: async () => {
      try {
        await exportText(id, 'markdown', project.title);
      } catch (e) {
        setProblem(failure(e, 'The text could not be exported'));
      }
    },
    problem,
    onDismissProblem: () => setProblem(''),
  };

  return (
    <StudioShell id={id} project={project} section="read" status={status} error={error} onStop={stop}>
      <div className="s-reader" data-testid="studio-read" data-side={sideShown ? 'shown' : 'hidden'}>
        {mode === 'scroll'
          ? <ScrollReader key="scroll" id={id} project={project} chrome={chrome} />
          : <BookReader key="book" id={id} project={project} chrome={chrome} />}
        {ambient.element}
      </div>
    </StudioShell>
  );
}
