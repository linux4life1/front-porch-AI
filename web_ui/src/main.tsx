// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { createHashRouter, RouterProvider } from 'react-router-dom';
import { AuthProvider } from './auth/AuthContext';
import { App } from './App';
import { AppErrorBoundary } from './components/AppErrorBoundary';
import { applyChatColors, loadChatColors } from './chatColors';
import { applyReadingSize, loadReadingSize } from './readingSize';
import './styles.css';

// Apply the user's saved chat colors before first paint so bubbles never flash
// the default palette.
applyChatColors(loadChatColors());
applyReadingSize(loadReadingSize());

// A data router (rather than <HashRouter>) so pages with unsaved edits can
// block leaving them (useUnsavedChanges). App keeps its own <Routes>.
const router = createHashRouter([
  {
    path: '*',
    element: (
      <AppErrorBoundary>
        <AuthProvider>
          <App />
        </AuthProvider>
      </AppErrorBoundary>
    ),
  },
]);

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>,
);
