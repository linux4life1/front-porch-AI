// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The lens mark and tension bars a scene row carries, and the lens list they
// read. Web twins of StoryLensMark / StoryTensionBars (studio_widgets.dart).

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import type { StoryLens, StoryProject } from '../../../storyTypes';
import { normalizeLensId, tensionBars } from '../storyShape';

/** The built-in lenses with their glyphs (`GET /api/stories/lenses`). */
export function useLenses(): StoryLens[] {
  const [lenses, setLenses] = useState<StoryLens[]>([]);
  useEffect(() => {
    api.get<{ lenses: StoryLens[] }>('/api/stories/lenses').then((r) => setLenses(r.lenses)).catch(() => undefined);
  }, []);
  return lenses;
}

/** A lens's name: the story's own lens of that id wins over the built-in one; '' when it is unknown. */
export function lensNameFor(p: StoryProject, lenses: StoryLens[], id: string): string {
  const wanted = normalizeLensId(id);
  const custom = ((p.custom_lenses ?? []) as { id: string; name: string }[]).find((l) => l.id === wanted);
  return custom?.name ?? lenses.find((l) => l.id === wanted)?.name ?? '';
}

/** A 22px raised square with the lens glyph in amber; a lens nobody knows shows ✎ and reads "Balanced". */
export function LensMark({ lensId, lenses }: { lensId?: string; lenses: StoryLens[] }) {
  const id = lensId ?? '';
  const name = lenses.find((l) => l.id === normalizeLensId(id))?.name ?? 'Balanced';
  const glyph = lenses.find((l) => l.id === id)?.glyph ?? '✎';
  return <span className="s-lens" title={name} aria-label={`Lens: ${name}`}>{glyph}</span>;
}

/** Four 4px bars rising 5 to 14px, terracotta when filled. */
export function TensionBars({ tension }: { tension: number }) {
  const filled = tensionBars(tension);
  return (
    <span className="s-tension" title={`Tension ${tension > 0 ? '+' : ''}${tension}`} data-filled={filled}>
      {[0, 1, 2, 3].map((i) => <i key={i} className={i < filled ? 'f' : ''} style={{ height: 5 + i * 3 }} />)}
    </span>
  );
}
