// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Write header (sketch O): ‹ previous scene, the scene's label and title
// with where the writing stands (tap to jump to any scene), › next scene, the
// run chip while the pipeline works, and the scene ⋯ menu. Web twin of
// _buildHeader in story_writer_page.dart.

import { ChevronLeftIcon, ChevronRightIcon } from '../icons';
import { Chip, MenuButton, type MenuEntry } from '../setup/primitives';

export function SceneHeader({
  title, subtitle, canPrev, canNext, onPrev, onNext, onPick, step, menu,
}: {
  title: string;
  subtitle: string;
  canPrev: boolean;
  canNext: boolean;
  onPrev: () => void;
  onNext: () => void;
  onPick: () => void;
  /** The pipeline's current step while it runs; null when idle. */
  step: string | null;
  menu: MenuEntry[];
}) {
  const prev = canPrev ? 'Previous scene' : 'First scene';
  const next = canNext ? 'Next scene' : 'Last scene';
  return (
    <div className="s-write-head">
      <button type="button" className="s-btn-ico ghost" data-testid="story-prev-scene" aria-label={prev} title={prev}
        disabled={!canPrev} onClick={onPrev}><ChevronLeftIcon /></button>
      <button type="button" className="s-write-title" data-testid="story-scene-title" title="Go to scene" onClick={onPick}>
        <b className="s-ell">{title}</b>
        <span className="s-ell">{subtitle}</span>
      </button>
      <button type="button" className="s-btn-ico ghost" data-testid="story-next-scene" aria-label={next} title={next}
        disabled={!canNext} onClick={onNext}><ChevronRightIcon /></button>
      {step !== null && <Chip tone="amber">● {step}</Chip>}
      <MenuButton label="Scene menu" testid="story-scene-menu" entries={menu} />
    </div>
  );
}
