// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { ReactNode } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { api } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { useLayout } from '../hooks/useBreakpoint';

const NAV = [
  { to: '/', label: 'Characters', icon: '👤', end: true },
  { to: '/chat', label: 'Chat', icon: '💬', end: false },
  { to: '/worlds', label: 'Worlds', icon: '🗺️', end: false },
  { to: '/stories', label: 'Stories', icon: '📖', end: false },
  { to: '/models', label: 'Models', icon: '🧠', end: false },
  { to: '/remote', label: 'Remote', icon: '🌐', end: false },
  { to: '/settings', label: 'Settings', icon: '🎛️', end: false },
  { to: '/account', label: 'Account', icon: '⚙️', end: false },
];

export function Layout({ children }: { children: ReactNode }) {
  const { setAuthenticated } = useAuth();
  const { wide } = useLayout();
  const navigate = useNavigate();

  const logout = async () => {
    try {
      await api.post('/api/auth/logout');
    } catch {
      /* ignore */
    }
    setAuthenticated(false);
    navigate('/');
  };

  const navItem = ({ isActive }: { isActive: boolean }) =>
    isActive ? 'nav-item active' : 'nav-item';

  // ── Desktop / tablet: persistent labeled side rail (app-like) ──
  if (wide) {
    return (
      <div className="app-shell cols">
        <aside className="side-nav">
          <div className="side-brand">Front Porch AI</div>
          <nav className="side-links">
            {NAV.map((n) => (
              <NavLink key={n.to} to={n.to} end={n.end} className={navItem}>
                <span className="nav-icon" aria-hidden>{n.icon}</span>
                <span className="nav-label">{n.label}</span>
              </NavLink>
            ))}
          </nav>
          <button className="side-logout link-btn" onClick={logout}>Log out</button>
        </aside>
        <main className="app-main">{children}</main>
      </div>
    );
  }

  // ── Phone: top bar + bottom tab nav ──
  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="app-title">Front Porch AI</span>
        <button className="link-btn" onClick={logout}>Log out</button>
      </header>
      <main className="app-content">{children}</main>
      <nav className="app-nav">
        {NAV.map((n) => (
          <NavLink key={n.to} to={n.to} end={n.end} className={navItem}>
            <span className="nav-icon" aria-hidden>{n.icon}</span>
            <span>{n.label}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
