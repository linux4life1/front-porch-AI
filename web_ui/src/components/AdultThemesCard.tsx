// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → 18+ themes: the adult master switch, which lives in
// General on the desktop (not in the Porch Life tab) because it hides that
// tab's After Dark group — inside the thing it hides there would be no way
// back on. Turning it on while the engine runs asks about applying
// Afterglow to existing chats, as the desktop does. One-chat-ux PR 7a.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import { ExistingChatsOffer, type OfferFeature } from './ExistingChatsOffer';

export function AdultThemesCard() {
  // Null until the host has answered; each field gates its own control.
  const [st, setSt] = useState<{
    adultThemesEnabled: boolean;
    realismAllowed: boolean;
    nsfwCooldownDefault: boolean;
  } | null>(null);
  const [error, setError] = useState('');
  // The existing-chats question, asked when 18+ starts allowing Afterglow
  // (the same transition PorchLifeSettings watches for its own rows).
  const [offer, setOffer] = useState<OfferFeature | null>(null);

  useEffect(() => {
    let alive = true;
    const read = () => {
      api
        .get<{ realism?: { adultThemesEnabled?: unknown; realismAllowed?: unknown; nsfwCooldownDefault?: unknown } }>('/api/settings')
        .then((r) => {
          if (!alive) return;
          setSt({
            adultThemesEnabled: r.realism?.adultThemesEnabled === true,
            realismAllowed: r.realism?.realismAllowed !== false,
            nsfwCooldownDefault: r.realism?.nsfwCooldownDefault === true,
          });
        })
        .catch((e: unknown) => console.warn('Could not read the 18+ themes setting', e));
    };
    read();
    // Live: another surface flips the switch or the engine; stay in step.
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
    };
  }, []);

  if (!st) return null;

  // Afterglow is allowed by Porch Life with 18+ on (desktop afterglowEnabled).
  const allowed = (s: typeof st) => s.adultThemesEnabled && s.nsfwCooldownDefault;

  const set = (value: boolean) => {
    const prev = st;
    const next = { ...st, adultThemesEnabled: value };
    setSt(next);
    setError('');
    api
      .post('/api/settings', { realism: { adultThemesEnabled: value } })
      .then(() => {
        if (next.realismAllowed && !allowed(prev) && allowed(next)) setOffer('afterglow');
      })
      .catch((e) => {
        setSt(prev);
        setError(e instanceof ApiError ? e.message : 'Could not save that change');
      });
  };

  return (
    <section className="card" data-testid="adult-themes-card">
      {offer && <ExistingChatsOffer key={offer} feature={offer} onClose={() => setOffer(null)} />}
      <label className="row-label">
        <span>18+ themes</span>
        <input
          type="checkbox"
          checked={st.adultThemesEnabled}
          onChange={(e) => set(e.target.checked)}
          aria-label="18+ themes"
        />
      </label>
      <p className="muted small">
        Shows the adult features — the After Dark group in Porch Life, and
        intimate preferences in the character editor. Off means they are
        simply not there. Turning this off never erases what you already set;
        it only hides the switches.
      </p>
      {error && <p className="error">{error}</p>}
    </section>
  );
}
