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
  StoopComment,
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

/** Restore / first-paint of a saved browser session. Wipe the login only
 *  when it is already gone (tryRefresh cleared a dead refresh token). A
 *  502, timeout, or TypeError is a hiccup — keep the tokens so the next
 *  open can retry. A 401 that still has tokens means refresh hiccuped
 *  after call() already tried; do not undo that keep.
 *
 *  StoopContext used to `clearStoopSession()` on ANY `me()` failure, which
 *  undid the 401-only rule in tryRefresh and signed the phone out over
 *  one dropped packet (1.3 independent review leftover). */
export function shouldWipeStoopSessionAfterRestoreError(err: unknown): boolean {
  if (!(err instanceof StoopError) || err.status !== 401) return false;
  return !hasStoopSession();
}

/** RFC-4122 v4 UUID that also works in an INSECURE browsing context.
 *
 *  `crypto.randomUUID()` is secure-context-only, so it is `undefined` when
 *  the web UI is served over plain `http://` on a LAN IP — which is the
 *  normal remote-access setup (`http://192.168.x.x:8085`). Calling it there
 *  threw a TypeError before the login request was ever sent, surfacing as
 *  the generic "Something went wrong. Please try again." on every Stoop
 *  sign-in and sign-up (issue #160). localhost is a secure context, which is
 *  why it never reproduced on the dev machine.
 *
 *  `crypto.getRandomValues()` is NOT secure-context-gated, so it is the
 *  primary fallback; `Math.random` is the last-resort floor (this id is an
 *  anonymous install trace, not a secret or an auth factor). */
function newUuidV4(): string {
  const c: Crypto | undefined = globalThis.crypto;
  if (typeof c?.randomUUID === 'function') return c.randomUUID();
  const b = new Uint8Array(16);
  if (typeof c?.getRandomValues === 'function') {
    c.getRandomValues(b);
  } else {
    for (let i = 0; i < b.length; i++) b[i] = Math.floor(Math.random() * 256);
  }
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  const hex = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  return (
    `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-` +
    `${hex.slice(16, 20)}-${hex.slice(20)}`
  );
}

/** Anonymous per-browser install id (parity with the desktop's per-install id;
 *  the AUP's anti-ban-evasion trace). Never cleared on logout. */
function installId(): string {
  let id = localStorage.getItem(INSTALL_KEY);
  if (!id) {
    id = newUuidV4();
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
  // The "no refresh token" answer is decided BEFORE the latch is armed. An
  // early return from inside the IIFE never reaches its `finally`, and even if
  // it did, a body with no `await` runs to completion (clearing the latch)
  // BEFORE `??=` assigns the resolved promise — either way the latch would be
  // left holding a permanent `false`, silently killing refresh-and-retry for
  // the rest of the page's life (survives an in-place sign-out/sign-in).
  const refresh = localStorage.getItem(REFRESH_KEY);
  if (!refresh) return false;
  refreshing ??= (async () => {
    try {
      const r = await raw<{ accessToken: string; refreshToken: string }>(
        'POST',
        '/api/stoop/auth/refresh',
        { refreshToken: refresh },
        false,
      );
      saveTokens(r.accessToken, r.refreshToken);
      return true;
    } catch (e) {
      // Only a genuine 401 means the refresh token is dead. A network blip,
      // a 5xx or a proxy 502 is a hiccup — keep the tokens so a later call
      // can retry, the same rule the desktop AuthState refresh follows. The
      // phone/PWA twin used to clear on ANY failure, signing users out over
      // one dropped packet (1.3 sweep, independent review).
      if (e instanceof StoopError && e.status === 401) {
        clearStoopSession();
      }
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
  /** Edit the public creator profile (bio ≤ 300 chars, up to 4 http(s) links). */
  updateProfile: (bio: string, links: string[]) =>
    call<MeResult>('POST', '/api/stoop/me/profile', { bio, links }),
  /** Change the sign-in email. Confirmation goes to the NEW address; nothing
   *  changes until it's clicked (shows as user.pendingEmail meanwhile). */
  changeEmail: (newEmail: string, password: string, totp?: string) =>
    call<MeResult>('POST', '/api/stoop/me/email', {
      newEmail,
      ...(password ? { password } : {}),
      ...(totp ? { totp } : {}),
    }),
  cancelEmailChange: () => call<MeResult>('DELETE', '/api/stoop/me/email'),
  /** Ask for a password-reset email (always answers ok — never reveals whether
   *  the address has an account). The emailed link opens the hub's reset page. */
  forgot: (email: string) =>
    raw<{ ok: boolean }>('POST', '/api/stoop/auth/forgot', { email }, false),
  resendVerification: () =>
    call<{ ok: boolean }>('POST', '/api/stoop/me/resend-verification', {}),
  /** Upload a profile photo (raw image bytes; live instantly, post-moderated). */
  uploadAvatar: async (blob: Blob): Promise<MeResult> => {
    const doPost = async () => {
      const token = accessToken();
      const res = await fetch('/api/stoop/me/avatar', {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': blob.type || 'image/jpeg',
          ...(token ? { 'X-Stoop-Token': token } : {}),
        },
        body: blob,
      });
      const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
      if (!res.ok) {
        throw new StoopError(res.status, (data.error as string) || `http_${res.status}`);
      }
      return data as unknown as MeResult;
    };
    try {
      return await doPost();
    } catch (e) {
      if (e instanceof StoopError && e.status === 401 && (await tryRefresh())) {
        return doPost();
      }
      throw e;
    }
  },
  deleteAvatar: () => call<MeResult>('DELETE', '/api/stoop/me/avatar'),
  /** Delete one of YOUR OWN uploads (the backend enforces ownership). */
  deleteCharacter: (id: string) =>
    call<{ ok: boolean }>('DELETE', `/api/stoop/cards/${encodeURIComponent(id)}`),
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
    const type = query.type ?? 'all';
    const params = new URLSearchParams({
      sort: query.sort ?? 'newest',
      type,
      page: String(query.page ?? 0),
      take: String(query.take ?? 24),
    });
    // Desktop always opts in with types=solo,group,world when type=all
    // because the server keeps type=all as solo+group forever. Without this
    // Living Worlds never appear on web browse (audit P2.15).
    if (type === 'all') params.set('types', 'solo,group,world');
    if (query.q) params.set('q', query.q);
    if (query.pick) params.set('pick', 'true');
    if (query.following) params.set('following', 'true');
    return call<StoopBrowsePage>('GET', `/api/stoop/browse?${params}`);
  },
  cardDetail: (id: string, type?: 'SOLO' | 'GROUP' | 'WORLD') =>
    call<StoopCardDetail>(
      'GET',
      `/api/stoop/cards/${encodeURIComponent(id)}${type ? `?type=${encodeURIComponent(type)}` : ''}`,
    ),
  vote: (id: string, value: number) =>
    call<{ score: number; myVote: number }>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/vote`,
      { value },
    ),
  /** Download + import into the desktop library (runs server-side). */
  download: (id: string, type: 'SOLO' | 'GROUP' | 'WORLD') =>
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

  comments: (id: string) =>
    call<{ items?: StoopComment[]; comments?: StoopComment[] }>(
      'GET',
      `/api/stoop/cards/${encodeURIComponent(id)}/comments`,
    ),
  postComment: (id: string, body: string) =>
    call<StoopComment>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/comments`,
      { body },
    ),
  deleteComment: (id: string, commentId: string) =>
    call<StoopComment>(
      'DELETE',
      `/api/stoop/cards/${encodeURIComponent(id)}/comments/${encodeURIComponent(commentId)}`,
    ),
  reportComment: (
    id: string,
    commentId: string,
    category: string,
    reason: string,
  ) =>
    call<void>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/comments/${encodeURIComponent(commentId)}/report`,
      { category, reason },
    ),
  replyComment: (id: string, commentId: string, body: string) =>
    call<StoopComment>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/comments/${encodeURIComponent(commentId)}/reply`,
      { body },
    ),
  deleteReply: (id: string, commentId: string) =>
    call<StoopComment>(
      'DELETE',
      `/api/stoop/cards/${encodeURIComponent(id)}/comments/${encodeURIComponent(commentId)}/reply`,
    ),
  setCommentFlags: (
    id: string,
    flags: { commentsEnabled?: boolean; commentsLocked?: boolean },
  ) =>
    call<{ commentsEnabled?: boolean; commentsLocked?: boolean }>(
      'POST',
      `/api/stoop/cards/${encodeURIComponent(id)}/comment-flags`,
      flags,
    ),

  creator: (id: string) =>
    call<StoopCreator>(
      'GET',
      `/api/stoop/creators/${encodeURIComponent(id)}?types=solo,group,world`,
    ),
  setFollow: (id: string, follow: boolean) =>
    call<{ following: boolean; followers: number }>(
      'POST',
      `/api/stoop/creators/${encodeURIComponent(id)}/follow`,
      { follow },
    ),
  myFollowing: () =>
    call<{ items: StoopFollowedCreator[] }>('GET', '/api/stoop/me/following'),
  myCharacters: () =>
    call<{ items: StoopMine[] }>(
      'GET',
      '/api/stoop/me/characters?types=solo,group,world',
    ),
  myDownloads: () =>
    call<{ items: StoopCard[] }>(
      'GET',
      '/api/stoop/me/downloads?types=solo,group,world',
    ),

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
  if (!(e instanceof StoopError)) {
    // Diagnostics gap (issue #160): a non-API failure — a TypeError from a
    // secure-context-only browser API, a dropped fetch — used to collapse
    // into a bare "Something went wrong", leaving nothing in any log to act
    // on. Surface the real reason; it is the only breadcrumb a remote user
    // can copy into a bug report.
    const detail = e instanceof Error ? e.message : '';
    console.error('[Stoop] request failed', e);
    return detail
      ? `Something went wrong: ${detail}`
      : 'Something went wrong. Please try again.';
  }
  switch (e.code) {
    case 'invalid_credentials':
      return 'Wrong email or password.';
    case 'two_factor_required':
      return 'Enter your two-factor code.';
    case 'invalid_code':
      return 'That code didn’t work — try again.';
    case 'email_taken':
      return 'An account with that email already exists.';
    case 'disposable_email':
      return "Please use a permanent email address — throwaway addresses aren't accepted. You can browse The Stoop without an account.";
    case 'undeliverable_email':
      return "That domain can't receive email. Check the address and try again.";
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
    case 'display_name_taken':
      return 'That display name is already taken — pick another.';
    case 'email_not_verified':
      return 'Confirm your email first — check your inbox, or resend from Account.';
    case 'reason_required':
      return 'Please add a reason.';
    case 'avatar_locked':
      return 'A moderator has disabled profile pictures for this account.';
    case 'unsupported_image_type':
      return 'Use a PNG, JPEG, or WebP image.';
    case 'resend_too_soon':
      return 'Hang on a minute before requesting another email.';
    case 'same_email':
      return 'That’s already your sign-in email.';
    case 'wrong_password':
      return 'That password didn’t match.';
    default:
      return `Something went wrong (${e.code}).`;
  }
}
