// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where chats start" in the world editor (web twin of the desktop
// WorldStartingPlaceSection): the place inside a top-level world where
// every chat that gets the world begins. A new world names one (created
// inside it on save); an existing world picks among its places or names a
// new one. Presentational: the page owns the draft and the save.

/** What a new world with no starting place reports (desktop wording). */
export const STARTING_PLACE_REQUIRED = 'Name the place where chats in this world start.';
/** What a world with places but none chosen reports. */
export const STARTING_PLACE_PICK = 'Pick the place where chats in this world start.';

export type StartingPlaceDraft = {
  /** A place inside the world, '' for "a new place" named below, null for
   * none picked yet. */
  startingPlaceId: string | null;
  startingPlaceName: string;
  startingPlaceDescription: string;
};

/** Why Save must stop for the starting place, or null. Same rule as the
 * desktop: a new world must name one, an existing world with places must
 * pick one, an older world with none may stay as it is. */
export function startingPlaceProblem(
  d: StartingPlaceDraft,
  { isNew, hasPlaces }: { isNew: boolean; hasPlaces: boolean },
): string | null {
  if (d.startingPlaceId) return null;
  if (d.startingPlaceName.trim()) return null;
  if (isNew) return STARTING_PLACE_REQUIRED;
  return hasPlaces ? STARTING_PLACE_PICK : null;
}

/** The relay's `startingPlace` field for a save, or undefined to leave the
 * world's star alone. */
export function startingPlacePayload(
  d: StartingPlaceDraft,
): { placeId: string } | { name: string; description: string } | undefined {
  if (d.startingPlaceId) return { placeId: d.startingPlaceId };
  const name = d.startingPlaceName.trim();
  return name ? { name, description: d.startingPlaceDescription.trim() } : undefined;
}

export function WorldStartingPlaceField({
  draft,
  places,
  isNew,
  error,
  onChange,
}: {
  draft: StartingPlaceDraft;
  /** Places inside the world, in library order, with their label. */
  places: { id: string; label: string }[];
  isNew: boolean;
  error: string | null;
  onChange: (next: Partial<StartingPlaceDraft>) => void;
}) {
  const naming = places.length === 0 || draft.startingPlaceId === '';
  return (
    <div className="wsg-starting-place" data-testid="world-starting-place">
      <span className="muted small">★ Where chats start</span>
      <p className="muted small">
        {!isNew && places.length === 0
          ? 'Name a place inside this world and chats that get it will begin there, with the world’s lore and weather.'
          : 'Chats that get this world begin in this place, with the world’s lore and weather.'}
      </p>
      {places.length > 0 && (
        <label className="cg-field">
          <select
            aria-label="Where chats start"
            value={draft.startingPlaceId ?? '__none__'}
            onChange={(e) =>
              onChange({ startingPlaceId: e.target.value === '__none__' ? null : e.target.value })
            }
          >
            <option value="__none__" disabled>
              Pick a place
            </option>
            {places.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
            <option value="">A new place…</option>
          </select>
        </label>
      )}
      {naming && (
        <>
          <label className="cg-field">
            <span className="muted small">Starting place</span>
            <input
              aria-label="Starting place"
              placeholder="e.g. The Tea Rooms"
              value={draft.startingPlaceName}
              onChange={(e) => onChange({ startingPlaceName: e.target.value })}
            />
          </label>
          <label className="cg-field">
            <span className="muted small">What is it like there? (optional)</span>
            <textarea
              aria-label="Starting place description"
              rows={2}
              placeholder="Steam, gossip and a cracked bell over the door."
              value={draft.startingPlaceDescription}
              onChange={(e) => onChange({ startingPlaceDescription: e.target.value })}
            />
          </label>
        </>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
