// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { ApiError } from '../../../api/client';
import { cancelPack, fetchPack, type PackView } from './packApi';

/** A line above the desk while a pack is being made, with a way to stop it. */
export function PackBanner() {
  const [pack, setPack] = useState<PackView | null>(null);

  useEffect(() => {
    let live = true;
    const load = () =>
      fetchPack()
        .then((view) => {
          if (live) setPack(view);
        })
        .catch((e: unknown) => {
          if (live && e instanceof ApiError && e.status === 404) setPack(null);
        });
    void load();
    const timer = window.setInterval(load, 3000);
    return () => {
      live = false;
      window.clearInterval(timer);
    };
  }, []);

  if (!pack?.running) return null;
  return (
    <p data-region="pack-banner">
      Expression pack for {pack.characterName}: {pack.done} of {pack.total} made.{' '}
      <button
        type="button"
        className="secondary"
        onClick={() => {
          void cancelPack()
            .then(setPack)
            .catch(() => undefined);
        }}
      >
        Cancel pack
      </button>
    </p>
  );
}
