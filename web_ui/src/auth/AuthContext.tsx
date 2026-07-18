// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { api } from '../api/client';

interface AuthState {
  loading: boolean;
  setupRequired: boolean;
  authenticated: boolean;
}

interface AuthContextValue extends AuthState {
  refresh: () => Promise<void>;
  setAuthenticated: (v: boolean) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({
    loading: true,
    setupRequired: false,
    authenticated: false,
  });

  const refresh = useCallback(async () => {
    try {
      const s = await api.get<{ setupRequired: boolean; authenticated: boolean }>(
        '/api/auth/state',
      );
      setState({
        loading: false,
        setupRequired: s.setupRequired,
        authenticated: s.authenticated,
      });
    } catch {
      setState({ loading: false, setupRequired: false, authenticated: false });
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const setAuthenticated = useCallback((v: boolean) => {
    setState((s) => ({ ...s, authenticated: v }));
  }, []);

  return (
    <AuthContext.Provider value={{ ...state, refresh, setAuthenticated }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
