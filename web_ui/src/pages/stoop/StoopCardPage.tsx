// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop card detail — definition sections, tags, votes (optimistic with
// revert, like the desktop), download-to-library and report. The download
// itself runs on the desktop server (it owns the library); this page just
// asks and reports the outcome.

import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { StoopBadges, StoopCardArt } from '../../components/stoop/StoopCardTile';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { REPORT_CATEGORIES, type StoopCardDetail } from '../../stoop/stoopTypes';

const CARD_SECTIONS: { key: string; label: string }[] = [
  { key: 'description', label: 'Description' },
  { key: 'personality', label: 'Personality' },
  { key: 'scenario', label: 'Scenario' },
  { key: 'first_mes', label: 'Greeting' },
];

export function StoopCardPage() {
  const { id = '' } = useParams();
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
      .cardDetail(id)
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
  }, [id]);

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
      const r = await stoop.download(id, detail.type);
      setNote(
        detail.type === 'GROUP'
          ? `“${r.name}” was added to your groups.`
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

  const cardText = (key: string): string => {
    const v = detail.card[key];
    return typeof v === 'string' ? v.trim() : '';
  };

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
            <button className="link-btn" onClick={() => setReporting(true)}>
              Report
            </button>
          </div>
          {note && <p className="stoop-note">{note}</p>}
          {error && <p className="error">{error}</p>}
        </div>
      </div>

      {CARD_SECTIONS.map(({ key, label }) => {
        const text = cardText(key);
        if (!text) return null;
        return (
          <section key={key} className="card stoop-section">
            <h4>{label}</h4>
            <p className="stoop-pre">{text}</p>
          </section>
        );
      })}

      {reporting && (
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
    setBusy(true);
    setError('');
    try {
      await onSubmit(category, reason.trim());
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
              Details (optional)
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
