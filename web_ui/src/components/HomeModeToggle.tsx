// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Home's mode switch, as on the desktop (home_mode_toggle.dart): Chats and
// Porch Stories, leading the Home toolbar and the Stories shelf. Labels drop
// to icons on a narrow screen and stay as tooltips.

import { useNavigate } from 'react-router-dom';

export function HomeModeToggle({ mode }: { mode: 'chats' | 'stories' }) {
  const navigate = useNavigate();
  const item = (key: 'chats' | 'stories', label: string, icon: string, to: string) => (
    <button
      key={key}
      type="button"
      className={mode === key ? 'mode-btn active' : 'mode-btn'}
      aria-pressed={mode === key}
      title={label}
      onClick={() => mode !== key && navigate(to)}
    >
      <span aria-hidden>{icon}</span>
      <span className="mode-label">{label}</span>
    </button>
  );
  return (
    <div className="home-mode-toggle" role="group" aria-label="Home view" data-testid="home-mode-toggle">
      {item('chats', 'Chats', '💬', '/')}
      {item('stories', 'Porch Stories', '📖', '/stories')}
    </div>
  );
}
