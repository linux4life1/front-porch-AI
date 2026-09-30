// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';

interface PackVerdict {
  emotion: string;
  samePerson: boolean;
  expressionMatches: boolean;
  note: string;
}

interface PackStatus {
  running: boolean;
  filenames: string[];
  verdicts: PackVerdict[];
}

/// Filenames and quality verdicts for a pack started on the desktop.
/// The payload has no image bytes, so this view never draws those pixels.
export function PackGrid() {
  const [pack, setPack] = useState<PackStatus | null>(null);

  useEffect(() => {
    let live = true;
    const load = () => {
      api
        .get<PackStatus>('/api/image/expression-pack')
        .then((body) => {
          if (live) setPack(body);
        })
        .catch((error: unknown) => {
          if (!live) return;
          if (error instanceof ApiError && error.status === 404) setPack(null);
        });
    };
    load();
    const timer = window.setInterval(load, 3000);
    return () => {
      live = false;
      window.clearInterval(timer);
    };
  }, []);

  if (!pack) return null;
  return (
    <div className="pack-status">
      <p>{pack.running ? 'Expression pack running' : 'Expression pack'}</p>
      <ul>
        {pack.filenames.map((name) => (
          <li key={name}>{name}</li>
        ))}
      </ul>
      <ul>
        {pack.verdicts.map((verdict) => (
          <li key={verdict.emotion}>
            {verdict.emotion}: {verdict.samePerson && verdict.expressionMatches ? 'pass' : 'check'}
            {verdict.note ? ` — ${verdict.note}` : ''}
          </li>
        ))}
      </ul>
      {pack.running && (
        <button
          type="button"
          className="secondary"
          onClick={() => {
            void api.post('/api/image/expression-pack/cancel', {});
          }}
        >
          Cancel pack
        </button>
      )}
    </div>
  );
}
