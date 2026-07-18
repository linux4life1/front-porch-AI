// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router-dom';
import { AuthProvider } from './auth/AuthContext';
import { App } from './App';
import { applyChatColors, loadChatColors } from './chatColors';
import './styles.css';

// Apply the user's saved chat colors before first paint so bubbles never flash
// the default palette.
applyChatColors(loadChatColors());

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <HashRouter>
      <AuthProvider>
        <App />
      </AuthProvider>
    </HashRouter>
  </StrictMode>,
);
