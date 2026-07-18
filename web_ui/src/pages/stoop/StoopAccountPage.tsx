// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop account — profile (display name), NSFW preference, authenticator 2FA
// (QR enroll + code confirm, code-gated disable), your uploads with their
// moderation status, your past downloads, creators you follow, sign out and
// account deletion. Mirrors the desktop account sheet feature-for-feature.

import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { StoopCardTile } from '../../components/stoop/StoopCardTile';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import type { StoopCard, StoopFollowedCreator, StoopMine } from '../../stoop/stoopTypes';

const STATUS_LABEL: Record<StoopMine['status'], string> = {
  PENDING: 'In review',
  APPROVED: 'Live',
  REJECTED: 'Rejected',
  TAKEN_DOWN: 'Taken down',
};

export function StoopAccountPage() {
  const { user, updateUser, signOut } = useStoop();
  const [name, setName] = useState(user?.displayName ?? '');
  const [mine, setMine] = useState<StoopMine[]>([]);
  const [downloads, setDownloads] = useState<StoopCard[]>([]);
  const [followed, setFollowed] = useState<StoopFollowedCreator[]>([]);
  const [enroll, setEnroll] = useState<{ qrDataUrl: string; secret: string } | null>(null);
  const [code, setCode] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    stoop.myCharacters().then((r) => setMine(r.items)).catch(() => {});
    stoop.myDownloads().then((r) => setDownloads(r.items)).catch(() => {});
    stoop.myFollowing().then((r) => setFollowed(r.items)).catch(() => {});
  }, []);

  if (!user) return null;

  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    setNote('');
    setError('');
    try {
      await fn();
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  const saveName = () =>
    run(async () => {
      const r = await stoop.setDisplayName(name.trim());
      updateUser(r.user);
      setNote('Display name updated.');
    });

  const toggleNsfw = () =>
    run(async () => {
      const r = await stoop.setNsfwEnabled(!user.nsfwEnabled);
      updateUser(r.user);
    });

  const begin2fa = () =>
    run(async () => {
      setEnroll(await stoop.twoFactorSetup());
    });

  const confirm2fa = () =>
    run(async () => {
      await stoop.twoFactorEnable(code.trim());
      const r = await stoop.me();
      updateUser(r.user);
      setEnroll(null);
      setCode('');
      setNote('Two-factor authentication is on.');
    });

  const disable2fa = () =>
    run(async () => {
      await stoop.twoFactorDisable(code.trim());
      const r = await stoop.me();
      updateUser(r.user);
      setCode('');
      setNote('Two-factor authentication is off.');
    });

  const deleteAccount = () =>
    run(async () => {
      await stoop.deleteAccount();
      await signOut();
    });

  return (
    <div className="stoop-account">
      {note && <p className="stoop-note">{note}</p>}
      {error && <p className="error">{error}</p>}

      <section className="card">
        <h3>Profile</h3>
        <p className="muted">
          {user.email} · {user.role !== 'USER' ? `${user.role} · ` : ''}age verified
        </p>
        <label>
          Display name
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <button disabled={busy || !name.trim() || name.trim() === user.displayName} onClick={saveName}>
          Save name
        </button>
      </section>

      <section className="card">
        <h3>Content</h3>
        <label className="stoop-toggle">
          <input type="checkbox" checked={user.nsfwEnabled} onChange={toggleNsfw} disabled={busy} />
          Show NSFW cards
        </label>
      </section>

      <section className="card">
        <h3>Two-factor authentication</h3>
        {user.twoFactorEnabled ? (
          <>
            <p className="muted">2FA is on. Enter a current code to turn it off.</p>
            <label>
              Code
              <input
                inputMode="numeric"
                placeholder="123456"
                value={code}
                onChange={(e) => setCode(e.target.value)}
              />
            </label>
            <button disabled={busy || !code.trim()} onClick={disable2fa}>
              Turn off 2FA
            </button>
          </>
        ) : enroll ? (
          <>
            <p className="muted">Scan with an authenticator app, then enter the 6-digit code.</p>
            <div className="qr">
              <img src={enroll.qrDataUrl} alt="2FA QR code" width={180} height={180} />
            </div>
            <p className="muted">
              Secret: <code>{enroll.secret}</code>
            </p>
            <label>
              Code
              <input
                inputMode="numeric"
                placeholder="123456"
                value={code}
                onChange={(e) => setCode(e.target.value)}
              />
            </label>
            <button className="primary" disabled={busy || !code.trim()} onClick={confirm2fa}>
              Confirm &amp; enable
            </button>
          </>
        ) : (
          <button className="primary" disabled={busy} onClick={begin2fa}>
            Set up 2FA
          </button>
        )}
      </section>

      <section className="card">
        <h3>Your uploads</h3>
        {mine.length === 0 ? (
          <p className="muted">Nothing shared yet.</p>
        ) : (
          <ul className="stoop-mine">
            {mine.map((m) => (
              <li key={m.id}>
                <span>
                  {m.status === 'APPROVED' ? (
                    <Link to={`/stoop/card/${encodeURIComponent(m.id)}`}>{m.name}</Link>
                  ) : (
                    m.name
                  )}{' '}
                  <span className="muted">v{m.version} · ⬇ {m.downloadCount}</span>
                </span>
                <span className={`stoop-status ${m.status.toLowerCase()}`}>
                  {STATUS_LABEL[m.status]}
                </span>
                {m.status === 'REJECTED' && m.rejectionNote && (
                  <p className="muted stoop-reject-note">{m.rejectionNote}</p>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card">
        <h3>Your downloads</h3>
        {downloads.length === 0 ? (
          <p className="muted">Nothing downloaded yet.</p>
        ) : (
          <div className="lib-grid stoop-grid">
            {downloads.map((c) => (
              <StoopCardTile key={c.id} card={c} />
            ))}
          </div>
        )}
      </section>

      <section className="card">
        <h3>Following</h3>
        {followed.length === 0 ? (
          <p className="muted">You aren’t following anyone yet.</p>
        ) : (
          <ul className="stoop-following">
            {followed.map((c) => (
              <li key={c.id}>
                <Link to={`/stoop/creator/${encodeURIComponent(c.id)}`}>{c.displayName}</Link>
                <span className="muted">
                  {c.followers} follower{c.followers === 1 ? '' : 's'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card stoop-danger">
        <h3>Account</h3>
        <button disabled={busy} onClick={() => void signOut()}>
          Sign out on this device
        </button>
        {confirmDelete ? (
          <div className="stoop-delete-confirm">
            <p className="error">
              This permanently deletes your Stoop account, uploads and messages. There is
              no undo.
            </p>
            <div className="modal-actions">
              <button onClick={() => setConfirmDelete(false)}>Keep my account</button>
              <button className="danger" disabled={busy} onClick={deleteAccount}>
                Delete forever
              </button>
            </div>
          </div>
        ) : (
          <button className="link-btn stoop-delete-link" onClick={() => setConfirmDelete(true)}>
            Delete my account…
          </button>
        )}
      </section>
    </div>
  );
}
