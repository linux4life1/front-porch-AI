// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → the Porch Life pointer card: the feature toggles
// moved to the Porch Life tab (2026-08-07); this card is all that remains
// of them in General. Twin of the desktop's PorchLifePointerCard
// (lib/ui/settings/tabs/general_tab/porch_life_pointer_card.dart),
// one-chat-ux PR 7a.

export function PorchLifePointerCard() {
  return (
    <div className="porch-life-pointer" data-testid="porch-life-pointer">
      <span className="porch-life-pointer-icon" aria-hidden="true">🛖</span>
      <p>
        The Realism Engine, passage of time, weather, the Journal, dreams,
        promises, ambitions and the welcome-back recap all live in the Porch
        Life section now — each one saying plainly what it needs.
      </p>
    </div>
  );
}
