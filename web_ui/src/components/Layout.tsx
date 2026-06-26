// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState, type ReactNode } from 'react';
import { Link, NavLink, useNavigate } from 'react-router-dom';
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
  const { wide, bp } = useLayout();
  const navigate = useNavigate();
  const [drawerOpen, setDrawerOpen] = useState(false);

  // Single source of truth for form factor: write it to the document root so CSS
  // can scope desktop-first base rules vs `[data-layout="phone"]` overrides that
  // physically cannot leak across form factors. (See styles.css header rule.)
  useEffect(() => {
    document.documentElement.dataset.layout = bp;
  }, [bp]);

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

  const links = (onPick?: () => void) => (
    <nav className="side-links">
      {NAV.map((n) => (
        <NavLink key={n.to} to={n.to} end={n.end} className={navItem} onClick={onPick}>
          <span className="nav-icon" aria-hidden>{n.icon}</span>
          <span className="nav-label">{n.label}</span>
        </NavLink>
      ))}
    </nav>
  );

  const footer = (
    <div className="side-footer">
      <a
        className="side-social-link"
        href="https://discord.gg/e4tET6rpdv"
        target="_blank"
        rel="noopener noreferrer"
        title="Discord"
      >
        <span aria-hidden>💬</span>
      </a>
      <button className="side-logout link-btn" onClick={logout}>Log out</button>
    </div>
  );

  // ── Desktop / tablet: persistent Dart-style side rail ──
  if (wide) {
    return (
      <div className="app-shell cols">
        <aside className="side-nav">
          <Link to="/" className="side-brand">Front Porch AI</Link>
          {links()}
          {footer}
        </aside>
        <main className="app-main">{children}</main>
      </div>
    );
  }

  // ── Phone: top bar + slide-in nav drawer (no crammed bottom tab bar) ──
  return (
    <div className="app-shell">
      <header className="app-header">
        <button className="hamburger icon-btn" aria-label="Open menu" onClick={() => setDrawerOpen(true)}>
          ☰
        </button>
        <Link to="/" className="app-title">Front Porch AI</Link>
      </header>
      <main className="app-content">{children}</main>
      {drawerOpen && (
        <div className="drawer-backdrop nav-backdrop" onClick={() => setDrawerOpen(false)}>
          <aside className="side-nav nav-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <Link to="/" className="side-brand" onClick={() => setDrawerOpen(false)}>Front Porch AI</Link>
              <button className="icon-btn" aria-label="Close menu" onClick={() => setDrawerOpen(false)}>
                ✕
              </button>
            </div>
            {links(() => setDrawerOpen(false))}
            {footer}
          </aside>
        </div>
      )}
    </div>
  );
}
