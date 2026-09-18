// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Standing mood, ambitions, and the Objectives panel. Desktop twin is
// chat_tools_facade.objectives.

import { ObjectivesPanel } from './ObjectivesPanel';
import { type ToolsApply, type ToolsState } from './ChatToolsShared';

export function ChatToolsStandingMood({ t }: { t: ToolsState }) {
  if (!t.standingMood) return null;
  return (
    <p className="muted small" style={{ margin: '0 0 10px', fontStyle: 'italic' }}>
      🌤️ Came in {t.standingMood}
    </p>
  );
}

export function ChatToolsAmbitions({ t }: { t: ToolsState }) {
  if ((t.ambitions?.length ?? 0) === 0) return null;
  return (
    <details className="tool-section" open>
      <summary>Ambitions</summary>
      <div className="tool-body">
        {t.ambitions!.map((a, i) => (
          <div key={i} className="ambition-row" title={`${a.text} — ${a.stage}`}>
            <div className="ambition-line">
              <span>🧭 {a.text}</span>
              <em className="ambition-stage">{a.stage}</em>
            </div>
            <div className="ambition-bar">
              <div
                className="ambition-bar-fill"
                style={{ width: `${Math.min(100, Math.max(0, a.progress))}%` }}
              />
            </div>
            {a.step?.trim() && <div className="ambition-step">↳ {a.step.trim()}</div>}
          </div>
        ))}
      </div>
    </details>
  );
}

export function ChatToolsObjectives({
  t,
  q,
  apply,
}: {
  t: ToolsState;
  q: string;
  apply: ToolsApply;
}) {
  return (
    <ObjectivesPanel
      primary={t.objectives.primary}
      secondary={t.objectives.secondary}
      checking={t.objectives.isChecking}
      enabled={t.objectives.enabled !== false}
      query={q}
      apply={apply}
    />
  );
}
