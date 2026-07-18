// Copyright (C) 2026 Front Porch AI — SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Import Lorebook wizard (desktop parity): Pick a file → Review what was
// detected → choose a destination (World / character(s) / this group / this
// chat). The server does the format detection and analysis (dryRun), then the
// commit clones entries into exactly one home.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';

interface Review {
  format: string;
  suggestedName: string;
  suggestedDescription: string;
  entryCount: number;
  enabledCount: number;
  approxTokens: number;
  features: Record<string, number>;
  warnings: string[];
  canGroup: boolean;
  canChat: boolean;
}

type Destination = 'world' | 'characters' | 'group' | 'chat';

export function ImportLorebookWizard({
  onClose,
  onImported,
}: {
  onClose: () => void;
  onImported: (message: string) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [step, setStep] = useState(0);
  const [raw, setRaw] = useState<Record<string, unknown> | null>(null);
  const [review, setReview] = useState<Review | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [destination, setDestination] = useState<Destination>('world');
  const [worldName, setWorldName] = useState('');
  const [worldDesc, setWorldDesc] = useState('');
  const [characters, setCharacters] = useState<{ id: string; name: string }[]>([]);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api
      .get<{ id: string; name: string }[]>('/api/characters')
      .then(setCharacters)
      .catch(() => setCharacters([]));
  }, []);

  const pick = async (file: File) => {
    setError(null);
    try {
      const parsed = JSON.parse(await file.text()) as Record<string, unknown>;
      const r = await api.post<Review>('/api/lorebook/import', {
        json: parsed,
        dryRun: true,
      });
      setRaw(parsed);
      setReview(r);
      setWorldName(r.suggestedName);
      setWorldDesc(r.suggestedDescription);
      if (r.entryCount > 0) setStep(1);
      else setError('No entries were found in this file.');
    } catch (e) {
      setRaw(null);
      setReview(null);
      setError(
        e instanceof ApiError
          ? e.message
          : 'Could not read this file as a lorebook. Supported: SillyTavern, Chub, NovelAI, AgnAI, RisuAI, Front Porch.',
      );
    }
  };

  const canProceed =
    step === 0
      ? review != null
      : step === 2
        ? destination === 'world'
          ? worldName.trim().length > 0
          : destination === 'characters'
            ? selectedIds.size > 0
            : true
        : true;

  const commit = async () => {
    if (raw == null || busy) return;
    setBusy(true);
    try {
      const r = await api.post<{ where: string; name?: string; count?: number }>(
        '/api/lorebook/import',
        {
          json: raw,
          destination,
          name: worldName.trim(),
          description: worldDesc.trim(),
          characterIds: [...selectedIds],
        },
      );
      const where =
        r.where === 'world'
          ? `the world "${r.name}"`
          : r.where === 'characters'
            ? `${r.count} character${r.count === 1 ? '' : 's'}`
            : r.where === 'group'
              ? `the group "${r.name}"`
              : 'this chat';
      onImported(`Imported ${review?.entryCount ?? 0} entries into ${where}.`);
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Import failed');
      setBusy(false);
    }
  };

  const stepLabel = ['Pick a file', 'Review', 'Destination'];

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal lore-import-modal" onClick={(e) => e.stopPropagation()}>
        <h3>Import Lorebook</h3>
        <div className="lore-wiz-steps">
          {stepLabel.map((label, i) => (
            <span key={label} className={`lore-wiz-step${step >= i ? ' on' : ''}`}>
              {i + 1}. {label}
            </span>
          ))}
        </div>

        {step === 0 && (
          <div className="lore-wiz-pick">
            <button onClick={() => fileRef.current?.click()}>
              Choose a lorebook file…
            </button>
            <p className="muted small">
              JSON from SillyTavern, Chub, NovelAI, AgnAI, RisuAI, or Front
              Porch — the format is detected automatically.
            </p>
            <input
              ref={fileRef}
              type="file"
              accept=".json,application/json"
              style={{ display: 'none' }}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) void pick(f);
                e.target.value = '';
              }}
            />
          </div>
        )}

        {step === 1 && review && (
          <div className="lore-wiz-review">
            <p>
              <strong>{review.format}</strong>
              <br />
              <span className="muted small">
                {review.suggestedName} · {review.entryCount} entries · ~
                {review.approxTokens} tokens
              </span>
            </p>
            {Object.keys(review.features).length > 0 && (
              <div className="lore-preview-chips">
                {Object.entries(review.features).map(([k, v]) => (
                  <span key={k} className="lore-pill honey">
                    {v} {k}
                  </span>
                ))}
              </div>
            )}
            {review.warnings.map((w) => (
              <p key={w} className="lore-wiz-warning small">{w}</p>
            ))}
          </div>
        )}

        {step === 2 && review && (
          <div className="lore-wiz-dest">
            <label className={`lore-dest${destination === 'world' ? ' sel' : ''}`}>
              <input
                type="radio"
                checked={destination === 'world'}
                onChange={() => setDestination('world')}
              />
              <div>
                <strong>New World</strong>
                <p className="muted small">
                  Shared library — attach to any character, group, or chat.
                </p>
                {destination === 'world' && (
                  <>
                    <input
                      placeholder="World name"
                      value={worldName}
                      onChange={(e) => setWorldName(e.target.value)}
                    />
                    <input
                      placeholder="Description (optional)"
                      value={worldDesc}
                      onChange={(e) => setWorldDesc(e.target.value)}
                    />
                  </>
                )}
              </div>
            </label>
            <label
              className={`lore-dest${destination === 'characters' ? ' sel' : ''}`}
            >
              <input
                type="radio"
                checked={destination === 'characters'}
                onChange={() => setDestination('characters')}
              />
              <div>
                <strong>Into character(s)</strong>
                <p className="muted small">
                  Becomes part of their card and travels with them.
                </p>
                {destination === 'characters' && (
                  <div className="lore-preview-chips">
                    {characters.map((c) => (
                      <button
                        key={c.id}
                        className={`lore-pill${selectedIds.has(c.id) ? ' ok' : ''}`}
                        onClick={(e) => {
                          e.preventDefault();
                          setSelectedIds((prev) => {
                            const next = new Set(prev);
                            if (next.has(c.id)) {
                              next.delete(c.id);
                            } else {
                              next.add(c.id);
                            }
                            return next;
                          });
                        }}
                      >
                        {c.name}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </label>
            {review.canGroup && (
              <label className={`lore-dest${destination === 'group' ? ' sel' : ''}`}>
                <input
                  type="radio"
                  checked={destination === 'group'}
                  onChange={() => setDestination('group')}
                />
                <div>
                  <strong>This group</strong>
                  <p className="muted small">Shared by everyone in the current group chat.</p>
                </div>
              </label>
            )}
            {review.canChat && (
              <label className={`lore-dest${destination === 'chat' ? ' sel' : ''}`}>
                <input
                  type="radio"
                  checked={destination === 'chat'}
                  onChange={() => setDestination('chat')}
                />
                <div>
                  <strong>This chat only</strong>
                  <p className="muted small">
                    Try a book in one conversation without touching your library.
                  </p>
                </div>
              </label>
            )}
          </div>
        )}

        {error && <p className="danger small">{error}</p>}

        <div className="modal-actions wizard-nav">
          {step > 0 ? (
            <button className="ghost" onClick={() => setStep(step - 1)} disabled={busy}>
              Back
            </button>
          ) : (
            <button className="ghost" onClick={onClose}>Cancel</button>
          )}
          <button
            disabled={!canProceed || busy}
            onClick={() => (step < 2 ? setStep(step + 1) : void commit())}
          >
            {step < 2
              ? 'Next'
              : busy
                ? 'Importing…'
                : `Import ${review?.entryCount ?? 0} entries`}
          </button>
        </div>
      </div>
    </div>
  );
}
