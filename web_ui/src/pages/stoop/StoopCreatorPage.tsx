// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop creator profile — follower count, follow/unfollow (hidden on your own
// profile, like the desktop) and the creator's approved cards.

import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { StoopCardTile } from '../../components/stoop/StoopCardTile';
import { StoopCreatorAvatar } from '../../components/stoop/StoopCreatorAvatar';
import { StoopVerifiedBadge } from '../../components/stoop/StoopVerifiedBadge';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import type { StoopCreator } from '../../stoop/stoopTypes';

function monthYear(iso?: string): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
}

export function StoopCreatorPage() {
  const { id = '' } = useParams();
  const [creator, setCreator] = useState<StoopCreator | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    setCreator(null);
    setError('');
    stoop
      .creator(id)
      .then((c) => {
        if (!cancelled) setCreator(c);
      })
      .catch((e) => {
        if (!cancelled) setError(stoopErrorText(e));
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  const toggleFollow = async () => {
    if (!creator) return;
    setBusy(true);
    try {
      const r = await stoop.setFollow(id, !creator.following);
      setCreator({ ...creator, following: r.following, followers: r.followers });
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  if (error && !creator) return <p className="error">{error}</p>;
  if (!creator) return <div className="spinner" aria-label="Loading" />;

  const since = monthYear(creator.createdAt);
  const stats = creator.stats;
  const creatorLinks = (creator.links ?? []).filter(Boolean);
  return (
    <div className="stoop-creator">
      <div className="stoop-creator-head">
        <StoopCreatorAvatar assetId={creator.avatarAssetId} name={creator.displayName} size={56} />
        <div>
          <h3>
            {creator.displayName}
            <StoopVerifiedBadge verification={creator.verification} />
          </h3>
          {since && <p className="muted stoop-small">On the porch since {since}</p>}
          <p className="muted">
            {creator.followers} follower{creator.followers === 1 ? '' : 's'}
            {stats
              ? ` · ${stats.cards} card${stats.cards === 1 ? '' : 's'} · ${stats.downloads} downloads · ▲ ${stats.score} net votes`
              : ` · ${creator.cards.length} card${creator.cards.length === 1 ? '' : 's'}`}
          </p>
        </div>
        {!creator.isMe && (
          <button
            className={creator.following ? '' : 'primary'}
            disabled={busy}
            onClick={toggleFollow}
          >
            {creator.following ? 'Unfollow' : 'Follow'}
          </button>
        )}
      </div>
      {creator.bio?.trim() && <p className="stoop-creator-bio">{creator.bio.trim()}</p>}
      {creatorLinks.length > 0 && (
        <p className="stoop-creator-links">
          {creatorLinks.map((u) => (
            <a key={u} href={u} target="_blank" rel="noopener nofollow">
              🔗 {u.replace(/^https?:\/\//, '').replace(/\/$/, '')}
            </a>
          ))}
        </p>
      )}
      {error && <p className="error">{error}</p>}
      <div className="lib-grid stoop-grid">
        {creator.cards.map((c) => (
          <StoopCardTile key={c.id} card={c} />
        ))}
      </div>
      {creator.cards.length === 0 && <p className="muted">No cards published yet.</p>}
    </div>
  );
}
