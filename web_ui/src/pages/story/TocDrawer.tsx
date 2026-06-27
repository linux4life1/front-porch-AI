// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Table-of-contents drawer for the web book reader: title page, acts, and scenes
// with their page numbers and the current location highlighted. Tapping an entry
// jumps the flip-book. Mirrors the desktop reader's end-drawer TOC.

import type { StoryProject } from '../../storyTypes';

export function TocDrawer({
  project, anchors, currentPage, onJump, onClose,
}: {
  project: StoryProject;
  anchors: Record<string, number>;
  currentPage: number;
  onJump: (page: number) => void;
  onClose: () => void;
}) {
  const entry = (label: string, page: number, kind: 'title' | 'act' | 'scene') => (
    <button
      key={`${kind}-${label}-${page}`}
      className={`toc-entry ${kind}${currentPage === page ? ' current' : ''}`}
      onClick={() => { onJump(page); onClose(); }}
    >
      <span>{label}</span>
      <span className="toc-num">{page + 1}</span>
    </button>
  );

  return (
    <>
      <div className="toc-scrim" onClick={onClose} />
      <nav className="toc" aria-label="Table of contents">
        <div className="toc-head">
          <div className="toc-title">{project.title}</div>
          <div className="toc-sub">TABLE OF CONTENTS</div>
        </div>
        <div className="toc-list">
          {entry('Title Page', anchors['title'] ?? 0, 'title')}
          {project.acts.map((act, ai) => {
            const scenes = project.scenes[String(ai)] ?? [];
            return (
              <div key={ai}>
                {entry(`Act ${act.number}: ${act.title}`, anchors[`act:${ai}`] ?? 0, 'act')}
                {scenes.map((sc, si) =>
                  anchors[`scene:${ai}-${si}`] !== undefined
                    ? entry(sc.title || `Scene ${sc.number}`, anchors[`scene:${ai}-${si}`], 'scene')
                    : null,
                )}
              </div>
            );
          })}
        </div>
      </nav>
    </>
  );
}
