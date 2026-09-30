// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { sizeParts, snapSize } from './deskRules';

const PRESETS = ['512×512', '768×768', '1024×1024', '1536×1024', '1024×1536'];

/** The size that is sent, with the common shapes one tap away. */
export function DeskSize(props: { size: string; onSize: (size: string) => void }) {
  const [width, height] = sizeParts(props.size);
  const sentW = snapSize(Number(width) || 1024);
  const sentH = snapSize(Number(height) || 1024);
  const send = (w: string, h: string) =>
    props.onSize(`${snapSize(Number(w) || 1024)}x${snapSize(Number(h) || 1024)}`);
  return (
    <div>
      <div>Size</div>
      <div>
        {PRESETS.map((label) => (
          <button
            key={label}
            type="button"
            className="fp-pill"
            aria-pressed={label === `${width}×${height}`}
            onClick={() => {
              const [w, h] = label.split('×');
              send(w, h);
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <label>
        Width
        <input
          key={`w-${props.size}`}
          aria-label="Width"
          defaultValue={width || '1024'}
          onBlur={(e) => send(e.target.value, height || '1024')}
        />
      </label>
      <label>
        Height
        <input
          key={`h-${props.size}`}
          aria-label="Height"
          defaultValue={height || '1024'}
          onBlur={(e) => send(width || '1024', e.target.value)}
        />
      </label>
      <p>{`Sends ${sentW}×${sentH}. Each side snaps to a multiple of 64, from 256 to 2048.`}</p>
    </div>
  );
}
