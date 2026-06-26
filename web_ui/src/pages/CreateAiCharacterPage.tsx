// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// AI character creator: describe a character, the host LLM generates a full
// card (profile → interview → dialogue → lorebook → first message → …) and
// persists it. Progress streams over the WebSocket hub so the page shows live
// steps instead of a dead spinner; on completion it jumps to the editor.

import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';

export function CreateAiCharacterPage() {
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [concept, setConcept] = useState('');
  const [keywords, setKeywords] = useState('');
  const [nsfw, setNsfw] = useState(false);
  const [available, setAvailable] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [steps, setSteps] = useState<string[]>([]);
  const [error, setError] = useState('');
  const socketRef = useRef<ChatSocket | null>(null);

  useEffect(() => {
    api.get<{ available: boolean }>('/api/chargen/status')
      .then((r) => setAvailable(r.available))
      .catch(() => setAvailable(false));
  }, []);

  // Listen for generation progress / completion. Mounted once; the socket is the
  // same multiplexed hub the chat uses.
  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'chargen_status' && e.data) {
        setSteps((s) => [...s, e.data!]);
      } else if (e.event === 'chargen_done') {
        setBusy(false);
        navigate(`/edit/${e.id}`);
      } else if (e.event === 'chargen_error') {
        setBusy(false);
        setError(e.error || 'Generation failed');
      }
    });
    socket.connect();
    socketRef.current = socket;
    return () => socket.close();
  }, [navigate]);

  const generate = async () => {
    if (!name.trim() || busy) return;
    setBusy(true);
    setSteps([]);
    setError('');
    try {
      await api.post('/api/chargen/create', {
        name: name.trim(),
        concept: concept.trim(),
        personalityKeywords: keywords.trim(),
        nsfwEnabled: nsfw,
      });
    } catch (e) {
      setBusy(false);
      setError(e instanceof ApiError ? e.message : 'Could not start generation');
    }
  };

  return (
    <div className="page">
      <header className="page-head">
        <button className="ghost" onClick={() => navigate('/')}>← Library</button>
        <h2>✨ AI Character Creator</h2>
      </header>

      {available === false && (
        <p className="muted">
          No LLM backend is ready. Start or connect a model on the Models page
          first.
        </p>
      )}

      <section className="card">
        <label>
          Name
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Aria Vale"
            disabled={busy}
          />
        </label>
        <label>
          Concept
          <textarea
            rows={4}
            value={concept}
            onChange={(e) => setConcept(e.target.value)}
            placeholder="A wandering bard with a sharp tongue and a hidden past…"
            disabled={busy}
          />
        </label>
        <label>
          Personality keywords <span className="muted small">(optional)</span>
          <input
            value={keywords}
            onChange={(e) => setKeywords(e.target.value)}
            placeholder="witty, guarded, loyal"
            disabled={busy}
          />
        </label>
        <label className="row-label">
          <input
            type="checkbox"
            checked={nsfw}
            onChange={(e) => setNsfw(e.target.checked)}
            disabled={busy}
          />
          Allow mature content
        </label>
        <button
          className="primary"
          disabled={busy || !name.trim() || available === false}
          onClick={generate}
        >
          {busy ? 'Generating…' : 'Generate character'}
        </button>
        {error && <p className="error">{error}</p>}
      </section>

      {steps.length > 0 && (
        <section className="card">
          <h3>Progress</h3>
          <ol className="chargen-steps">
            {steps.map((s, i) => (
              <li key={i} className={i === steps.length - 1 && busy ? 'active' : 'done'}>{s}</li>
            ))}
          </ol>
        </section>
      )}
    </div>
  );
}
