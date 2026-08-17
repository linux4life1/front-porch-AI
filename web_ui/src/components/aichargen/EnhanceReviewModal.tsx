// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AI Enhance review (web twin of the desktop enhance_review_page): old vs new
// per rewritten field — side-by-side on wide layouts, stacked on phones — with
// per-section "use this" toggles and editable new text. Apply creates the
// "<Name> (Enhanced)" duplicate via the existing duplicate endpoint, then
// writes the accepted fields with the existing partial-update endpoint.
// Discard closes without any request.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { useLayout } from '../../hooks/useBreakpoint';
import {
  buildApplyBody,
  withEmptyTextUseOff,
  type EnhanceAccepted,
  type EnhanceEdits,
  type EnhanceProposal,
  type EnhanceSelection,
} from './enhanceForm';

interface CharDetail {
  description?: string;
  personality?: string;
  mesExample?: string;
  scenario?: string;
  firstMessage?: string;
  lorebook?: unknown;
  realism?: {
    ambitions?: string[];
    likes?: string[];
    dislikes?: string[];
    intimateInto?: string[];
    intimateNotInto?: string[];
    inventory?: { worn?: unknown[]; carrying?: unknown[] };
  } | null;
}

export function EnhanceReviewModal({
  characterId,
  characterName,
  proposal,
  selection,
  onApplied,
  onClose,
}: {
  characterId: string;
  characterName: string;
  proposal: EnhanceProposal;
  selection: EnhanceSelection;
  onApplied: (newId: string) => void;
  onClose: () => void;
}) {
  const { wide } = useLayout();
  const [old, setOld] = useState<CharDetail | null>(null);
  const [accepted, setAccepted] = useState<EnhanceAccepted>(() => ({
    ...selection,
    ...withEmptyTextUseOff(selection, proposal),
    porchLife:
      selection.porchLife &&
      porchHasItems(proposal.porchLife),
  }));
  const [edits, setEdits] = useState<EnhanceEdits>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  // Post-apply "bring your chats along" offer (web twin of the desktop
  // wizard's last step): applied = the saved duplicate's id.
  const [applied, setApplied] = useState<string | null>(null);
  const [copying, setCopying] = useState(false);
  const [copied, setCopied] = useState<number | null>(null);
  const [copyError, setCopyError] = useState('');

  useEffect(() => {
    api
      .get<CharDetail>(`/api/characters/${characterId}/detail`)
      .then(setOld)
      .catch(() => setOld({}));
  }, [characterId]);

  const apply = async () => {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      const dup = await api.post<{ id: string; name: string }>(
        `/api/characters/${characterId}/duplicate`,
        { newName: `${characterName} (Enhanced)` },
      );
      await api.post(
        `/api/characters/${dup.id}`,
        buildApplyBody(proposal, accepted, edits, {
          lorebook: old?.lorebook,
          ambitions: old?.realism?.ambitions,
          likes: old?.realism?.likes,
          dislikes: old?.realism?.dislikes,
          intimateInto: old?.realism?.intimateInto,
          intimateNotInto: old?.realism?.intimateNotInto,
          inventory: old?.realism?.inventory,
        }),
      );
      // Don't leave yet — offer to bring the base character's chats along.
      setBusy(false);
      setApplied(dup.id);
    } catch (e) {
      setBusy(false);
      setError(e instanceof ApiError ? e.message : 'Could not save the enhanced character');
    }
  };

  const copyChats = async () => {
    if (!applied || copying) return;
    setCopying(true);
    setCopyError('');
    try {
      const r = await api.post<{ copied: number }>('/api/chargen/enhance-chats', {
        fromId: characterId,
        toId: applied,
      });
      setCopied(r.copied);
    } catch (e) {
      setCopyError(e instanceof ApiError ? e.message : 'Could not copy the chats');
    } finally {
      setCopying(false);
    }
  };

  // Once the copy is saved, leaving the modal by any door lands on it.
  const leave = () => (applied ? onApplied(applied) : onClose());

  const section = (
    key: keyof EnhanceAccepted,
    title: string,
    oldText: string | undefined,
    newText: string | undefined,
    editKey?: keyof EnhanceEdits,
  ) => {
    if (newText === undefined) return null;
    const use = accepted[key];
    return (
      <div className="enh-section" key={`${key}-${title}`}>
        <div className="enh-section-head">
          <strong>{title}</strong>
          <label className="cg-field cg-toggle enh-use">
            <input
              type="checkbox"
              checked={use}
              onChange={(e) => setAccepted({ ...accepted, [key]: e.target.checked })}
            />
            <span>Use this</span>
          </label>
        </div>
        <div className={`enh-compare${wide ? ' wide' : ''}`}>
          <div>
            <small className="muted">Before</small>
            <div className="enh-old">{oldText?.trim() ? oldText : '(empty)'}</div>
          </div>
          <div>
            <small className="muted">After (editable)</small>
            <textarea
              className="enh-new"
              disabled={!use || editKey === undefined}
              value={
                editKey !== undefined
                  ? ((edits[editKey] as string | undefined) ?? newText)
                  : newText
              }
              onChange={(e) =>
                editKey !== undefined && setEdits({ ...edits, [editKey]: e.target.value })
              }
            />
          </div>
        </div>
      </div>
    );
  };

  const loreCount = Array.isArray((proposal.lorebook as { entries?: unknown[] })?.entries)
    ? (proposal.lorebook as { entries: unknown[] }).entries.length
    : 0;

  const porchLive = edits.porchLife ?? proposal.porchLife;
  const porchField = (title: string, key: keyof NonNullable<EnhanceEdits['porchLife']>) => {
    if (!proposal.porchLife || !porchLive) return null;
    return (
      <label key={key} className="enh-porch-field">
        <small className="muted">{title} (comma-separated)</small>
        <textarea
          className="enh-new"
          disabled={!accepted.porchLife}
          value={(porchLive[key] ?? []).join(', ')}
          onChange={(e) => {
            const next = {
              ...proposal.porchLife!,
              ...edits.porchLife,
              [key]: e.target.value
                .split(',')
                .map((s) => s.trim())
                .filter(Boolean),
            };
            setEdits({ ...edits, porchLife: next });
          }}
        />
      </label>
    );
  };

  if (applied !== null) {
    return (
      <div className="drawer-backdrop center" onClick={copying ? undefined : leave}>
        <div className="modal enh-modal" onClick={(e) => e.stopPropagation()}>
          <div className="drawer-head">
            <span>✨ “{characterName} (Enhanced)” is saved!</span>
            {!copying && (
              <button className="link-btn" onClick={leave}>
                Close
              </button>
            )}
          </div>
          <p className="muted">
            One last thing: the enhanced copy starts with an empty chat list. Want to
            bring {characterName}'s chats along? Each one is copied in full — messages,
            journal memories, relationship state — so you can pick up right where you
            left off. {characterName} keeps the originals either way.
          </p>
          {copied !== null && (
            <p className="muted">
              {copied === 0
                ? 'Nothing to copy — no chats yet.'
                : `Copied ${copied} chat${copied === 1 ? '' : 's'} over.`}
            </p>
          )}
          {copyError && <p className="error">{copyError}</p>}
          <div className="modal-actions">
            {copied === null ? (
              <>
                <button className="ghost" disabled={copying} onClick={leave}>
                  Skip
                </button>
                <button className="primary" disabled={copying} onClick={copyChats}>
                  {copying ? 'Copying…' : 'Copy my chats over'}
                </button>
              </>
            ) : (
              <button className="primary" onClick={leave}>
                Done
              </button>
            )}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="drawer-backdrop center" onClick={busy ? undefined : onClose}>
      <div className="modal enh-modal enh-review" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>✨ Review: {characterName} (Enhanced)</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="muted">
          Nothing is saved yet. Untick what you don't want, tweak the text, then Save to add
          the enhanced copy to your library. Your original {characterName} stays exactly
          as-is either way.
        </p>

        {old === null && <p className="muted">Loading current card…</p>}
        {old !== null && (
          <div className="enh-sections">
            {section('description', 'Description', old.description, proposal.description, 'description')}
            {section('personality', 'Personality', old.personality, proposal.personality, 'personality')}
            {section('exampleDialogue', 'Example dialogue', old.mesExample, proposal.mesExample, 'mesExample')}
            {section('scenario', 'Scenario', old.scenario, proposal.scenario, 'scenario')}
            {section('greetings', 'First message', old.firstMessage, proposal.firstMessage, 'firstMessage')}
            {proposal.alternateGreetings?.map((g, i) => (
              <div className="enh-section" key={`alt${i}`}>
                <div className="enh-section-head">
                  <strong>Alternate greeting {i + 1}</strong>
                </div>
                <textarea
                  className="enh-new"
                  disabled={!accepted.greetings}
                  value={edits.alternateGreetings?.[i] ?? g}
                  onChange={(e) => {
                    const alts = [...(edits.alternateGreetings ?? proposal.alternateGreetings ?? [])];
                    alts[i] = e.target.value;
                    setEdits({ ...edits, alternateGreetings: alts });
                  }}
                />
              </div>
            ))}
            {selection.porchLife && proposal.porchLife && (
              <div className="enh-section">
                <div className="enh-section-head">
                  <strong>Porch Life (wardrobe, ambitions, likes)</strong>
                  <label className="cg-field cg-toggle enh-use">
                    <input
                      type="checkbox"
                      checked={accepted.porchLife}
                      onChange={(e) =>
                        setAccepted({ ...accepted, porchLife: e.target.checked })
                      }
                    />
                    <span>Use this</span>
                  </label>
                </div>
                <p className="muted small">
                  Before: {formatPorchBefore(old.realism)}
                </p>
                {porchField('Ambitions', 'ambitions')}
                {porchField('Drawn to', 'likes')}
                {porchField('Put off by', 'dislikes')}
                {porchField('Wearing', 'worn')}
                {porchField('Carrying', 'carrying')}
                {(proposal.porchLife.intimateInto.length > 0 ||
                  proposal.porchLife.intimateNotInto.length > 0) && (
                  <>
                    {porchField('Warms to', 'intimateInto')}
                    {porchField('Not interested in', 'intimateNotInto')}
                  </>
                )}
              </div>
            )}
            {selection.lorebook && loreCount > 0 && (
              <div className="enh-section">
                <div className="enh-section-head">
                  <strong>New lorebook ({loreCount} entries)</strong>
                  <label className="cg-field cg-toggle enh-use">
                    <input
                      type="checkbox"
                      checked={accepted.lorebook}
                      onChange={(e) => setAccepted({ ...accepted, lorebook: e.target.checked })}
                    />
                    <span>Use this</span>
                  </label>
                </div>
              </div>
            )}
          </div>
        )}

        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          <button className="ghost" disabled={busy} onClick={onClose}>
            Discard
          </button>
          <button className="primary" disabled={busy || old === null} onClick={apply}>
            {busy ? 'Saving…' : 'Save as New Character'}
          </button>
        </div>
      </div>
    </div>
  );
}

function porchHasItems(p: EnhanceProposal['porchLife'] | undefined): boolean {
  if (!p) return false;
  return (
    p.ambitions.length +
      p.likes.length +
      p.dislikes.length +
      p.worn.length +
      p.carrying.length +
      p.intimateInto.length +
      p.intimateNotInto.length >
    0
  );
}

function formatPorchBefore(realism: CharDetail['realism']): string {
  if (!realism) return '(empty)';
  const worn = (realism.inventory?.worn ?? [])
    .map((e) => (typeof e === 'string' ? e : (e as { name?: string }).name ?? ''))
    .filter(Boolean);
  const carrying = (realism.inventory?.carrying ?? [])
    .map((e) => (typeof e === 'string' ? e : (e as { name?: string }).name ?? ''))
    .filter(Boolean);
  const bits = [
    realism.ambitions?.length ? `ambitions ${realism.ambitions.join(', ')}` : null,
    worn.length ? `wearing ${worn.join(', ')}` : null,
    carrying.length ? `carrying ${carrying.join(', ')}` : null,
  ].filter(Boolean);
  return bits.length ? bits.join(' · ') : '(empty)';
}
