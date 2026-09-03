// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Stoop section shell: mounts the Stoop session provider, gates on
// sign-in and AUP acceptance (exact desktop parity), and hosts the nested
// routes behind a tab header with the inbox bell.
//
// The Share tab is desktop-browser only (per product decision): on phones it
// is neither shown nor routable — uploads are a full-browser flow, and the
// coming-soon surface would be dead weight on mobile.

import { Navigate, NavLink, Route, Routes } from 'react-router-dom';
import { useLayout } from '../../hooks/useBreakpoint';
import { StoopProvider, useStoop } from '../../stoop/StoopContext';
import { StoopAccountPage } from './StoopAccountPage';
import { StoopAuthView } from './StoopAuthView';
import { StoopBrowsePage } from './StoopBrowsePage';
import { StoopCardPage } from './StoopCardPage';
import { StoopCreatorPage } from './StoopCreatorPage';
import { StoopHomePage } from './StoopHomePage';
import { StoopInboxPage } from './StoopInboxPage';
import { StoopVerifiedBadge } from '../../components/stoop/StoopVerifiedBadge';
import { StoopPolicyGate } from './StoopPolicyGate';

export function StoopSection() {
  return (
    <StoopProvider>
      <StoopGate />
    </StoopProvider>
  );
}

function StoopGate() {
  const { loading, user, needsPolicy } = useStoop();

  if (loading) {
    return (
      <div className="centered">
        <div className="spinner" aria-label="Loading" />
      </div>
    );
  }
  if (!user) return <StoopAuthView />;
  if (needsPolicy) return <StoopPolicyGate />;
  return <StoopShell />;
}

function StoopShell() {
  const { wide } = useLayout();
  const { unread, user } = useStoop();
  // The personal tab wears the signed-in display name (desktop parity) —
  // ellipsized so a long name can't stretch the tab bar.
  const accountLabel = user?.displayName ? `@${user.displayName}` : 'Account';

  const tab = ({ isActive }: { isActive: boolean }) =>
    isActive ? 'stoop-tab active' : 'stoop-tab';

  return (
    <div className="page stoop-page">
      <header className="stoop-head">
        <h2>The Stoop</h2>
        <NavLink to="inbox" className="stoop-bell" title="Inbox" aria-label="Inbox">
          🔔{unread > 0 && <span className="stoop-bell-badge">{unread}</span>}
        </NavLink>
      </header>
      <nav className="stoop-tabs">
        <NavLink to="." end className={tab}>
          Home
        </NavLink>
        <NavLink to="browse" className={tab}>
          Browse
        </NavLink>
        {wide && (
          <NavLink to="share" className={tab}>
            Share
          </NavLink>
        )}
        <NavLink to="account" className={tab}>
          <span className="stoop-tab-name">
            <span className="stoop-tab-name-text">{accountLabel}</span>
            <StoopVerifiedBadge verification={user?.verification} />
          </span>
        </NavLink>
      </nav>
      <Routes>
        <Route index element={<StoopHomePage />} />
        <Route path="browse" element={<StoopBrowsePage />} />
        <Route path="card/:id" element={<StoopCardPage />} />
        <Route path="creator/:id" element={<StoopCreatorPage />} />
        <Route path="inbox" element={<StoopInboxPage />} />
        <Route path="account" element={<StoopAccountPage />} />
        <Route
          path="share"
          element={wide ? <ShareComingSoon /> : <Navigate to="/stoop" replace />}
        />
        <Route path="*" element={<Navigate to="/stoop" replace />} />
      </Routes>
    </div>
  );
}

function ShareComingSoon() {
  return (
    <section className="card stoop-coming-soon">
      <h3>Sharing — coming soon</h3>
      <p className="muted">
        Uploading characters, groups, and worlds (.fpworld places) to The Stoop
        from the web UI is on its way. Until then, you can share from the
        desktop app — everything you publish there shows up here too.
      </p>
    </section>
  );
}
