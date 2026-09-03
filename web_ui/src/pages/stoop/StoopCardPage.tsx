// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop card detail — definition sections, tags, votes (optimistic with
// revert, like the desktop), download-to-library and report. The download
// itself runs on the desktop server (it owns the library); this page just
// asks and reports the outcome.

import { useEffect, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { StoopBadges, StoopCardArt } from '../../components/stoop/StoopCardTile';
import { StoopVerifiedBadge } from '../../components/stoop/StoopVerifiedBadge';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import { stoopCardKind, type CardMap } from '../../stoop/stoopCardBody';
import { REPORT_CATEGORIES, type StoopCardDetail } from '../../stoop/stoopTypes';
import { StoopCardSections } from './StoopCardSections';
import { StoopDiscussion } from './StoopDiscussion';

export function StoopCardPage() {
  const { id = '' } = useParams();
  const [params] = useSearchParams();
  const hintedType = params.get('type');
  const typeHint =
    hintedType === 'GROUP' || hintedType === 'WORLD' || hintedType === 'SOLO'
      ? hintedType
      : undefined;
  const { user } = useStoop();
  const canReport = !!user && user.emailVerified !== false;
  const [detail, setDetail] = useState<StoopCardDetail | null>(null);
  const [score, setScore] = useState(0);
  const [myVote, setMyVote] = useState(0);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const [error, setError] = useState('');
  const [reporting, setReporting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setDetail(null);
    setError('');
    stoop
      .cardDetail(id, typeHint)
      .then((d) => {
        if (cancelled) return;
        setDetail(d);
        setScore(d.score);
        setMyVote(d.myVote);
      })
      .catch((e) => {
        if (!cancelled) setError(stoopErrorText(e));
      });
    return () => {
      cancelled = true;
    };
  }, [id, typeHint]);

  const vote = async (value: number) => {
    const next = myVote === value ? 0 : value;
    const prev = { score, myVote };
    setScore(score + next - myVote);
    setMyVote(next);
    try {
      const r = await stoop.vote(id, next);
      setScore(r.score);
      setMyVote(r.myVote);
    } catch {
      setScore(prev.score);
      setMyVote(prev.myVote);
    }
  };

  const download = async () => {
    if (!detail) return;
    setBusy(true);
    setNote('');
    setError('');
    try {
      const kind = stoopCardKind(detail.type, detail.card as CardMap);
      const r = await stoop.download(id, kind);
      setNote(
        kind === 'GROUP'
          ? `“${r.name}” was added to your groups.`
          : kind === 'WORLD'
            ? `“${r.name}” was added to your places.`
            : `“${r.name}” was added to your library.`,
      );
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  if (error && !detail) return <p className="error">{error}</p>;
  if (!detail) return <div className="spinner" aria-label="Loading" />;

  return (
    <div className="stoop-detail">
      <div className="stoop-detail-head">
        <StoopCardArt
          assetId={detail.primaryAssetId}
          name={detail.name}
          className="lib-art stoop-detail-art"
        />
        <div className="stoop-detail-info">
          <h3>
            {detail.name} <StoopBadges card={detail} />
          </h3>
          {detail.creator && (
            <Link to={`/stoop/creator/${encodeURIComponent(detail.creator.id)}`}>
              by {detail.creator.displayName}
              <StoopVerifiedBadge verification={detail.creator.verification} />
            </Link>
          )}
          {detail.originalCreator && (
            <span className="muted stoop-original-creator">
              {detail.creator ? ' · ' : ''}created by {detail.originalCreator}
            </span>
          )}
          <p className="muted">{detail.summary}</p>
          <div className="stoop-detail-meta muted">
            <span>⬇ {detail.downloadCount}</span>
            <span>v{detail.version}</span>
            {detail.tokenCount != null && <span>~{detail.tokenCount} tokens</span>}
          </div>
          {detail.tags.length > 0 && (
            <div className="tag-pills">
              {detail.tags.map((t) => (
                <Link
                  key={t}
                  className="tag-pill"
                  to={`/stoop/browse?q=${encodeURIComponent(`#${t}`)}`}
                >
                  #{t}
                </Link>
              ))}
            </div>
          )}
          <div className="stoop-actions">
            <div className="stoop-vote">
              <button
                className={myVote === 1 ? 'active' : ''}
                onClick={() => void vote(1)}
                aria-label="Upvote"
              >
                ▲
              </button>
              <span>{score}</span>
              <button
                className={myVote === -1 ? 'active' : ''}
                onClick={() => void vote(-1)}
                aria-label="Downvote"
              >
                ▼
              </button>
            </div>
            <button className="primary" disabled={busy} onClick={download}>
              {busy ? 'Adding…' : 'Add to library'}
            </button>
            {canReport ? (
              <button className="link-btn" onClick={() => setReporting(true)}>
                Report
              </button>
            ) : user ? (
              <Link className="link-btn" to="/stoop/account">
                Confirm email to report
              </Link>
            ) : null}
          </div>
          {note && <p className="stoop-note">{note}</p>}
          {error && <p className="error">{error}</p>}
        </div>
      </div>

      <StoopCardSections detail={detail} />
      <StoopDiscussion detail={detail} />

      {reporting && canReport && (
        <ReportDialog
          onClose={() => setReporting(false)}
          onSubmit={async (category, reason) => {
            await stoop.report(id, category, reason);
          }}
        />
      )}
    </div>
  );
}

function ReportDialog({
  onClose,
  onSubmit,
}: {
  onClose: () => void;
  onSubmit: (category: string, reason: string) => Promise<void>;
}) {
  const [category, setCategory] = useState<string>('SPAM');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');

  const submit = async () => {
    const text = reason.trim();
    if (!text) {
      setError('Please add a reason.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await onSubmit(category, text);
      setDone(true);
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        {done ? (
          <>
            <h3>Thanks</h3>
            <p className="dialog-msg">Your report was sent to the mod team.</p>
            <div className="modal-actions">
              <button className="primary" onClick={onClose}>
                Close
              </button>
            </div>
          </>
        ) : (
          <>
            <h3>Report this card</h3>
            <label>
              Reason
              <select value={category} onChange={(e) => setCategory(e.target.value)}>
                {REPORT_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c.replace(/_/g, ' ').toLowerCase()}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Details (required)
              <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} />
            </label>
            {error && <p className="error">{error}</p>}
            <div className="modal-actions">
              <button onClick={onClose}>Cancel</button>
              <button className="primary" disabled={busy} onClick={submit}>
                {busy ? 'Sending…' : 'Send report'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
