// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Stoop card tile — used by the browse grid, home carousels, creator
// pages and the downloads list. Mirrors the library's .lib-card look so the
// hub feels native to the rest of the web UI.

import { useNavigate } from 'react-router-dom';
import { stoop } from '../../stoop/stoopApi';
import { stoopCardClimateEnabled } from '../../stoop/stoopCardBody';
import type { StoopCard } from '../../stoop/stoopTypes';
import { StoopVerifiedBadge } from './StoopVerifiedBadge';

export function StoopCardArt({
  assetId,
  name,
  className,
}: {
  assetId: string | null;
  name: string;
  className?: string;
}) {
  return (
    <div className={className ?? 'lib-art'}>
      {assetId ? (
        <img
          src={stoop.assetUrl(assetId)}
          alt=""
          loading="lazy"
          onError={(e) => {
            (e.target as HTMLImageElement).style.display = 'none';
          }}
        />
      ) : (
        <span className="lib-art-fallback">{name.charAt(0).toUpperCase() || '?'}</span>
      )}
    </div>
  );
}

export function StoopBadges({ card }: { card: StoopCard }) {
  const climateEnabled =
    card.type === 'WORLD' && stoopCardClimateEnabled(card);
  return (
    <span className="stoop-badges">
      {card.modPick && (
        <span className="stoop-badge pick" title="Mod pick">
          ★
        </span>
      )}
      {card.type === 'GROUP' && <span className="stoop-badge group">Group</span>}
      {card.type === 'WORLD' && (
        <>
          <span className="stoop-badge world">World</span>
          <span
            className={`stoop-badge ${climateEnabled ? 'climate' : 'lore'}`}
          >
            {climateEnabled ? 'Climate' : 'Lore'}
          </span>
        </>
      )}
      {card.nsfw && <span className="stoop-badge nsfw">NSFW</span>}
    </span>
  );
}

export function StoopCardTile({ card }: { card: StoopCard }) {
  const navigate = useNavigate();
  return (
    <div className="lib-card stoop-tile">
      <button
        className="lib-open"
        onClick={() =>
          navigate(
            `/stoop/card/${encodeURIComponent(card.id)}?type=${encodeURIComponent(card.type)}`,
          )
        }
      >
        <StoopCardArt assetId={card.primaryAssetId} name={card.name} />
        <div className="lib-info">
          <div className="lib-name-row">
            <span className="lib-name">{card.name}</span>
            <StoopBadges card={card} />
          </div>
          <div className="stoop-tile-meta">
            <span title="Score">▲ {card.score}</span>
            <span title="Downloads">⬇ {card.downloadCount}</span>
            {card.creator && (
              <span className="muted">
                {card.creator.displayName}
                <StoopVerifiedBadge verification={card.creator.verification} />
              </span>
            )}
            {card.originalCreator && (
              <span className="muted" title="Original creator (credited repost)">
                ✎ {card.originalCreator}
              </span>
            )}
          </div>
        </div>
      </button>
    </div>
  );
}
