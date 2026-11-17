// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The new-group wizard's per-member Starts away, the phone's twin of the
// switch on each desktop Members row (docs/design/group-initial-presence.md).
// A member whose switch was touched rides: true lands them Away in every
// chat the group creates, false keeps them present even on a card that asks
// to start away. No pick keeps the card's own switch, shown unless the card
// could not be read. Each row is the tool-toggle idiom (label left, control
// right) so the checkbox rides beside the name, not on a line of its own.

export function MemberStartsAwayPicks({
  members,
  cardStartsAway,
  picks,
  set,
}: {
  members: { id: string; name: string }[];
  /** Library id → the card's own switch, once it has loaded. */
  cardStartsAway: Record<string, boolean>;
  picks: Record<string, boolean>;
  set: (next: Record<string, boolean>) => void;
}) {
  if (members.length === 0) return null;
  const pick = (id: string, away: boolean) => set({ ...picks, [id]: away });
  const state = (id: string) =>
    id in picks
      ? picks[id]
        ? 'away in every chat here'
        : 'present in every chat here'
      : "their card's own";
  return (
    <div className="cg-field" data-testid="member-starts-away">
      <span className="cg-field-label">Starts away</span>
      {members.map((m) => (
        <label key={m.id} className="tool-toggle" data-testid={`starts-away-row-${m.id}`}>
          <span>
            {m.name}{' '}
            <span className="muted small" data-testid={`starts-away-value-${m.id}`}>
              {state(m.id)}
            </span>
          </span>
          <input
            type="checkbox"
            data-testid={`starts-away-check-${m.id}`}
            checked={m.id in picks ? picks[m.id] : (cardStartsAway[m.id] ?? false)}
            onChange={(e) => pick(m.id, e.target.checked)}
          />
        </label>
      ))}
    </div>
  );
}
