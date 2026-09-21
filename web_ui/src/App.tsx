// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import { Layout } from './components/Layout';
import { SetupPage } from './pages/SetupPage';
import { LoginPage } from './pages/LoginPage';
import { UnreachablePage } from './pages/UnreachablePage';
import { CharactersPage } from './pages/CharactersPage';
import { ChatPage } from './pages/ChatPage';
import { RemoteAccessPage } from './pages/RemoteAccessPage';
import { SettingsPage } from './pages/SettingsPage';
import { CharacterEditPage } from './pages/CharacterEditPage';
import { CreateCharacterPage } from './pages/CreateCharacterPage';
import { CreateAiCharacterPage } from './pages/CreateAiCharacterPage';
import { CreateGroupChatPage } from './pages/CreateGroupChatPage';
import { WorldsPage } from './pages/WorldsPage';
import { WorldFromWikiPage } from './pages/WorldFromWikiPage';
import { StoriesPage } from './pages/StoriesPage';
import { StorySetupPage } from './pages/StorySetupPage';
import { StoryDashboardPage } from './pages/StoryDashboardPage';
import { StoryStructurePage } from './pages/StoryStructurePage';
import { StoryWriterPage } from './pages/StoryWriterPage';
import { StoryReaderPage } from './pages/StoryReaderPage';
import { ModelsPage } from './pages/ModelsPage';
import { AccountPage } from './pages/AccountPage';
import { StoopSection } from './pages/stoop/StoopSection';
import { restoreSpellCheckLang, syncSpellCheckLang } from './spellCheckLang';

restoreSpellCheckLang();

export function App() {
  const { loading, setupRequired, authenticated, unreachable } = useAuth();

  // Pull the desktop's spell check language once we can actually reach it.
  // The cached value from restoreSpellCheckLang() is already applied, so this
  // only corrects a change made on the desktop since the last visit.
  useEffect(() => {
    if (authenticated) void syncSpellCheckLang();
  }, [authenticated]);

  if (loading) {
    return (
      <div className="centered">
        <div className="spinner" aria-label="Loading" />
      </div>
    );
  }
  // Before the login branch: a dead server used to render as a working-looking
  // login form (the service worker serves the shell from cache) — say so
  // honestly instead.
  if (unreachable) return <UnreachablePage />;
  if (setupRequired) return <SetupPage />;
  if (!authenticated) return <LoginPage />;

  return (
    <Layout>
      <Routes>
        <Route path="/" element={<CharactersPage />} />
        <Route path="/chat" element={<ChatPage />} />
        <Route path="/remote" element={<RemoteAccessPage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/create" element={<CreateCharacterPage />} />
        <Route path="/create-ai" element={<CreateAiCharacterPage />} />
        <Route path="/create-group" element={<CreateGroupChatPage />} />
        <Route path="/worlds" element={<WorldsPage />} />
        <Route path="/worlds/from-wiki" element={<WorldFromWikiPage />} />
        <Route path="/stories" element={<StoriesPage />} />
        <Route path="/stories/:id" element={<StoryDashboardPage />} />
        <Route path="/stories/:id/setup" element={<StorySetupPage />} />
        <Route path="/stories/:id/structure" element={<StoryStructurePage />} />
        <Route path="/stories/:id/write/:act/:scene" element={<StoryWriterPage />} />
        <Route path="/stories/:id/read" element={<StoryReaderPage />} />
        <Route path="/models" element={<ModelsPage />} />
        <Route path="/stoop/*" element={<StoopSection />} />
        <Route path="/edit/:id" element={<CharacterEditPage />} />
        <Route path="/account" element={<AccountPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Layout>
  );
}
