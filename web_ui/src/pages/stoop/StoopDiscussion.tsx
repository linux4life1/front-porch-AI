// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Stoop Discussion on a card. Hits the hub through the Dart relay —
// not an in-memory notepad.

import { useEffect, useState } from 'react';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import { StoopVerifiedBadge } from '../../components/stoop/StoopVerifiedBadge';
import {
  REPORT_CATEGORIES,
  type StoopComment,
  type StoopCardDetail,
} from '../../stoop/stoopTypes';

const MAX = 1000;

function itemsOf(
  r: StoopComment[] | { items?: StoopComment[]; comments?: StoopComment[] },
): StoopComment[] {
  const raw = Array.isArray(r) ? r : (r.items ?? r.comments ?? []);
  return [...raw].sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );
}

export function StoopDiscussion({ detail }: { detail: StoopCardDetail }) {
  const { user } = useStoop();
  const isOwner = !!user && user.id === detail.creator?.id;
  const [enabled, setEnabled] = useState(detail.commentsEnabled === true);
  const [locked, setLocked] = useState(detail.commentsLocked === true);
  const live = enabled && !locked;
  const [comments, setComments] = useState<StoopComment[]>([]);
  const [loading, setLoading] = useState(live);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [replyTo, setReplyTo] = useState<string | null>(null);
  const [replyDraft, setReplyDraft] = useState('');
  const [reportFor, setReportFor] = useState<string | null>(null);

  useEffect(() => {
    if (!live) return;
    let cancelled = false;
    setLoading(true);
    stoop
      .comments(detail.id)
      .then((r) => {
        if (!cancelled) setComments(itemsOf(r));
      })
      .catch((e) => {
        if (!cancelled) {
          // Fail-closed: a 403/error is "discussion is not on", not an empty thread.
          setEnabled(false);
          setError(stoopErrorText(e));
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [detail.id, live]);

  if (!isOwner && !live) return null;

  const setFlags = async (next: { commentsEnabled?: boolean; commentsLocked?: boolean }) => {
    setError('');
    try {
      const flags = await stoop.setCommentFlags(detail.id, next);
      setEnabled(flags.commentsEnabled === true);
      setLocked(flags.commentsLocked === true);
    } catch (e) {
      setError(stoopErrorText(e));
    }
  };

  const post = async () => {
    const body = draft.trim();
    if (!body || busy) return;
    setBusy(true);
    setError('');
    try {
      const created = await stoop.postComment(detail.id, body);
      setComments((prev) => itemsOf([created, ...prev]));
      setDraft('');
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  const canWrite = !!user && user.emailVerified !== false;

  return (
    <section className="card stoop-section">
      <h4>Discussion</h4>
      {isOwner && (
        <label className="row-label">
          <span>Allow discussion on this card</span>
          <input
            type="checkbox"
            checked={live}
            onChange={(e) => {
              const on = e.target.checked;
              void setFlags(
                on
                  ? { commentsEnabled: true, commentsLocked: false }
                  : enabled
                    ? { commentsLocked: true }
                    : { commentsEnabled: false },
              );
            }}
          />
        </label>
      )}
      {live && (
        <>
          {!user ? (
            <p className="muted small">Sign in to comment.</p>
          ) : !canWrite ? (
            <p className="muted small">Confirm email to comment.</p>
          ) : (
            <label>
              Write a comment
              <textarea
                rows={3}
                maxLength={MAX}
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
              />
            </label>
          )}
          {canWrite && (
            <button className="primary" disabled={busy || !draft.trim()} onClick={() => void post()}>
              {busy ? 'Posting…' : 'Post'}
            </button>
          )}
          {error && <p className="error">{error}</p>}
          {loading ? (
            <div className="spinner" aria-label="Loading comments" />
          ) : comments.length === 0 ? (
            <p className="muted small">No comments yet.</p>
          ) : (
            <ul className="stoop-ambitions">
              {comments.map((c) => (
                <li key={c.id} className="stoop-comment">
                  <p className="muted small">
                    @{c.displayName || 'someone'}
                    <StoopVerifiedBadge verification={c.verification} /> ·{' '}
                    {new Date(c.createdAt).toLocaleString()}
                  </p>
                  <p className="stoop-pre">{c.deleted ? '(deleted)' : c.body}</p>
                  <div className="stoop-comment-actions">
                    {(user?.id === c.authorId || user?.role === 'MOD' || user?.role === 'OWNER' || isOwner) &&
                      !c.deleted && (
                        <button
                          className="link-btn"
                          onClick={() =>
                            void stoop.deleteComment(detail.id, c.id).then((u) =>
                              setComments((prev) => prev.map((x) => (x.id === u.id ? u : x))),
                            )
                          }
                        >
                          Delete
                        </button>
                      )}
                    {user && user.id !== c.authorId && !c.deleted && (
                      <button className="link-btn" onClick={() => setReportFor(c.id)}>
                        Report
                      </button>
                    )}
                    {isOwner && user && user.id !== c.authorId && !c.deleted && !c.reply && (
                      <button className="link-btn" onClick={() => setReplyTo(c.id)}>
                        Reply
                      </button>
                    )}
                  </div>
                  {c.reply && (
                    <div className="stoop-comment-reply">
                      <p className="muted small">
                        @{c.reply.displayName} (author)
                        <StoopVerifiedBadge verification={c.reply.verification} />
                      </p>
                      <p className="stoop-pre">{c.reply.deleted ? '(deleted)' : c.reply.body}</p>
                    </div>
                  )}
                  {replyTo === c.id && (
                    <label>
                      Reply
                      <textarea
                        rows={2}
                        maxLength={MAX}
                        value={replyDraft}
                        onChange={(e) => setReplyDraft(e.target.value)}
                      />
                      <button
                        className="primary"
                        disabled={!replyDraft.trim()}
                        onClick={() => {
                          void stoop
                            .replyComment(detail.id, c.id, replyDraft.trim())
                            .then((u) => {
                              setComments((prev) => prev.map((x) => (x.id === u.id ? u : x)));
                              setReplyTo(null);
                              setReplyDraft('');
                            })
                            .catch((e) => setError(stoopErrorText(e)));
                        }}
                      >
                        Send reply
                      </button>
                    </label>
                  )}
                  {reportFor === c.id && (
                    <ReportBox
                      onClose={() => setReportFor(null)}
                      onSubmit={(category, reason) =>
                        stoop.reportComment(detail.id, c.id, category, reason)
                      }
                    />
                  )}
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </section>
  );
}

function ReportBox({
  onClose,
  onSubmit,
}: {
  onClose: () => void;
  onSubmit: (category: string, reason: string) => Promise<void>;
}) {
  const [category, setCategory] = useState<string>(REPORT_CATEGORIES[0] ?? 'SPAM');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  return (
    <div className="stoop-comment-report">
      <select value={category} onChange={(e) => setCategory(e.target.value)}>
        {REPORT_CATEGORIES.map((c) => (
          <option key={c} value={c}>
            {c.replace(/_/g, ' ').toLowerCase()}
          </option>
        ))}
      </select>
      <textarea
        rows={2}
        value={reason}
        placeholder="Why are you reporting this?"
        onChange={(e) => setReason(e.target.value)}
      />
      {error && <p className="error">{error}</p>}
      <button
        className="primary"
        disabled={busy || !reason.trim()}
        onClick={() => {
          setBusy(true);
          void onSubmit(category, reason.trim())
            .then(onClose)
            .catch((e) => setError(stoopErrorText(e)))
            .finally(() => setBusy(false));
        }}
      >
        Send report
      </button>
      <button onClick={onClose}>Cancel</button>
    </div>
  );
}
