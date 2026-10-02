// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reader shell: loads the project and shows it as a paginated book or as a
// continuous scroll with chapter headings; the story remembers which.
// Mirrors the desktop StoryReaderPage.

import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import { BookReader } from './story/BookReader';
import { ScrollReader } from './story/ScrollReader';
import '../styles/ws-j.css';
import '../styles/studio.css';

export function StoryReaderPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project, error, reload } = useStory(id);

  if (!project) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const mode = project.reader_mode === 'scroll' ? 'scroll' : 'book';
  const setMode = async (m: 'book' | 'scroll') => {
    await api.post(`/api/stories/${id}/reading-position`, { mode: m });
    reload();
  };
  const toggle = (
    <div className="s-seg" data-testid="reader-mode">
      <button className={mode === 'book' ? 'on' : ''} onClick={() => setMode('book')}>Book</button>
      <button className={mode === 'scroll' ? 'on' : ''} onClick={() => setMode('scroll')}>Scroll</button>
    </div>
  );

  return (
    <div className="page">
      {mode === 'scroll' ? (
        <ScrollReader id={id} project={project} bar={(
          <div className="reader-bar">
            <button className="ghost" onClick={() => navigate(`/stories/${id}`)}>← {project.title}</button>
            <h2>{project.title}</h2>
            {toggle}
          </div>
        )} />
      ) : (
        <BookReader id={id} project={project} modeToggle={toggle} />
      )}
    </div>
  );
}
