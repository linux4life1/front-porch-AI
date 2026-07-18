// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Client for The Stoop via the Dart server's /api/stoop/* relay.
//
// Unlike the app session (HttpOnly cookie), the Stoop session deliberately
// lives in THIS browser's localStorage — signing in to The Stoop on your phone
// persists on the phone, independent of the desktop app's own Stoop login.
// Every call attaches the access token as an X-Stoop-Token header; on a 401 we
// refresh once (single-flight) and retry, mirroring the desktop AuthState.

import type {
  StoopAup,
  StoopBrowsePage,
  StoopBrowseQuery,
  StoopCard,
  StoopCardDetail,
  StoopCreator,
  StoopFollowedCreator,
  StoopMessage,
  StoopMine,
  StoopUser,
} from './stoopTypes';

const ACCESS_KEY = 'stoop_access_token';
const REFRESH_KEY = 'stoop_refresh_token';
const INSTALL_KEY = 'stoop_install_id';

export class StoopError extends Error {
  status: number;
  /** Machine-readable upstream code (invalid_credentials, email_taken, …). */
  code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export type MeResult = { user: StoopUser; policyVersion: string };

// ---- token store (the "login info saved in the browser") ----

export function hasStoopSession(): boolean {
  return !!localStorage.getItem(ACCESS_KEY) || !!localStorage.getItem(REFRESH_KEY);
}

export function accessToken(): string | null {
  return localStorage.getItem(ACCESS_KEY);
}

function saveTokens(access: string, refresh: string): void {
  localStorage.setItem(ACCESS_KEY, access);
  localStorage.setItem(REFRESH_KEY, refresh);
}

export function clearStoopSession(): void {
  localStorage.removeItem(ACCESS_KEY);
  localStorage.removeItem(REFRESH_KEY);
}

/** Anonymous per-browser install id (parity with the desktop's per-install id;
 *  the AUP's anti-ban-evasion trace). Never cleared on logout. */
function installId(): string {
  let id = localStorage.getItem(INSTALL_KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(INSTALL_KEY, id);
  }
  return id;
}

// ---- transport ----

async function raw<T>(
  method: string,
  path: string,
  body?: unknown,
  auth = true,
): Promise<T> {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const token = auth ? accessToken() : null;
  if (token) headers['X-Stoop-Token'] = token;
  const res = await fetch(path, {
    method,
    credentials: 'include',
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data: Record<string, unknown> = {};
  try {
    const parsed: unknown = text ? JSON.parse(text) : {};
    if (typeof parsed === 'object' && parsed !== null) {
      data = parsed as Record<string, unknown>;
    }
  } catch {
    /* non-JSON body — fall through to the status check */
  }
  if (!res.ok) {
    throw new StoopError(res.status, (data.error as string) || `http_${res.status}`);
  }
  return data as T;
}

// Single-flight refresh so a burst of parallel 401s spends one refresh token.
let refreshing: Promise<boolean> | null = null;

async function tryRefresh(): Promise<boolean> {
  refreshing ??= (async () => {
    const refresh = localStorage.getItem(REFRESH_KEY);
    if (!refresh) return false;
    try {
      const r = await raw<{ accessToken: string; refreshToken: string }>(
        'POST',
        '/api/stoop/auth/refresh',
        { refreshToken: refresh },
        false,
      );
      saveTokens(r.accessToken, r.refreshToken);
      return true;
    } catch {
      clearStoopSession();
      return false;
    } finally {
      refreshing = null;
    }
  })();
  return refreshing;
}

/** Authenticated call with one transparent refresh-and-retry on 401. */
async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  try {
    return await raw<T>(method, path, body);
  } catch (e) {
    if (e instanceof StoopError && e.status === 401 && (await tryRefresh())) {
      return raw<T>(method, path, body);
    }
    throw e;
  }
}

function applyAuth(r: {
  user: StoopUser;
  accessToken: string;
  refreshToken: string;
  policyVersion?: string;
}): MeResult {
  saveTokens(r.accessToken, r.refreshToken);
  return { user: r.user, policyVersion: r.policyVersion ?? '' };
}

// ---- API surface (mirrors lib/services/backporch/backporch_api.dart) ----

export const stoop = {
  aup: () => raw<StoopAup>('GET', '/api/stoop/aup', undefined, false),

  login: async (email: string, password: string, totp?: string): Promise<MeResult> =>
    applyAuth(
      await raw<Parameters<typeof applyAuth>[0]>('POST', '/api/stoop/auth/login', {
        email,
        password,
        installId: installId(),
        ...(totp ? { totp } : {}),
      }, false),
    ),

  signup: async (
    email: string,
    password: string,
    displayName: string,
    dateOfBirth: string,
  ): Promise<MeResult> =>
    applyAuth(
      await raw<Parameters<typeof applyAuth>[0]>('POST', '/api/stoop/auth/signup', {
        email,
        password,
        displayName,
        dateOfBirth,
        installId: installId(),
      }, false),
    ),

  /** Best-effort server-side revoke; the local session clears regardless. */
  logout: async (): Promise<void> => {
    const refresh = localStorage.getItem(REFRESH_KEY);
    try {
      await raw('POST', '/api/stoop/auth/logout', refresh ? { refreshToken: refresh } : {}, false);
    } catch {
      /* unreachable server must not block signing out locally */
    }
    clearStoopSession();
  },

  me: () => call<MeResult>('GET', '/api/stoop/me'),
  acceptPolicy: (version: string) =>
    call<MeResult>('POST', '/api/stoop/me/accept-policy', { version }),
  setDisplayName: (displayName: string) =>
    call<MeResult>('POST', '/api/stoop/me/display-name', { displayName }),
  setNsfwEnabled: (enabled: boolean) =>
    call<MeResult>('POST', '/api/stoop/me/nsfw', { enabled }),
  deleteAccount: async (): Promise<void> => {
    await call('DELETE', '/api/stoop/me');
    clearStoopSession();
  },

  twoFactorSetup: () =>
    call<{ secret: string; otpauthUrl: string; qrDataUrl: string }>(
      'POST',
      '/api/stoop/2fa/setup',
    ),
  twoFactorEnable: (totp: string) => call<void>('POST', '/api/stoop/2fa/enable', { totp }),
  twoFactorDisable: (totp: string) => call<void>('POST', '/api/stoop/2fa/disable', { totp }),

  browse: (query: StoopBrowseQuery) => {
    const params = new URLSearchParams({
      sort: query.sort ?? 'newest',
      type: query.type ?? 'all',
      page: String(query.page ?? 0),
      take: String(query.take ?? 24),
    });
    if (query.q) params.set('q', query.q);
    if (query.pick) params.set('pick', 'true');
    if (query.following) params.set('following', 'true');
    return call<StoopBrowsePage>('GET', `/api/stoop/browse?${params}`);
  },
  cardDetail: (id: string) =>
    call<StoopCardDetail>('GET', `/api/stoop/cards/${encodeURIComponent(id)}`),
  vote: (id: string, value: number) =>
    call<{ score: number; myVote: number }>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/vote`,
      { value },
    ),
  /** Download + import into the desktop library (runs server-side). */
  download: (id: string, type: 'SOLO' | 'GROUP') =>
    call<{ ok: boolean; name: string; type: string }>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/download`,
      { type },
    ),
  report: (id: string, category: string, reason: string) =>
    call<void>('POST', `/api/stoop/cards/${encodeURIComponent(id)}/report`, {
      category,
      reason,
    }),

  creator: (id: string) =>
    call<StoopCreator>('GET', `/api/stoop/creators/${encodeURIComponent(id)}`),
  setFollow: (id: string, follow: boolean) =>
    call<{ following: boolean; followers: number }>(
      'POST',
      `/api/stoop/creators/${encodeURIComponent(id)}/follow`,
      { follow },
    ),
  myFollowing: () =>
    call<{ items: StoopFollowedCreator[] }>('GET', '/api/stoop/me/following'),
  myCharacters: () => call<{ items: StoopMine[] }>('GET', '/api/stoop/me/characters'),
  myDownloads: () => call<{ items: StoopCard[] }>('GET', '/api/stoop/me/downloads'),

  messages: () => call<{ items: StoopMessage[] }>('GET', '/api/stoop/me/messages'),
  unreadCount: async (): Promise<number> =>
    (await call<{ count: number }>('GET', '/api/stoop/me/messages/unread')).count ?? 0,
  markMessagesRead: () => call<void>('POST', '/api/stoop/me/messages/read'),
  sendMessage: async (body: string): Promise<StoopMessage> =>
    (await call<{ message: StoopMessage }>('POST', '/api/stoop/me/messages', { body }))
      .message,

  /** Authenticated avatar URL — the server attaches the remembered token. */
  assetUrl: (assetId: string) => `/api/stoop/assets/${encodeURIComponent(assetId)}`,
};

/** Human messages for the upstream machine codes the UI commonly hits. */
export function stoopErrorText(e: unknown): string {
  if (!(e instanceof StoopError)) return 'Something went wrong. Please try again.';
  switch (e.code) {
    case 'invalid_credentials':
      return 'Wrong email or password.';
    case 'two_factor_required':
      return 'Enter your two-factor code.';
    case 'invalid_code':
      return 'That code didn’t work — try again.';
    case 'email_taken':
      return 'An account with that email already exists.';
    case 'underage':
      return 'You must be 18 or older to use The Stoop.';
    case 'account_banned':
      return 'This account has been banned.';
    case 'stoop_unreachable':
      return 'The Stoop is unreachable right now. Check the desktop app’s connection.';
    case 'stoop_not_signed_in':
      return 'Your Stoop session expired — please sign in again.';
    case 'library_unavailable':
      return 'The desktop library isn’t ready yet — try again in a moment.';
    default:
      return `Something went wrong (${e.code}).`;
  }
}
