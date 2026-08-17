// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AI Enhance pre-flight + progress (web twin of the desktop enhance_flow):
// pick which chat grounds the rewrite (auto-picked when only one exists,
// friendly empty state at zero), tick which fields to rewrite, then watch the
// pipeline stream status until the proposal arrives — at which point the
// parent swaps in EnhanceReviewModal. Nothing is saved by this dialog.

import { useEffect, useMemo, useRef, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import type { SessionSummary } from '../ConversationsDrawer';
import {
  DEFAULT_ENHANCE_SELECTION,
  anySelected,
  buildEnhancePayload,
  type EnhanceProposal,
  type EnhanceSelection,
} from './enhanceForm';

const FIELD_ROWS: { key: keyof EnhanceSelection; label: string; hint: string }[] = [
  { key: 'description', label: 'Description', hint: 'Appearance, rewritten with detail from the story' },
  { key: 'personality', label: 'Personality', hint: 'Inner traits grounded in how they actually behaved' },
  { key: 'exampleDialogue', label: 'Example dialogue', hint: 'Teaching lines mined from their real voice' },
  { key: 'scenario', label: 'Scenario', hint: 'Re-anchor the opening to where the story went' },
  { key: 'greetings', label: 'First message + alternates', hint: 'Fresh openings in the voice from the chat' },
  { key: 'lorebook', label: 'Lorebook', hint: 'World entries from places the story revealed' },
  { key: 'porchLife', label: 'Porch Life (wardrobe, ambitions, likes)', hint: 'Propose what they wear and carry, long-term goals, and tastes — keep or accept on the next step' },
];

export function EnhanceDialog({
  characterId,
  characterName,
  defaultNsfw,
  onProposal,
  onClose,
}: {
  characterId: string;
  characterName: string;
  defaultNsfw: boolean;
  onProposal: (proposal: EnhanceProposal, selection: EnhanceSelection) => void;
  onClose: () => void;
}) {
  const [sessions, setSessions] = useState<SessionSummary[] | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [selection, setSelection] = useState<EnhanceSelection>(DEFAULT_ENHANCE_SELECTION);
  const [nsfw, setNsfw] = useState(defaultNsfw);
  const [running, setRunning] = useState(false);
  const [steps, setSteps] = useState<string[]>([]);
  const [error, setError] = useState('');
  // Remote backends only: which model runs this enhance ('' = current model).
  // Local backends generate with the loaded model — no picker, same rule as
  // the desktop dialog and the creator wizard.
  const [remoteModels, setRemoteModels] = useState<{ id: string; name: string }[] | null>(null);
  const [currentModel, setCurrentModel] = useState('');
  const [modelId, setModelId] = useState('');
  // Create's voice — fetched from detail so the enhance payload can carry it.
  // Missing fields stay omitted; the server then uses the card stamp.
  const [voice, setVoice] = useState<{
    narrativePerspective?: string;
    narrativeTense?: string;
    sex?: string;
  }>({});

  useEffect(() => {
    api
      .get<{
        narrativePerspective?: string;
        narrativeTense?: string;
        sex?: string;
      }>(`/api/characters/${encodeURIComponent(characterId)}/detail`)
      .then((d) =>
        setVoice({
          narrativePerspective: d.narrativePerspective,
          narrativeTense: d.narrativeTense,
          sex: d.sex,
        }),
      )
      .catch(() => {});
    api
      .get<{ sessions: SessionSummary[] }>(
        `/api/chat/sessions?characterId=${encodeURIComponent(characterId)}`,
      )
      .then((r) => {
        setSessions(r.sessions);
        if (r.sessions.length === 1) setSessionId(r.sessions[0].id);
      })
      .catch(() => setSessions([]));
    api
      .get<{ isLocal: boolean; remoteModel?: string }>('/api/backend/status')
      .then((s) => {
        if (s.isLocal) return;
        setCurrentModel(s.remoteModel || '');
        api
          .post<{ models: { id: string; name: string }[] }>('/api/backend/remote-models', {})
          .then((r) => setRemoteModels(r.models))
          .catch(() => setRemoteModels([]));
      })
      .catch(() => {});
  }, [characterId]);

  // Latest callback/selection via refs so the socket effect depends only on
  // `running` — a parent re-render (new inline onProposal identity) must not
  // tear down and reopen the socket mid-run, which could drop the done event.
  const onProposalRef = useRef(onProposal);
  onProposalRef.current = onProposal;
  const selectionRef = useRef(selection);
  selectionRef.current = selection;

  useEffect(() => {
    if (!running) return;
    const socket = new ChatSocket((e) => {
      if (e.event === 'chargen_status' && e.data) {
        setSteps((s) => [...s.slice(-6), e.data!]);
      } else if (e.event === 'chargen_enhance_done') {
        onProposalRef.current((e.proposal ?? {}) as EnhanceProposal, selectionRef.current);
      } else if (e.event === 'chargen_error') {
        setRunning(false);
        setError(e.error || 'Enhance failed');
      }
    });
    socket.connect();
    return () => socket.close();
  }, [running]);

  const shortChat = useMemo(() => {
    const s = sessions?.find((x) => x.id === sessionId);
    return s != null && s.user_message_count < 2;
  }, [sessions, sessionId]);

  const start = async () => {
    if (!sessionId || running || !anySelected(selection)) return;
    setError('');
    setSteps([]);
    setRunning(true);
    try {
      await api.post(
        '/api/chargen/enhance',
        buildEnhancePayload(characterId, sessionId, selection, nsfw, modelId, voice),
      );
    } catch (e) {
      setRunning(false);
      setError(e instanceof ApiError ? e.message : 'Could not start');
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={running ? undefined : onClose}>
      <div className="modal enh-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>✨ AI Enhance {characterName}</span>
          {!running && (
            <button className="link-btn" onClick={onClose}>
              Close
            </button>
          )}
        </div>

        {sessions === null && <p className="muted">Loading chats…</p>}

        {sessions !== null && sessions.length === 0 && (
          <>
            <p className="muted">
              AI Enhance grows {characterName} from a real conversation — the chat is what
              teaches the AI their true voice. Have a chat with {characterName} first, then
              come back.
            </p>
            <div className="modal-actions">
              <button className="primary" onClick={onClose}>
                Got it
              </button>
            </div>
          </>
        )}

        {sessions !== null && sessions.length > 0 && !running && (
          <>
            <p className="muted">
              Character cards are written before the first hello — but after a few real
              conversations, {characterName} has become someone more specific than the
              card ever described. AI Enhance reads one real chat and rewrites the card
              so the character on paper matches the one you actually know.
            </p>
            {sessions.length > 1 && (
              <div className="enh-sessions">
                <p className="muted">Which chat should ground the rewrite?</p>
                {sessions.map((s) => (
                  <button
                    key={s.id}
                    className={`enh-session${s.id === sessionId ? ' on' : ''}`}
                    onClick={() => setSessionId(s.id)}
                  >
                    <span className="enh-session-preview">{s.session_name || s.preview}</span>
                    <span className="enh-session-meta">
                      {s.message_count} messages · {s.user_message_count} yours
                    </span>
                  </button>
                ))}
              </div>
            )}
            <p className="muted">
              Rewrites the parts you pick using the real chat as the source of truth, then
              shows you every change before anything is saved. The result becomes a NEW “
              {characterName} (Enhanced)” character — the original is never touched.
            </p>
            {shortChat && (
              <p className="muted enh-warn">
                Heads up: this chat is very short, so the AI has little to work with —
                results may be thin.
              </p>
            )}
            {FIELD_ROWS.map((f) => (
              <label key={f.key} className="cg-field cg-toggle">
                <input
                  type="checkbox"
                  checked={selection[f.key]}
                  onChange={(e) => setSelection({ ...selection, [f.key]: e.target.checked })}
                />
                <span>
                  {f.label}
                  <small className="muted"> — {f.hint}</small>
                </span>
              </label>
            ))}
            {remoteModels !== null && remoteModels.length > 0 && (
              <label className="cg-field">
                <span className="cg-field-label">Model for this enhance</span>
                <select value={modelId} onChange={(e) => setModelId(e.target.value)}>
                  <option value="">
                    Current model{currentModel ? ` (${currentModel})` : ''}
                  </option>
                  {remoteModels.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.name || m.id}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label className="cg-field cg-toggle">
              <input type="checkbox" checked={nsfw} onChange={(e) => setNsfw(e.target.checked)} />
              <span>Allow 18+ themes</span>
            </label>
            {error && <p className="error">{error}</p>}
            <div className="modal-actions">
              <button className="ghost" onClick={onClose}>
                Cancel
              </button>
              <button
                className="primary"
                disabled={!sessionId || !anySelected(selection)}
                onClick={start}
              >
                ✨ Enhance
              </button>
            </div>
          </>
        )}

        {running && (
          <>
            <p className="muted">
              Interviewing {characterName} about the chat — this takes a few minutes on
              local models.
            </p>
            <div className="enh-steps">
              {steps.map((s, i) => (
                <div key={i} className={i === steps.length - 1 ? '' : 'muted'}>
                  {s}
                </div>
              ))}
            </div>
            {error && <p className="error">{error}</p>}
            <div className="modal-actions">
              <button className="ghost" onClick={onClose}>
                Cancel
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
