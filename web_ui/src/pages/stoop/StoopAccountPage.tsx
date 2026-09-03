// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop account — profile (display name), NSFW preference, authenticator 2FA
// (QR enroll + code confirm, code-gated disable), your uploads with their
// moderation status, your past downloads, creators you follow, sign out and
// account deletion. Mirrors the desktop account sheet feature-for-feature.

import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { StoopCardArt, StoopCardTile } from '../../components/stoop/StoopCardTile';
import { StoopCreatorAvatar } from '../../components/stoop/StoopCreatorAvatar';
import { StoopVerifiedBadge } from '../../components/stoop/StoopVerifiedBadge';
import { stoop, StoopError, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import type { StoopCard, StoopFollowedCreator, StoopMine } from '../../stoop/stoopTypes';

/** Center-crop to a square (max 512px), encoded as JPEG — same treatment the
 *  hub site applies, so avatars land round-crop-safe and small. */
function squareCropAvatar(file: File): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      try {
        const side = Math.min(img.naturalWidth, img.naturalHeight);
        const out = Math.min(side, 512);
        const canvas = document.createElement('canvas');
        canvas.width = out;
        canvas.height = out;
        canvas
          .getContext('2d')!
          .drawImage(
            img,
            (img.naturalWidth - side) / 2,
            (img.naturalHeight - side) / 2,
            side,
            side,
            0,
            0,
            out,
            out,
          );
        canvas.toBlob(
          (b) => {
            URL.revokeObjectURL(url);
            if (b) resolve(b);
            else reject(new Error('Couldn’t read that image.'));
          },
          'image/jpeg',
          0.9,
        );
      } catch (e) {
        URL.revokeObjectURL(url);
        reject(e instanceof Error ? e : new Error('Couldn’t read that image.'));
      }
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Couldn’t read that image.'));
    };
    img.src = url;
  });
}

const STATUS_LABEL: Record<StoopMine['status'], string> = {
  PENDING: 'In review',
  APPROVED: 'Live',
  REJECTED: 'Rejected',
  TAKEN_DOWN: 'Taken down',
};

export function StoopAccountPage() {
  const { user, updateUser, signOut } = useStoop();
  const [name, setName] = useState(user?.displayName ?? '');
  const [bio, setBio] = useState(user?.bio ?? '');
  const [links, setLinks] = useState<string[]>(() => {
    const l = user?.profileLinks ?? [];
    return [l[0] ?? '', l[1] ?? '', l[2] ?? '', l[3] ?? ''];
  });
  const fileRef = useRef<HTMLInputElement>(null);
  const [emailOpen, setEmailOpen] = useState(false);
  const [newEmail, setNewEmail] = useState('');
  const [emailPw, setEmailPw] = useState('');
  const [emailTotp, setEmailTotp] = useState('');
  const [emailTotpNeeded, setEmailTotpNeeded] = useState(false);
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

  const saveProfile = () =>
    run(async () => {
      const cleaned = links.map((l) => l.trim()).filter(Boolean);
      if (cleaned.some((l) => !/^https?:\/\/.+/.test(l))) {
        setError('Links must start with http:// or https://');
        return;
      }
      const r = await stoop.updateProfile(bio.trim(), cleaned);
      updateUser(r.user);
      setNote('Profile updated.');
    });

  const canAvatar = user?.emailVerified !== false && !user?.avatarLocked;

  const pickAvatar = (file: File | null) => {
    if (!file) return;
    void run(async () => {
      const blob = await squareCropAvatar(file);
      const r = await stoop.uploadAvatar(blob);
      updateUser(r.user);
      setNote('Profile photo updated — it’s live.');
    });
  };

  const removeAvatar = () =>
    run(async () => {
      const r = await stoop.deleteAvatar();
      updateUser(r.user);
      setNote('Profile photo removed.');
    });

  const resendVerify = () =>
    run(async () => {
      await stoop.resendVerification();
      setNote('Confirmation email sent — check your inbox (and spam).');
    });

  const submitEmailChange = async () => {
    setBusy(true);
    setNote('');
    setError('');
    try {
      const r = await stoop.changeEmail(
        newEmail.trim(),
        emailPw,
        emailTotpNeeded ? emailTotp.trim() : undefined,
      );
      updateUser(r.user);
      setEmailOpen(false);
      setNewEmail('');
      setEmailPw('');
      setEmailTotp('');
      setEmailTotpNeeded(false);
      setNote(`Confirmation sent to ${newEmail.trim()} — the change lands when that inbox opens the link.`);
    } catch (e) {
      if (e instanceof StoopError && e.code === 'two_factor_required') {
        setEmailTotpNeeded(true);
        setError(emailTotp ? stoopErrorText(e) : 'Enter your two-factor code to confirm the change.');
      } else {
        setError(stoopErrorText(e));
      }
    } finally {
      setBusy(false);
    }
  };

  const cancelEmailChange = () =>
    run(async () => {
      const r = await stoop.cancelEmailChange();
      updateUser(r.user);
      setNote('Pending email change cancelled.');
    });

  const deleteUpload = (m: StoopMine) => {
    if (!window.confirm(`Take “${m.name}” off The Stoop permanently? Copies people already downloaded stay theirs.`)) {
      return;
    }
    void run(async () => {
      await stoop.deleteCharacter(m.id);
      setMine((prev) => prev.filter((x) => x.id !== m.id));
      setNote(`“${m.name}” was removed from The Stoop.`);
    });
  };

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
          {user.email} · {user.role !== 'USER' ? `${user.role} · ` : ''}age verified{' '}
          <button className="link-btn" onClick={() => setEmailOpen(!emailOpen)}>
            Change email…
          </button>
        </p>
        {user.pendingEmail && (
          <p className="muted stoop-small">
            → {user.pendingEmail} (awaiting confirmation){' '}
            <button className="link-btn" disabled={busy} onClick={cancelEmailChange}>
              Cancel
            </button>
          </p>
        )}
        {emailOpen && (
          <div className="stoop-email-change">
            <p className="muted stoop-small">
              We’ll send a confirmation link to the new address; your account keeps{' '}
              {user.email} until that link is opened. This also proves the new address
              for sharing and profile photos.
            </p>
            <label>
              New email
              <input
                type="email"
                value={newEmail}
                onChange={(e) => setNewEmail(e.target.value)}
              />
            </label>
            <label>
              Current password
              <input
                type="password"
                autoComplete="current-password"
                value={emailPw}
                onChange={(e) => setEmailPw(e.target.value)}
              />
            </label>
            {emailTotpNeeded && (
              <label>
                Two-factor code
                <input
                  inputMode="numeric"
                  placeholder="123456"
                  value={emailTotp}
                  onChange={(e) => setEmailTotp(e.target.value)}
                />
              </label>
            )}
            <button
              className="primary"
              disabled={busy || !newEmail.includes('@')}
              onClick={() => void submitEmailChange()}
            >
              Send confirmation
            </button>
          </div>
        )}
        {user.emailVerified === false && (
          <p className="stoop-verify-note">
            📮 Confirm your email to share cards and set a profile photo.{' '}
            <button className="link-btn" disabled={busy} onClick={resendVerify}>
              Send the link again
            </button>
          </p>
        )}
        <div className="stoop-ava-row">
          <StoopCreatorAvatar assetId={user.avatarAssetId} name={user.displayName} size={52} />
          <button disabled={busy || !canAvatar} onClick={() => fileRef.current?.click()}>
            {user.avatarAssetId ? 'Change photo…' : 'Choose photo…'}
          </button>
          {user.avatarAssetId && (
            <button className="danger" disabled={busy} onClick={removeAvatar}>
              Remove
            </button>
          )}
          <input
            ref={fileRef}
            type="file"
            accept="image/png,image/jpeg,image/webp"
            hidden
            onChange={(e) => {
              pickAvatar(e.target.files?.[0] ?? null);
              e.target.value = '';
            }}
          />
        </div>
        <p className="muted stoop-small">
          {user.avatarLocked
            ? 'A moderator has disabled profile pictures for this account. You can appeal from your inbox.'
            : 'Shows beside your name across The Stoop, immediately. Keep it porch-front friendly — visitors see it without an 18+ check, and a moderator removing an avatar counts as a formal warning.'}
        </p>
        <label>
          Display name
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <button disabled={busy || !name.trim() || name.trim() === user.displayName} onClick={saveName}>
          Save name
        </button>
        <label>
          Bio
          <textarea
            rows={3}
            maxLength={300}
            placeholder="A short bio for your public porch page (300 characters max)."
            value={bio}
            onChange={(e) => setBio(e.target.value)}
          />
        </label>
        <label>
          Links (up to 4, shown on your public page)
          {links.map((l, i) => (
            <input
              key={i}
              type="url"
              maxLength={200}
              placeholder={i === 0 ? 'https:// — your chub / Backyard / socials' : 'https://…'}
              value={l}
              onChange={(e) =>
                setLinks((prev) => prev.map((x, j) => (j === i ? e.target.value : x)))
              }
            />
          ))}
        </label>
        <button disabled={busy} onClick={saveProfile}>
          Save profile
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
          <div className="lib-grid stoop-grid stoop-mine-grid">
            {mine.map((m) => (
              <div className="lib-card stoop-tile stoop-mine-tile" key={m.id}>
                {m.status === 'APPROVED' ? (
                  <Link
                    to={`/stoop/card/${encodeURIComponent(m.id)}?type=${encodeURIComponent(m.type)}`}
                    className="stoop-mine-art"
                  >
                    <StoopCardArt assetId={m.primaryAssetId} name={m.name} />
                  </Link>
                ) : (
                  <span className="stoop-mine-art">
                    <StoopCardArt assetId={m.primaryAssetId} name={m.name} />
                  </span>
                )}
                <span className={`stoop-status stoop-mine-status ${m.status.toLowerCase()}`}>
                  {STATUS_LABEL[m.status]}
                </span>
                <div className="lib-info">
                  <div className="lib-name-row">
                    <span className="lib-name">{m.name}</span>
                  </div>
                  <div className="stoop-tile-meta">
                    <span>v{m.version} · ⬇ {m.downloadCount}</span>
                    <button
                      className="link-btn stoop-delete-link"
                      disabled={busy}
                      onClick={() => deleteUpload(m)}
                    >
                      Delete
                    </button>
                  </div>
                  {m.status === 'REJECTED' && m.rejectionNote && (
                    <p className="muted stoop-reject-note">{m.rejectionNote}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
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
                <Link to={`/stoop/creator/${encodeURIComponent(c.id)}`}>
                  <StoopCreatorAvatar assetId={c.avatarAssetId} name={c.displayName} size={24} />{' '}
                  {c.displayName}
                  <StoopVerifiedBadge verification={c.verification} />
                </Link>
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
