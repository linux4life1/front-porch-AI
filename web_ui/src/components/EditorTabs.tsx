// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The editor's four tabs (Details, Dialogue, Lorebook, Worlds), the same bar
// on the character editor and the group editor. A tab can be greyed out:
// still in the bar at its place, not selectable, saying why on hover or
// long-press (docs/design/group-editor.md A3).

import { useRef, useState } from 'react';

export const EDITOR_TABS = ['Details', 'Dialogue', 'Lorebook', 'Worlds'] as const;
export type EditorTab = (typeof EDITOR_TABS)[number];

export function EditorTabs({
  tab,
  onTab,
  locked = {},
}: {
  tab: EditorTab;
  onTab: (t: EditorTab) => void;
  /** Tabs that are greyed out, each with its tooltip. */
  locked?: Partial<Record<EditorTab, string>>;
}) {
  const [tip, setTip] = useState<string | null>(null);
  const press = useRef<number | undefined>(undefined);
  return (
    <div className="editor-tabs" role="tablist" data-testid="editor-tabs">
      {EDITOR_TABS.map((t) => {
        const why = locked[t];
        return (
          <button
            key={t}
            type="button"
            role="tab"
            className={`editor-tab${tab === t ? ' active' : ''}${why ? ' greyed' : ''}`}
            aria-selected={tab === t}
            aria-disabled={why ? true : undefined}
            title={why}
            onClick={() => {
              if (!why) onTab(t);
            }}
            onTouchStart={() => {
              if (!why) return;
              press.current = window.setTimeout(() => {
                setTip(why);
                window.setTimeout(() => setTip(null), 2500);
              }, 500);
            }}
            onTouchEnd={() => window.clearTimeout(press.current)}
            onTouchMove={() => window.clearTimeout(press.current)}
          >
            {t}
          </button>
        );
      })}
      {tip && (
        <span role="tooltip" className="greyed-out-tip editor-tab-tip">
          {tip}
        </span>
      )}
    </div>
  );
}
