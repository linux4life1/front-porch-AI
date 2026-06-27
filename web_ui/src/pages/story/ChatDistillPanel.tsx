// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Collapsible chat-history distillation panel for the bible dashboard: a
// "N events distilled" / "Not distilled yet" badge, Timeline | Raw Messages
// tabs, and a Redistill action. Mirrors the desktop dashboard panel and finally
// calls the /chat-preview endpoint the old web never used.

import { useState } from 'react';
import { api } from '../../api/client';
import type { StoryProject } from '../../storyTypes';

export function ChatDistillPanel({
  id, project, busy, onRedistill,
}: {
  id: string;
  project: StoryProject;
  busy: boolean;
  onRedistill: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<'timeline' | 'raw'>('timeline');
  const [messages, setMessages] = useState<string[] | null>(null);
  const [loadingRaw, setLoadingRaw] = useState(false);

  const timeline = project.distilled_timeline || '';
  const hasTimeline = timeline.trim() !== '';
  const eventCount = (timeline.match(/\[EVENT \d+\]/g) || []).length;

  const loadRaw = async () => {
    setTab('raw');
    if (messages !== null || loadingRaw) return;
    setLoadingRaw(true);
    try {
      const r = await api.get<{ messages: string[] }>(`/api/stories/${id}/chat-preview`);
      setMessages(r.messages);
    } catch {
      setMessages([]);
    } finally {
      setLoadingRaw(false);
    }
  };

  return (
    <section className="card distill-panel" style={{ padding: 0 }}>
      <button className="distill-head" onClick={() => setOpen(!open)}>
        <span>🕓</span>
        <strong>Chat History</strong>
        {hasTimeline ? (
          <span className="distill-badge ok">{eventCount} events distilled</span>
        ) : (
          <span className="distill-badge none">Not distilled yet</span>
        )}
        <span style={{ marginLeft: 'auto' }}>{open ? '▴' : '▾'}</span>
      </button>

      {open && (
        <>
          <div className="distill-tabs">
            {hasTimeline && (
              <button className={`distill-tab${tab === 'timeline' ? ' on' : ''}`}
                onClick={() => setTab('timeline')}>Timeline</button>
            )}
            <button className={`distill-tab${tab === 'raw' || !hasTimeline ? ' on' : ''}`}
              onClick={loadRaw}>Raw Messages</button>
            <button className="distill-tab" style={{ marginLeft: 'auto' }}
              disabled={busy} onClick={onRedistill}>
              ↻ {hasTimeline ? 'Redistill' : 'Distill now'}
            </button>
          </div>

          {tab === 'timeline' && hasTimeline ? (
            <div className="distill-body">{timeline}</div>
          ) : loadingRaw ? (
            <div className="distill-body"><div className="spinner small" /></div>
          ) : messages && messages.length > 0 ? (
            <div className="distill-body">
              {messages.map((m, i) => (
                m.startsWith('---') ? (
                  <hr key={i} className="distill-sep" />
                ) : (
                  <div key={i} className={`distill-msg${/^(user|{{user}}):/i.test(m) ? ' user' : ''}`}>
                    <span>{/^(user|{{user}}):/i.test(m) ? '🧑' : '🤖'}</span>
                    <span>{m}</span>
                  </div>
                )
              ))}
            </div>
          ) : (
            <div className="distill-body muted">
              {messages ? 'No chat history found for the selected characters.'
                : 'Open "Raw Messages" to load the chat history.'}
            </div>
          )}
        </>
      )}
    </section>
  );
}
