// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review rail's Expressions card (desktop expressions_section.dart): the
// Generate-pack switch, the 8/28 set, Prompt rules, the run CTA and progress,
// and the ZIP import. Presentational — the rail owns the pack job. Vision QC
// is deliberately absent (maintainer ruling, 2026-11-15).

import type { PackView } from '../models/studio/packApi';
import { ToggleRow } from '../realism/controls';
import { ZipIcon } from './creatorIcons';

export function AvatarExpressions({
  packOn,
  onPackOnChange,
  full,
  onFullChange,
  pack,
  packError,
  note,
  error,
  engineReady,
  busy,
  generating,
  cta,
  onRun,
  onCancel,
  onPickZip,
  onOpenRules,
  expressionCount,
}: {
  packOn: boolean;
  onPackOnChange: (on: boolean) => void;
  full: boolean;
  onFullChange: (full: boolean) => void;
  pack: PackView | null;
  packError: string;
  note: string;
  error: string;
  engineReady: boolean;
  busy: boolean;
  generating: boolean;
  cta: string | null;
  onRun: () => void;
  onCancel: () => void;
  onPickZip: () => void;
  onOpenRules: () => void;
  expressionCount: number;
}) {
  return (
    <section className="cg-r-expr" aria-label="Expressions">
      <h4>EXPRESSIONS — INDEPENDENT OF THE PORTRAIT SOURCE</h4>
      <ToggleRow label="Generate pack" value={packOn} onChange={onPackOnChange} />
      {!packOn ? (
        <>
          <p className="cg-r-caption">
            Upload expression images instead: tag uploads above with an emotion, or import an
            emotion-named ZIP sprite pack.
          </p>
          <button type="button" className="ghost cg-r-import" disabled={busy} onClick={onPickZip}>
            <ZipIcon /> Import ZIP
          </button>
        </>
      ) : (
        <div className="cg-r-pack">
          <div className="cg-r-pack-row">
            <label className="cg-field">
              <span className="cg-field-label">Set</span>
              <select value={full ? 'full' : 'starter'} onChange={(e) => onFullChange(e.target.value === 'full')}>
                <option value="starter">8 base emotions</option>
                <option value="full">all 28</option>
              </select>
            </label>
            <button type="button" className="cg-p-text-btn" onClick={onOpenRules}>
              Prompt rules…
            </button>
          </div>
          {cta && (
            <button
              type="button"
              className="primary cg-r-generate-btn"
              disabled={!engineReady || busy || generating || pack?.running === true}
              onClick={onRun}
            >
              {pack?.running ? 'Running…' : cta}
            </button>
          )}
          {pack?.running && (
            <>
              <progress className="cg-r-progress" value={pack.done} max={pack.total || 1} />
              <div className="cg-r-pack-row">
                <span className="cg-r-caption">
                  {pack.done} / {pack.total} expressions
                </span>
                <button type="button" className="ghost" onClick={onCancel}>
                  Cancel
                </button>
              </div>
            </>
          )}
          {packError && <p className="error">{packError}</p>}
        </div>
      )}
      {note && <p className="cg-r-note-line">{note}</p>}
      {error && <p className="error">{error}</p>}
      {expressionCount > 0 && (
        <p className="cg-r-caption">
          {expressionCount} expression image{expressionCount === 1 ? '' : 's'} on this character.
        </p>
      )}
    </section>
  );
}
