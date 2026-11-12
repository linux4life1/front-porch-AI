// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState, type ReactNode } from 'react';
import { Link, NavLink, useLocation, useNavigate } from 'react-router-dom';
import { api } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { useLayout } from '../hooks/useBreakpoint';

// The desktop sidebar's items, labels and order (lib/ui/widgets/sidebar.dart),
// then Account (the web sign-in, the one platform-only item) and Log out.
const NAV: { to?: string; href?: string; label: string; icon: string; end?: boolean }[] = [
  { to: '/', label: 'Home', icon: '🏠', end: true },
  { to: '/images', label: 'Image Studio', icon: '🖼️' },
  { to: '/stoop', label: 'The Stoop', icon: '🏘️' },
  { to: '/create-ai', label: 'AI Character Creator', icon: '✨', end: true },
  { to: '/create', label: 'Create Character', icon: '➕', end: true },
  { to: '/create-group', label: 'Create Group Chat', icon: '👥', end: true },
  { to: '/models', label: 'Manage Models', icon: '🧠' },
  { to: '/settings', label: 'Settings', icon: '🎛️' },
  { to: '/persona', label: 'User Persona', icon: '👤' },
  { to: '/worlds', label: 'Worlds', icon: '🗺️' },
  { to: '/backups', label: 'Backups & Restore', icon: '💾' },
  { href: 'https://discord.gg/e4tET6rpdv', label: 'Join the Discord', icon: '💬' },
  { href: 'https://ko-fi.com/sosukeaizen37411', label: 'Buy Me a Coffee ☕', icon: '☕' },
  { to: '/account', label: 'Account', icon: '⚙️' },
];

export function Layout({ children }: { children: ReactNode }) {
  const { setAuthenticated } = useAuth();
  const { wide, bp } = useLayout();
  const navigate = useNavigate();
  const location = useLocation();
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
      {NAV.map((n) =>
        n.to ? (
          <NavLink key={n.to} to={n.to} end={n.end} className={navItem} onClick={onPick}>
            <span className="nav-icon" aria-hidden>{n.icon}</span>
            <span className="nav-label">{n.label}</span>
          </NavLink>
        ) : (
          <a key={n.href} className="nav-item" href={n.href} target="_blank" rel="noopener noreferrer" onClick={onPick}>
            <span className="nav-icon" aria-hidden>{n.icon}</span>
            <span className="nav-label">{n.label}</span>
          </a>
        ),
      )}
    </nav>
  );

  const footer = (
    <div className="side-footer">
      <button className="side-logout link-btn" onClick={logout}>Log out</button>
    </div>
  );

  // ── Chat route: the desktop chat window, at every width ──
  // The chat is the Flutter desktop's window: no side rail, no phone banner,
  // full width, and the header's back arrow owns leaving it (one-chat-ux.md
  // PR 1). Phone and tablet live in the same shell; only the sidebar's
  // presentation changes below 1024 (PR 1b).
  if (location.pathname.startsWith('/chat')) {
    return (
      <div className="app-shell cols">
        <main className="app-main">{children}</main>
      </div>
    );
  }

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
