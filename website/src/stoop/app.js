/* The Stoop hub — router + boot.
   Hash-routed single page: everything renders into #stoop-app. Signed-in users
   get the full hub; anonymous visitors can opt into a limited GUEST mode
   (browse + download only) to try the porch before making an account. */
(function () {
  'use strict';
  var S = window.Stoop;
  var el, ui, Api;

  var root = null;      // #stoop-app
  var headerBar = null; // in-app tab bar
  var viewMount = null;
  var unreadBadge = null;
  var unread = 0;
  // Guest mode persists for the tab so a refresh doesn't bounce back to the wall.
  var guest = sessionStorage.getItem('stoop.guest') === '1';

  var app = {
    setUnread: function (n) {
      unread = Math.max(0, n | 0);
      if (!unreadBadge) return;
      unreadBadge.textContent = unread ? String(unread) : '';
      unreadBadge.classList.toggle('hub-hidden', !unread);
    },
    paintHeader: paintHeader,
    onAuthed: onAuthed,
    onLoggedOut: onLoggedOut,
    enterGuest: enterGuest,
    exitGuest: exitGuest,
    isGuest: function () { return guest && !Api.state.user; },
  };
  S.app = app;

  var TABS = [
    { hash: '#/', label: 'Browse', match: function (h) { return h === '#/' || h.indexOf('#/card/') === 0 || h.indexOf('#/creator/') === 0; } },
    { hash: '#/mine', label: 'My cards', match: function (h) { return h.indexOf('#/mine') === 0 || h.indexOf('#/submit') === 0; } },
    { hash: '#/inbox', label: 'Inbox', match: function (h) { return h.indexOf('#/inbox') === 0; } },
    { hash: '#/account', label: 'Account', match: function (h) { return h.indexOf('#/account') === 0; } },
  ];

  function paintHeader() {
    if (!headerBar) return;
    var u = Api.state.user;
    var h = location.hash || '#/';
    if (!u) {
      // Guest bar: browse only, with a standing invitation to join.
      if (!app.isGuest()) { headerBar.classList.add('hub-hidden'); return; }
      headerBar.classList.remove('hub-hidden');
      headerBar.replaceChildren(
        el('div', { class: 'hub-tabs' }, [
          el('a', { class: 'hub-tab-link on', href: '#/' }, 'Browse'),
          el('span', { class: 'hub-guest-tag' }, 'Guest'),
        ]),
        el('div', { class: 'hub-user' }, [
          el('a', { class: 'btn btn-amber hub-share-btn', href: '#/signup' }, 'Create account'),
          el('a', { class: 'hub-linklike', href: '#/signin' }, 'Sign in'),
        ])
      );
      return;
    }
    headerBar.classList.remove('hub-hidden');
    headerBar.replaceChildren(
      el('div', { class: 'hub-tabs' }, TABS.map(function (t) {
        var extra = null;
        if (t.label === 'Inbox') {
          unreadBadge = el('span', { class: 'hub-unread' + (unread ? '' : ' hub-hidden') }, unread ? String(unread) : '');
          extra = unreadBadge;
        }
        return el('a', { class: 'hub-tab-link' + (t.match(h) ? ' on' : ''), href: t.hash }, [t.label, extra]);
      })),
      el('div', { class: 'hub-user' }, [
        el('a', { class: 'btn btn-amber hub-share-btn', href: '#/submit' }, '+ Share a card'),
        el('span', { class: 'hub-user-name', title: u.email || '' }, u.displayName || ''),
      ])
    );
  }

  /* ------------------------------- routing ------------------------------- */
  function route() {
    var h = location.hash || '#/';
    var authed = !!Api.state.user;

    if (!authed) {
      // "#/signin" / "#/signup" always leave guest mode for the real auth wall.
      if (h === '#/signin' || h === '#/login') { exitGuest(); headerBar.classList.add('hub-hidden'); S.viewsAuth.renderAuth(viewMount, 'login'); return; }
      if (h === '#/signup') { exitGuest(); headerBar.classList.add('hub-hidden'); S.viewsAuth.renderAuth(viewMount, 'signup'); return; }
      if (app.isGuest()) {
        paintHeader();
        window.scrollTo(0, 0);
        return routeGuest(h);
      }
      headerBar.classList.add('hub-hidden');
      S.viewsAuth.renderAuth(viewMount, 'login');
      return;
    }
    if (needsPolicy()) {
      headerBar.classList.add('hub-hidden');
      S.viewsAuth.renderPolicyGate(viewMount);
      return;
    }
    paintHeader();
    window.scrollTo(0, 0);

    var m;
    if ((m = h.match(/^#\/card\/([\w-]+)/))) return S.viewsBrowse.renderCard(viewMount, m[1]);
    if ((m = h.match(/^#\/creator\/([\w-]+)/))) return S.viewsBrowse.renderCreator(viewMount, m[1]);
    if ((m = h.match(/^#\/submit\/([\w-]+)/))) return S.viewsMy.renderSubmit(viewMount, m[1]);
    if (h.indexOf('#/submit') === 0) return S.viewsMy.renderSubmit(viewMount, null);
    if (h.indexOf('#/mine') === 0) return S.viewsMy.renderMine(viewMount);
    if (h.indexOf('#/inbox') === 0) return S.viewsInbox.renderInbox(viewMount);
    if (h.indexOf('#/account') === 0) return S.viewsInbox.renderAccount(viewMount);
    if (h === '#/login' || h === '#/signup') { location.hash = '#/'; return; }
    return S.viewsBrowse.renderBrowse(viewMount);
  }

  // Guests may only browse cards, view detail, and view creators — everything
  // else redirects to the invitation to join.
  function routeGuest(h) {
    var m;
    if ((m = h.match(/^#\/card\/([\w-]+)/))) return S.viewsBrowse.renderCard(viewMount, m[1]);
    if ((m = h.match(/^#\/creator\/([\w-]+)/))) return S.viewsBrowse.renderCreator(viewMount, m[1]);
    if (h !== '#/' && h !== '') {
      ui.toast('Make a free account to use that.');
      location.hash = '#/';
      return;
    }
    return S.viewsBrowse.renderBrowse(viewMount);
  }

  function needsPolicy() {
    var u = Api.state.user;
    return !!(u && Api.state.policyVersion && u.acceptedPolicyVersion !== Api.state.policyVersion);
  }

  /* ------------------------------ guest mode ------------------------------ */
  function enterGuest() {
    guest = true;
    sessionStorage.setItem('stoop.guest', '1');
    showGuestNotice();
    if (location.hash === '#/login' || location.hash === '#/signup' || !location.hash) location.hash = '#/';
    else route();
  }

  function exitGuest() {
    guest = false;
    sessionStorage.removeItem('stoop.guest');
  }

  function showGuestNotice() {
    ui.dialog('You’re browsing as a guest', [
      el('p', null, [
        'Guest access is intentionally limited — you can ',
        el('strong', null, 'browse and download cards'),
        ', and that’s it. Voting, following, reporting, messaging the mods, and sharing your own characters all need a free account.',
      ]),
      el('p', { class: 'hub-dim' }, 'NSFW cards stay hidden until you confirm you’re 18 or older (the 🔞 button on the browse bar).'),
      el('p', null, 'We hope you find some characters on The Stoop that you enjoy — and that you’ll join us. Make an account to share your own characters and unlock the full porch.'),
    ], [
      { label: 'Keep browsing', kind: 'btn-ghost' },
      { label: 'Create an account', kind: 'btn-amber', onclick: function () { location.hash = '#/signup'; } },
    ]);
  }

  /* ------------------------------ auth flow ------------------------------ */
  function onAuthed() {
    exitGuest();
    connectLive();
    Api.unread().then(function (r) { app.setUnread(r.count || 0); }).catch(function () {});
    if (location.hash === '#/login' || location.hash === '#/signup' || location.hash === '#/signin' || !location.hash) {
      location.hash = '#/'; // triggers route()
    } else {
      route();
    }
  }

  function onLoggedOut() {
    Api.ws.close();
    app.setUnread(0);
    location.hash = '#/login';
    route();
  }

  var liveWired = false;
  function connectLive() {
    Api.ws.connect();
    if (liveWired) return;
    liveWired = true;
    Api.ws.on('cardStats', ui.applyCardStats);
    Api.ws.on('message', function (f) {
      var m = f.message;
      if (!m || !m.fromMod) return;
      if ((location.hash || '').indexOf('#/inbox') === 0) return; // inbox handles it
      app.setUnread(unread + 1);
      ui.toast(m.kind === 'SYSTEM' ? '📣 ' + m.body : '💬 New message from the moderators');
    });
  }

  /* --------------------------------- boot --------------------------------- */
  function boot() {
    el = S.ui.el;
    ui = S.ui;
    Api = S.api;
    root = document.getElementById('stoop-app');
    if (!root) return;

    headerBar = el('div', { class: 'hub-bar hub-hidden' });
    viewMount = el('div', { class: 'hub-view' });
    root.replaceChildren(headerBar, viewMount);

    window.addEventListener('hashchange', route);

    if (Api.state.access || Api.state.refresh) {
      viewMount.replaceChildren(ui.spinner('Unlocking the door…'));
      Api.me()
        .then(function () { onAuthed(); })
        .catch(function () { route(); }); // tokens dead → login
    } else {
      route();
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
