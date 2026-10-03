// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The reader bar (sketch P), one for Book and Scroll: ☰ (folds the studio
// sidebar), the title, Book | Scroll, where you are, Read aloud, Contents and ⋯
// (ambient sound, Export text). Under it, the status line: what the narrator is
// doing, or why it is not (voice off). Web twin of _studioBar in
// story_reader_page.bar.dart.

import { Chip, MenuButton, Segmented } from './setup/primitives';
import { MenuIcon, PlayIcon, StopIcon } from './icons';
import type { Ambient } from './useAmbient';
import type { useSceneNarration } from './useSceneNarration';

export type ReaderMode = 'book' | 'scroll';

/** What both readers share: the page owns it, each reader draws the bar from it. */
export interface ReaderChrome {
  title: string;
  mode: ReaderMode;
  onMode: (mode: ReaderMode) => void;
  onToggleSidebar: () => void;
  ambient: Ambient;
  onExport: () => void;
  /** Why the last export failed; shown under the bar until dismissed. */
  problem: string;
  onDismissProblem: () => void;
}

export function ReaderBar({ chrome, where, reading, canRead, onRead, onStop, onContents }: {
  chrome: ReaderChrome;
  /** "Page 3 of 12" or "Ch. 2 · 40%". */
  where: string;
  reading: boolean;
  canRead: boolean;
  onRead: () => void;
  onStop: () => void;
  onContents: () => void;
}) {
  const { ambient } = chrome;
  return (
    <div className="s-read-bar" data-testid="reader-bar">
      <button type="button" className="s-btn-ico ghost" data-testid="reader-sidebar-toggle"
        aria-label="Show or hide the studio sidebar" title="Show or hide the studio sidebar"
        onClick={chrome.onToggleSidebar}><MenuIcon /></button>
      <span className="s-read-title s-ell">{chrome.title}</span>
      <Segmented testid="reader-mode" options={{ book: 'Book', scroll: 'Scroll' }} selected={chrome.mode}
        onSelect={(m) => chrome.onMode(m === 'scroll' ? 'scroll' : 'book')} />
      <span className="s-spacer" />
      {where && <span className="s-mono" data-testid="reader-where">{where}</span>}
      <div className="s-read-actions">
        {reading ? (
          <button type="button" className="s-btn-ghost" data-testid="reader-stop" onClick={onStop}><StopIcon /> Stop</button>
        ) : (
          <button type="button" className="s-btn-ghost" data-testid="reader-read-aloud" disabled={!canRead}
            onClick={onRead}><PlayIcon /> Read aloud</button>
        )}
        <button type="button" className="s-btn-ghost" data-testid="reader-contents" onClick={onContents}>Contents</button>
        <MenuButton label="Reader menu" testid="reader-menu" entries={[
          { label: ambient.on ? 'Ambient sound off' : 'Ambient sound on', disabled: !ambient.available, onSelect: ambient.toggle },
          { label: 'Export text…', divider: true, onSelect: chrome.onExport },
        ]} />
      </div>
    </div>
  );
}

/** Under the bar: the narrator's progress, why it refused (TTS off), or why an export failed. */
export function ReaderStatus({ chrome, narration }: {
  chrome: ReaderChrome;
  narration: ReturnType<typeof useSceneNarration>;
}) {
  return (
    <>
      {narration.reading && (
        <div className="s-read-status" role="status">
          <span>Reading scene {narration.current + 1} of {narration.total}</span>
          {narration.buffering && <Chip tone="teal">buffering…</Chip>}
        </div>
      )}
      {!narration.reading && narration.error && (
        <div className="s-read-status" role="status"><span>{narration.error}</span></div>
      )}
      {chrome.problem && (
        <div className="s-read-status" role="alert">
          <span className="s-error">{chrome.problem}</span>
          <button type="button" className="s-btn-ghost" onClick={chrome.onDismissProblem}>Dismiss</button>
        </div>
      )}
    </>
  );
}
