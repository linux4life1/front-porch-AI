// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Uploads, downloads, and following lists for the Stoop account page.

import { Link } from 'react-router-dom';
import { StoopCardArt, StoopCardTile } from '../../components/stoop/StoopCardTile';
import { StoopCreatorAvatar } from '../../components/stoop/StoopCreatorAvatar';
import { StoopVerifiedBadge } from '../../components/stoop/StoopVerifiedBadge';
import type { StoopCard, StoopFollowedCreator, StoopMine } from '../../stoop/stoopTypes';

const STATUS_LABEL: Record<StoopMine['status'], string> = {
  PENDING: 'In review',
  APPROVED: 'Live',
  REJECTED: 'Rejected',
  TAKEN_DOWN: 'Taken down',
};

export function StoopAccountCollections({
  mine,
  downloads,
  followed,
  busy,
  onDeleteUpload,
}: {
  mine: StoopMine[];
  downloads: StoopCard[];
  followed: StoopFollowedCreator[];
  busy: boolean;
  onDeleteUpload: (m: StoopMine) => void;
}) {
  return (
    <>
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
                    <span>
                      v{m.version} · ⬇ {m.downloadCount}
                    </span>
                    <button
                      className="link-btn stoop-delete-link"
                      disabled={busy}
                      onClick={() => onDeleteUpload(m)}
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
    </>
  );
}
