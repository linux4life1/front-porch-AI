// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One reusable popover menu for every library surface (character / folder /
// group cards + the Import button). The page owns a single open-menu state and
// renders this once, so there is exactly one menu implementation.

import { useEffect, useState } from 'react';

export interface CardMenuItem {
  label: string;
  icon?: string;
  danger?: boolean;
  onClick: () => void;
}

export interface MenuState {
  x: number;
  y: number;
  items: CardMenuItem[];
}

const WIDTH = 210;
const ITEM_H = 38;

export function CardMenu({ menu, onClose }: { menu: MenuState; onClose: () => void }) {
  // Clamp into the viewport so a kebab near the right/bottom edge stays visible.
  const [pos] = useState(() => {
    const maxLeft = window.innerWidth - WIDTH - 8;
    const maxTop = window.innerHeight - menu.items.length * ITEM_H - 8;
    return {
      left: Math.max(8, Math.min(menu.x, maxLeft)),
      top: Math.max(8, Math.min(menu.y, maxTop)),
    };
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="card-menu-backdrop"
      onClick={onClose}
      onContextMenu={(e) => {
        e.preventDefault();
        onClose();
      }}
    >
      <div
        className="card-menu"
        style={{ left: pos.left, top: pos.top, width: WIDTH }}
        onClick={(e) => e.stopPropagation()}
        role="menu"
      >
        {menu.items.map((it, i) => (
          <button
            key={i}
            role="menuitem"
            className={`card-menu-item${it.danger ? ' danger' : ''}`}
            onClick={() => {
              onClose();
              it.onClick();
            }}
          >
            {it.icon && (
              <span className="cmi-icon" aria-hidden>
                {it.icon}
              </span>
            )}
            <span>{it.label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
