/* The Stoop hub — API client.
   Talks straight to the backporch API with Bearer tokens (the same contract the
   desktop app uses; cookies don't ride cross-origin, so tokens live in
   localStorage). Handles the refresh dance, friendly error mapping, and the
   live WebSocket (messages, typing, real-time card stats). */
(function () {
  'use strict';
  window.Stoop = window.Stoop || {};

  var LS = {
    access: 'stoop.access',
    refresh: 'stoop.refresh',
    installId: 'stoop.installId',
    apiBase: 'stoop.apiBase', // manual override for debugging
    guestAdult: 'stoop.guestAdult', // guest self-certified 18+ (for NSFW)
  };

  function defaultBase() {
    var o = localStorage.getItem(LS.apiBase);
    if (o) return o;
    if (location.hostname === 'localhost' || location.hostname === '127.0.0.1') {
      return 'http://localhost:8080';
    }
    return 'https://api.frontporchai.app';
  }

  var state = {
    base: defaultBase(),
    access: localStorage.getItem(LS.access) || null,
    refresh: localStorage.getItem(LS.refresh) || null,
    user: null,
    policyVersion: null,
    // Guest 18+ self-cert: honored by the backend only for anonymous requests.
    guestAdult: localStorage.getItem(LS.guestAdult) === '1',
  };

  function installId() {
    var id = localStorage.getItem(LS.installId);
    if (!id) {
      id = (crypto.randomUUID && crypto.randomUUID()) || String(Date.now()) + Math.random().toString(16).slice(2);
      localStorage.setItem(LS.installId, id);
    }
    return id;
  }

  function setTokens(access, refresh) {
    state.access = access || null;
    state.refresh = refresh || null;
    if (access) localStorage.setItem(LS.access, access);
    else localStorage.removeItem(LS.access);
    if (refresh) localStorage.setItem(LS.refresh, refresh);
    else localStorage.removeItem(LS.refresh);
  }

  function applyAuthPayload(data) {
    if (data && data.user) state.user = data.user;
    if (data && data.policyVersion) state.policyVersion = data.policyVersion;
    if (data && data.accessToken) setTokens(data.accessToken, data.refreshToken || state.refresh);
    return data;
  }

  /* ---- friendly errors ---- */
  var ERROR_TEXT = {
    invalid_credentials: 'Wrong email or password.',
    email_taken: 'An account with that email already exists.',
    underage: 'You must be 18 or older to use The Stoop.',
    account_banned: 'This account has been banned.',
    ban_evasion: 'Sign-up was blocked. If you believe this is a mistake, reach out on Discord.',
    invalid_input: 'Please check the form — something looks off.',
    two_factor_required: 'Enter the 6-digit code from your authenticator app.',
    invalid_code: 'That code didn’t match — try again.',
    policy_not_accepted: 'Please read and accept the Acceptable Use Policy first.',
    version_mismatch: 'The policy changed while you were reading — please review it again.',
    already_reported: 'You already have an open report on this card.',
    too_many_reports: 'You’ve filed a lot of reports recently — please wait a while.',
    reason_required: 'Please add a reason.',
    invalid_message: 'Messages must be 1–2000 characters.',
    storage_unavailable: 'Uploads are temporarily unavailable — try again soon.',
    not_found: 'That wasn’t found — it may have been removed.',
    use_dashboard: 'Moderator accounts are managed from the dashboard.',
    payload_too_large: 'That file is too big.',
    unsupported_media: 'That image type isn’t supported — use PNG, JPEG, or WebP.',
  };

  function ApiError(status, code, detail) {
    var e = new Error(ERROR_TEXT[code] || detail || 'Something went wrong (' + (code || status) + ').');
    e.name = 'ApiError';
    e.status = status;
    e.code = code || '';
    return e;
  }

  /* ---- HTTP core with single-flight refresh ---- */
  var refreshing = null;

  function doRefresh() {
    if (!state.refresh) return Promise.reject(ApiError(401, 'unauthorized'));
    if (refreshing) return refreshing;
    refreshing = fetch(state.base + '/auth/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: state.refresh }),
    })
      .then(function (r) {
        if (!r.ok) throw ApiError(r.status, 'unauthorized');
        return r.json();
      })
      .then(function (data) {
        applyAuthPayload(data);
        return data;
      })
      .catch(function (e) {
        setTokens(null, null);
        state.user = null;
        throw e;
      })
      .finally(function () {
        refreshing = null;
      });
    return refreshing;
  }

  function rawFetch(method, path, body, opts) {
    opts = opts || {};
    var headers = opts.headers || {};
    if (state.access && !opts.noAuth) headers.Authorization = 'Bearer ' + state.access;
    // Guest 18+ self-cert rides read-only calls; ignored server-side once signed in.
    else if (!state.access && state.guestAdult) headers['X-Guest-Adult'] = '1';
    var init = { method: method, headers: headers };
    if (body instanceof FormData) init.body = body;
    else if (body !== undefined && body !== null) {
      headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(body);
    }
    return fetch(state.base + path, init);
  }

  /** api('GET', '/characters?...') → parsed JSON. Retries once through a token
      refresh on 401. Rejects with ApiError carrying a friendly message. */
  function api(method, path, body, opts) {
    opts = opts || {};
    return rawFetch(method, path, body, opts).then(function (r) {
      if (r.status === 401 && !opts.noAuth && !opts._retried && state.refresh) {
        return doRefresh().then(function () {
          opts._retried = true;
          return api(method, path, body, opts);
        });
      }
      if (r.status === 204) return {};
      var isJson = (r.headers.get('content-type') || '').indexOf('application/json') >= 0;
      return (isJson ? r.json() : r.text()).then(function (data) {
        if (!r.ok) {
          var code = data && typeof data === 'object' ? data.error : '';
          throw ApiError(r.status, code, typeof data === 'string' ? '' : undefined);
        }
        return data;
      });
    });
  }

  /** Auth-gated binary fetch (card art). Resolves to a Blob. */
  function apiBlob(path, opts) {
    opts = opts || {};
    return rawFetch('GET', path, undefined, opts).then(function (r) {
      if (r.status === 401 && !opts._retried && state.refresh) {
        return doRefresh().then(function () {
          opts._retried = true;
          return apiBlob(path, opts);
        });
      }
      if (!r.ok) throw ApiError(r.status, '');
      return r.blob();
    });
  }

  /* ---- domain calls ---- */
  var Api = {
    state: state,
    installId: installId,
    error: ApiError,

    /* auth */
    signup: function (email, password, displayName, dateOfBirth) {
      return api('POST', '/auth/signup', {
        email: email, password: password, displayName: displayName,
        dateOfBirth: dateOfBirth, installId: installId(),
      }, { noAuth: true }).then(applyAuthPayload);
    },
    login: function (email, password, totp) {
      var body = { email: email, password: password, installId: installId() };
      if (totp) body.totp = totp;
      return api('POST', '/auth/login', body, { noAuth: true }).then(applyAuthPayload);
    },
    logout: function () {
      var p = state.refresh
        ? api('POST', '/auth/logout', { refreshToken: state.refresh }).catch(function () {})
        : Promise.resolve();
      return p.finally(function () {
        setTokens(null, null);
        state.user = null;
        Api.ws.close();
      });
    },
    me: function () {
      return api('GET', '/auth/me').then(applyAuthPayload);
    },
    acceptPolicy: function (version) {
      return api('POST', '/auth/accept-policy', { version: version }).then(applyAuthPayload);
    },
    setDisplayName: function (displayName) {
      return api('POST', '/auth/display-name', { displayName: displayName }).then(applyAuthPayload);
    },
    setNsfw: function (enabled) {
      return api('POST', '/auth/nsfw', { enabled: enabled }).then(applyAuthPayload);
    },
    changePassword: function (currentPassword, newPassword) {
      return api('POST', '/auth/change-password', { currentPassword: currentPassword, newPassword: newPassword });
    },
    deleteAccount: function () {
      return api('DELETE', '/auth/me').then(function () {
        setTokens(null, null);
        state.user = null;
        Api.ws.close();
      });
    },
    policy: function () {
      return api('GET', '/policy', undefined, { noAuth: true });
    },
    // Guest 18+ self-cert. Drops the avatar cache so NSFW art (previously 404'd)
    // is refetched with the new header.
    setGuestAdult: function (on) {
      state.guestAdult = !!on;
      if (on) localStorage.setItem(LS.guestAdult, '1');
      else localStorage.removeItem(LS.guestAdult);
      avatarCache.clear();
    },

    /* 2FA */
    twoFaSetup: function () { return api('POST', '/2fa/setup', {}); },
    twoFaEnable: function (totp) { return api('POST', '/2fa/enable', { totp: totp }); },
    twoFaDisable: function (totp) { return api('POST', '/2fa/disable', { totp: totp }); },

    /* browse */
    browse: function (params) {
      var q = new URLSearchParams();
      Object.keys(params || {}).forEach(function (k) {
        if (params[k] !== undefined && params[k] !== null && params[k] !== '') q.set(k, params[k]);
      });
      return api('GET', '/characters?' + q.toString());
    },
    cardDetail: function (id) { return api('GET', '/characters/' + encodeURIComponent(id)); },
    vote: function (id, value) { return api('POST', '/characters/' + encodeURIComponent(id) + '/vote', { value: value }); },
    download: function (id) { return api('POST', '/characters/' + encodeURIComponent(id) + '/download', {}); },
    report: function (characterId, category, reason) {
      return api('POST', '/reports', { characterId: characterId, category: category, reason: reason });
    },

    /* creators */
    creator: function (id) { return api('GET', '/creators/' + encodeURIComponent(id)); },
    follow: function (id) { return api('POST', '/creators/' + encodeURIComponent(id) + '/follow', {}); },
    unfollow: function (id) { return api('DELETE', '/creators/' + encodeURIComponent(id) + '/follow'); },
    following: function () { return api('GET', '/me/following'); },

    /* own cards */
    myCharacters: function () { return api('GET', '/me/characters'); },
    myDownloads: function () { return api('GET', '/me/downloads'); },
    deleteCharacter: function (id) { return api('DELETE', '/characters/' + encodeURIComponent(id)); },
    uploadCharacter: function (payload, avatarBlob, avatarName) {
      var fd = new FormData();
      fd.append('payload', JSON.stringify(payload));
      fd.append('avatar', avatarBlob, avatarName || 'avatar.png');
      return api('POST', '/characters', fd);
    },
    uploadVersion: function (id, payload, avatarBlob, avatarName) {
      var fd = new FormData();
      fd.append('payload', JSON.stringify(payload));
      fd.append('avatar', avatarBlob, avatarName || 'avatar.png');
      return api('POST', '/characters/' + encodeURIComponent(id) + '/versions', fd);
    },

    /* messages */
    messages: function () { return api('GET', '/me/messages'); },
    unread: function () { return api('GET', '/me/messages/unread'); },
    markRead: function () { return api('POST', '/me/messages/read', {}); },
    sendMessage: function (body) { return api('POST', '/me/messages', { body: body }); },

    /* assets (auth-gated art) */
    assetBlob: function (assetId) { return apiBlob('/assets/' + encodeURIComponent(assetId) + '/raw'); },
  };

  /* ---- avatar cache: assetId → objectURL promise ---- */
  var avatarCache = new Map();
  Api.avatarUrl = function (assetId) {
    if (!assetId) return Promise.resolve(null);
    if (!avatarCache.has(assetId)) {
      avatarCache.set(
        assetId,
        Api.assetBlob(assetId)
          .then(function (b) { return URL.createObjectURL(b); })
          .catch(function () {
            avatarCache.delete(assetId); // allow retry later
            return null;
          })
      );
    }
    return avatarCache.get(assetId);
  };

  /* ---- WebSocket: live messages, typing, card stats ---- */
  var ws = {
    sock: null,
    timer: null,
    wanted: false,
    handlers: { message: [], typing: [], cardStats: [], status: [] },
    on: function (type, fn) { this.handlers[type].push(fn); },
    off: function (type, fn) {
      var a = this.handlers[type] || [];
      var i = a.indexOf(fn);
      if (i >= 0) a.splice(i, 1);
    },
    emit: function (type, data) {
      (this.handlers[type] || []).forEach(function (fn) {
        try { fn(data); } catch (e) { console.error(e); }
      });
    },
    connect: function () {
      ws.wanted = true;
      if (!state.access || (ws.sock && ws.sock.readyState <= 1)) return;
      var url = state.base.replace(/^http/, 'ws') + '/ws?token=' + encodeURIComponent(state.access);
      var s = new WebSocket(url);
      ws.sock = s;
      s.onmessage = function (ev) {
        var f;
        try { f = JSON.parse(ev.data); } catch (e) { return; }
        if (f && f.type) ws.emit(f.type, f);
      };
      s.onopen = function () { ws.emit('status', { connected: true }); };
      s.onclose = function () {
        ws.emit('status', { connected: false });
        ws.sock = null;
        if (ws.wanted) {
          clearTimeout(ws.timer);
          // token may have rotated while we were down — refresh cheaply first
          ws.timer = setTimeout(function () {
            if (!ws.wanted) return;
            Api.me().catch(function () {}).finally(function () { ws.connect(); });
          }, 3000);
        }
      };
      s.onerror = function () { try { s.close(); } catch (e) {} };
    },
    sendTyping: function (isTyping) {
      if (ws.sock && ws.sock.readyState === 1) {
        ws.sock.send(JSON.stringify({ type: 'typing', isTyping: !!isTyping }));
      }
    },
    close: function () {
      ws.wanted = false;
      clearTimeout(ws.timer);
      if (ws.sock) { try { ws.sock.close(); } catch (e) {} ws.sock = null; }
    },
  };
  Api.ws = ws;

  window.Stoop.api = Api;
})();
