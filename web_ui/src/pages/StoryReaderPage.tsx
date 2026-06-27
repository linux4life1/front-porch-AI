// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reader shell: loads the project and hands it to the paginated BookReader (paper
// book, prev/next, TOC, reading-progress, read-to-me, ambient). Mirrors the
// desktop StoryReaderPage's immersive reader, web-native.

import { useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { BookReader } from './story/BookReader';
import '../styles/ws-j.css';

export function StoryReaderPage() {
  const { id = '' } = useParams();
  const { project, error } = useStory(id);

  if (!project) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }

  return (
    <div className="page">
      <BookReader id={id} project={project} />
    </div>
  );
}
