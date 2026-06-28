// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import { Layout } from './components/Layout';
import { SetupPage } from './pages/SetupPage';
import { LoginPage } from './pages/LoginPage';
import { CharactersPage } from './pages/CharactersPage';
import { ChatPage } from './pages/ChatPage';
import { RemoteAccessPage } from './pages/RemoteAccessPage';
import { SettingsPage } from './pages/SettingsPage';
import { CharacterEditPage } from './pages/CharacterEditPage';
import { CreateCharacterPage } from './pages/CreateCharacterPage';
import { CreateAiCharacterPage } from './pages/CreateAiCharacterPage';
import { CreateGroupChatPage } from './pages/CreateGroupChatPage';
import { WorldsPage } from './pages/WorldsPage';
import { StoriesPage } from './pages/StoriesPage';
import { StorySetupPage } from './pages/StorySetupPage';
import { StoryDashboardPage } from './pages/StoryDashboardPage';
import { StoryStructurePage } from './pages/StoryStructurePage';
import { StoryWriterPage } from './pages/StoryWriterPage';
import { StoryReaderPage } from './pages/StoryReaderPage';
import { ModelsPage } from './pages/ModelsPage';
import { AccountPage } from './pages/AccountPage';

export function App() {
  const { loading, setupRequired, authenticated } = useAuth();

  if (loading) {
    return (
      <div className="centered">
        <div className="spinner" aria-label="Loading" />
      </div>
    );
  }
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
        <Route path="/stories" element={<StoriesPage />} />
        <Route path="/stories/:id" element={<StoryDashboardPage />} />
        <Route path="/stories/:id/setup" element={<StorySetupPage />} />
        <Route path="/stories/:id/structure" element={<StoryStructurePage />} />
        <Route path="/stories/:id/write/:act/:scene" element={<StoryWriterPage />} />
        <Route path="/stories/:id/read" element={<StoryReaderPage />} />
        <Route path="/models" element={<ModelsPage />} />
        <Route path="/edit/:id" element={<CharacterEditPage />} />
        <Route path="/account" element={<AccountPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Layout>
  );
}
