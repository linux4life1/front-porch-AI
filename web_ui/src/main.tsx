// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { createHashRouter, RouterProvider } from 'react-router-dom';
import { AuthProvider } from './auth/AuthContext';
import { App } from './App';
import { AppErrorBoundary } from './components/AppErrorBoundary';
import { applyReadingSize, loadReadingSize } from './readingSize';
import { applyCachedTheme } from './theme/appTheme';
import { applyCachedAppearance } from './theme/appearance';
import './styles.css';

// Apply the last theme and appearance the desktop sent, and the user's
// reading size, before first paint, so nothing flashes the default palette,
// face or corners.
applyCachedTheme();
applyCachedAppearance();
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
