// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Session state for The Stoop section. Mounted by StoopSection, so the live
// messaging socket (and its unread badge) exists exactly while the user is in
// The Stoop — the parity twin of the desktop's inbox bell ownership.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { accessToken, clearStoopSession, hasStoopSession, stoop } from './stoopApi';
import type { StoopMessage, StoopUser } from './stoopTypes';

export type StoopSocketEvent =
  | { type: 'message'; message: StoopMessage }
  | { type: 'typing'; fromMod: boolean; isTyping: boolean };

interface StoopState {
  loading: boolean;
  user: StoopUser | null;
  policyVersion: string;
  needsPolicy: boolean;
  unread: number;
  applyAuthResult: (user: StoopUser, policyVersion: string) => void;
  updateUser: (user: StoopUser) => void;
  signOut: () => Promise<void>;
  /** Inbox page presence: while open, incoming messages don't count as unread. */
  setInboxOpen: (open: boolean) => void;
  subscribe: (cb: (e: StoopSocketEvent) => void) => () => void;
  sendTyping: (isTyping: boolean) => void;
}

const Ctx = createContext<StoopState | null>(null);

export function useStoop(): StoopState {
  const v = useContext(Ctx);
  if (!v) throw new Error('useStoop outside StoopProvider');
  return v;
}

export function StoopProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(hasStoopSession());
  const [user, setUser] = useState<StoopUser | null>(null);
  const [policyVersion, setPolicyVersion] = useState('');
  const [unread, setUnread] = useState(0);

  const wsRef = useRef<WebSocket | null>(null);
  const wsBackoff = useRef(3000);
  const inboxOpen = useRef(false);
  const subscribers = useRef(new Set<(e: StoopSocketEvent) => void>());
  const userRef = useRef<StoopUser | null>(null);
  userRef.current = user;

  // Restore the saved browser session on entry (access token first, refresh
  // fallback handled inside the api layer).
  useEffect(() => {
    if (!hasStoopSession()) return;
    let cancelled = false;
    stoop
      .me()
      .then((r) => {
        if (cancelled) return;
        setUser(r.user);
        setPolicyVersion(r.policyVersion);
      })
      .catch(() => {
        if (!cancelled) clearStoopSession();
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Live messaging socket + unread badge, held while signed in. First frame
  // authenticates the relay; reconnects every few seconds on drop with the
  // freshest token (matching the desktop StoopMessageSocket).
  useEffect(() => {
    if (!user) return;
    let closed = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    stoop.unreadCount().then(setUnread).catch(() => {});

    const connect = () => {
      if (closed || !userRef.current) return;
      const proto = location.protocol === 'https:' ? 'wss' : 'ws';
      const ws = new WebSocket(`${proto}://${location.host}/api/stoop/ws`);
      wsRef.current = ws;
      ws.onopen = () => {
        wsBackoff.current = 3000;
        ws.send(JSON.stringify({ token: accessToken() ?? '' }));
      };
      ws.onmessage = (msg) => {
        try {
          const e = JSON.parse(msg.data as string) as StoopSocketEvent;
          if (e.type === 'message' && !inboxOpen.current) setUnread((u) => u + 1);
          subscribers.current.forEach((cb) => cb(e));
        } catch {
          /* ignore malformed frame */
        }
      };
      ws.onclose = () => {
        wsRef.current = null;
        if (!closed) timer = setTimeout(connect, wsBackoff.current);
      };
      ws.onerror = () => ws.close();
    };
    connect();

    return () => {
      closed = true;
      if (timer) clearTimeout(timer);
      wsRef.current?.close();
      wsRef.current = null;
    };
  }, [user]);

  const applyAuthResult = useCallback((u: StoopUser, policy: string) => {
    setUser(u);
    setPolicyVersion(policy);
    setLoading(false);
  }, []);

  const updateUser = useCallback((u: StoopUser) => setUser(u), []);

  const signOut = useCallback(async () => {
    await stoop.logout();
    setUser(null);
    setUnread(0);
  }, []);

  const setInboxOpen = useCallback((open: boolean) => {
    inboxOpen.current = open;
    if (open) {
      setUnread(0);
      stoop.markMessagesRead().catch(() => {});
    }
  }, []);

  const subscribe = useCallback((cb: (e: StoopSocketEvent) => void) => {
    subscribers.current.add(cb);
    return () => {
      subscribers.current.delete(cb);
    };
  }, []);

  const sendTyping = useCallback((isTyping: boolean) => {
    const ws = wsRef.current;
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'typing', isTyping }));
    }
  }, []);

  const needsPolicy =
    !!user && !!policyVersion && user.acceptedPolicyVersion !== policyVersion;

  return (
    <Ctx.Provider
      value={{
        loading,
        user,
        policyVersion,
        needsPolicy,
        unread,
        applyAuthResult,
        updateUser,
        signOut,
        setInboxOpen,
        subscribe,
        sendTyping,
      }}
    >
      {children}
    </Ctx.Provider>
  );
}
