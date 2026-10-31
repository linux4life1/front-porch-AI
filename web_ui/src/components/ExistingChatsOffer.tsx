// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The existing-chats question (desktop parity: existing_chats_offer_dialog
// .dart): once Porch Life allows Realism, Afterglow or Needs, count the chats
// whose own switch is off and offer one switch, starting off, to turn it on
// in those too.
// Nothing is shown when there are none; Done answers with the switch.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

export type OfferFeature = 'afterglow' | 'needs' | 'realism';

const NAMES: Record<OfferFeature, string> = { afterglow: 'Afterglow', needs: 'Needs', realism: 'Realism' };

export function ExistingChatsOffer({ feature, onClose }: { feature: OfferFeature; onClose: () => void }) {
  const name = NAMES[feature];
  const realism = feature === 'realism';
  const [count, setCount] = useState<number | null>(null);
  const [turnOn, setTurnOn] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api
      .get<{ count: number }>(`/api/settings/existing-chats?feature=${feature}`)
      .then((r) => (r.count > 0 ? setCount(r.count) : onClose()))
      .catch((e) => {
        console.warn(`[porch-life] could not count chats with ${name} off`, e);
        onClose();
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (count == null) return null;
  const done = () => {
    if (!turnOn) return onClose();
    api
      .post('/api/settings/existing-chats', { feature })
      .then(onClose)
      .catch((e) => {
        console.warn(`[porch-life] could not turn ${name} on in existing chats`, e);
        setError('Could not turn it on in those chats. Try Done again.');
      });
  };
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal" role="dialog" aria-label={`${name} is on`} onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>{name} is on</span>
        </div>
        <p className="muted dialog-msg">
          {realism
            ? "New chats start with Realism when their character's card, or a group chat's group, turns it on, or when Start every new chat with Realism is on."
            : `New chats start with ${name} unless their character's card, or a group chat's group, says otherwise.`}
        </p>
        <label className="tool-toggle">
          <span>{count === 1 ? 'Turn it on in that chat too' : `Turn it on in those ${count} chats too`}</span>
          <input type="checkbox" checked={turnOn} onChange={(e) => setTurnOn(e.target.checked)} />
        </label>
        <p className="muted small">
          Only each chat&apos;s {name} switch changes. Cards stay as they are, and any chat can switch it off again.
          {realism && ' A chat that never ran it reads where things stand the next time you open it.'}
        </p>
        {error && (
          <p className="error" role="alert">
            ⚠️ {error}
          </p>
        )}
        <div className="modal-actions">
          <button className="primary" onClick={done}>
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
