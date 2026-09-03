// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat tools Objectives section — desktop sidebar parity: NSFW Tasks switch,
// generate-with-count, and a manual add-task row. Extracted from ChatTools
// so that file does not grow and the controls can be tested in isolation.

import { useState } from 'react';
import { api } from '../api/client';

export interface ObjectiveTask {
  description: string;
  completed: boolean;
}

export interface ObjectiveView {
  id: string;
  objective: string;
  isPrimary: boolean;
  checkFrequency: number;
  tasks: ObjectiveTask[];
  servedAmbition?: string | null;
}

const TASK_COUNTS = [3, 4, 5, 6, 7, 8, 10];

export function ObjectivesPanel({
  primary,
  secondary,
  checking,
  enabled,
  query,
  apply,
}: {
  primary: ObjectiveView | null;
  secondary: ObjectiveView[];
  checking: boolean;
  enabled: boolean;
  query: string;
  apply: (p: Promise<unknown>) => void;
}) {
  const [goal, setGoal] = useState('');
  const [taskDraft, setTaskDraft] = useState('');
  const [nsfwTasks, setNsfwTasks] = useState(false);
  const [taskCount, setTaskCount] = useState(5);

  if (enabled === false) return null;

  const obj = primary;
  const q = query;
  const postObjective = (body: Record<string, unknown>) =>
    apply(api.post(`/api/chat/tools/objective${q}`, body));
  const postTask = (body: Record<string, unknown>) =>
    apply(api.post(`/api/chat/tools/task${q}`, body));

  const addManual = (id: string) => {
    const description = taskDraft.trim();
    if (!description) return;
    postTask({ action: 'add', id, description });
    setTaskDraft('');
  };

  return (
    <details className="tool-section" open={checking}>
      <summary>
        Objectives{obj || secondary.length > 0 ? '' : ' (none)'}
        {checking && <span className="obj-checking-tag"> · checking…</span>}
      </summary>
      <div className="tool-body">
        {checking && (
          <div className="obj-checking">
            <span className="proc-spinner sm" aria-hidden /> Checking objective &amp; task completion…
          </div>
        )}
        {obj ? (
          <>
            <div className="stat-line">
              <strong>{obj.objective}</strong>
            </div>
            {obj.servedAmbition?.trim() && (
              <div className="obj-ambition" title={`A step toward: ${obj.servedAmbition.trim()}`}>
                🧭 {obj.servedAmbition.trim()}
              </div>
            )}
            {obj.tasks.length > 0 && (
              <ul className="task-list">
                {obj.tasks.map((task, i) => (
                  <li key={i}>
                    <label className="task-item">
                      <input
                        type="checkbox"
                        checked={task.completed}
                        onChange={() => postTask({ action: 'toggle', id: obj.id, taskIndex: i })}
                      />
                      <span className={task.completed ? 'done' : ''}>{task.description}</span>
                      <button
                        className="icon-btn"
                        title="Remove"
                        onClick={() => postTask({ action: 'remove', id: obj.id, taskIndex: i })}
                      >
                        🗑
                      </button>
                    </label>
                  </li>
                ))}
              </ul>
            )}
            <label className="tool-toggle">
              <span>NSFW tasks</span>
              <input
                type="checkbox"
                checked={nsfwTasks}
                onChange={(e) => setNsfwTasks(e.target.checked)}
              />
            </label>
            <div className="tool-row">
              <button
                disabled={checking}
                onClick={() =>
                  postObjective({
                    action: 'generate',
                    id: obj.id,
                    taskCount,
                    nsfw: nsfwTasks,
                  })
                }
              >
                Generate tasks
              </button>
              <select
                aria-label="Task count"
                value={taskCount}
                onChange={(e) => setTaskCount(Number(e.target.value))}
              >
                {TASK_COUNTS.map((n) => (
                  <option key={n} value={n}>
                    {n}
                  </option>
                ))}
              </select>
              <button onClick={() => postObjective({ action: 'clear', id: obj.id })}>Clear</button>
            </div>
            <div className="tool-row">
              <input
                placeholder="Add a task manually…"
                value={taskDraft}
                onChange={(e) => setTaskDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') addManual(obj.id);
                }}
              />
              <button disabled={!taskDraft.trim()} onClick={() => addManual(obj.id)}>
                Add
              </button>
            </div>
          </>
        ) : (
          <div className="tool-row">
            <input
              placeholder="Set a goal for this character…"
              value={goal}
              onChange={(e) => setGoal(e.target.value)}
            />
            <button
              className="primary"
              disabled={!goal.trim()}
              onClick={() => {
                postObjective({ action: 'set', goal });
                setGoal('');
              }}
            >
              Set
            </button>
          </div>
        )}
        {secondary.length > 0 && (
          <>
            <div className="muted small side-quest-label">Side quests</div>
            {secondary.map((sq) => {
              const doneCount = sq.tasks.filter((x) => x.completed).length;
              return (
                <div className="side-quest" key={sq.id}>
                  <div className="stat-line">
                    <strong>{sq.objective}</strong>
                    {sq.tasks.length > 0 && (
                      <span className="muted">
                        {doneCount}/{sq.tasks.length}
                      </span>
                    )}
                  </div>
                  {sq.servedAmbition?.trim() && (
                    <div className="obj-ambition" title={`A step toward: ${sq.servedAmbition.trim()}`}>
                      🧭 {sq.servedAmbition.trim()}
                    </div>
                  )}
                  {sq.tasks.length > 0 && (
                    <ul className="task-list">
                      {sq.tasks.map((task, i) => (
                        <li key={i}>
                          <label className="task-item">
                            <input
                              type="checkbox"
                              checked={task.completed}
                              onChange={() => postTask({ action: 'toggle', id: sq.id, taskIndex: i })}
                            />
                            <span className={task.completed ? 'done' : ''}>{task.description}</span>
                            <button
                              className="icon-btn"
                              title="Remove"
                              onClick={() => postTask({ action: 'remove', id: sq.id, taskIndex: i })}
                            >
                              🗑
                            </button>
                          </label>
                        </li>
                      ))}
                    </ul>
                  )}
                  <div className="tool-row">
                    <button onClick={() => postObjective({ action: 'promote', id: sq.id })}>
                      Make primary
                    </button>
                    <button onClick={() => postObjective({ action: 'clear', id: sq.id })}>Clear</button>
                  </div>
                </div>
              );
            })}
          </>
        )}
      </div>
    </details>
  );
}
