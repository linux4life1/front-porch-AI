/* The Stoop hub — inbox (Notifications vs Moderator chat) + Account.
   The web inbox splits the single mod thread into two tabs using the additive
   `kind` field: SYSTEM = automated decision notices (card approved/denied),
   everything else = the human conversation with the mod team. Messages without
   a kind (older servers) count as chat. */
(function () {
  'use strict';
  var S = window.Stoop;
  var el, ui, Api;

  var activeTab = 'notifications';
  // Live-update handlers for the currently rendered inbox — unhooked on
  // re-render so stale copies can't mark messages read from other views.
  var liveMsgHandler = null;
  var liveTypingHandler = null;

  function isSystem(m) { return m.kind === 'SYSTEM'; }

  /* ================================= inbox ================================= */
  function renderInbox(mount) {
    if (liveMsgHandler) { Api.ws.off('message', liveMsgHandler); liveMsgHandler = null; }
    if (liveTypingHandler) { Api.ws.off('typing', liveTypingHandler); liveTypingHandler = null; }
    mount.replaceChildren(ui.spinner());
    Api.messages().then(function (res) {
      var all = res.items || [];
      Api.markRead().catch(function () {});
      S.app.setUnread(0);

      var notifications = all.filter(isSystem).reverse(); // newest first
      var chat = all.filter(function (m) { return !isSystem(m); });

      /* ---- notifications tab ---- */
      function notifNode(m) {
        var approved = m.body.indexOf('approved and') >= 0 || m.body.indexOf('is approved') >= 0;
        var rejected = m.body.indexOf('wasn’t approved') >= 0 || m.body.indexOf("wasn't approved") >= 0;
        var ico = approved ? '✅' : rejected ? '📝' : '📣';
        return el('div', { class: 'hub-notif' + (approved ? ' ok' : rejected ? ' bad' : '') }, [
          el('span', { class: 'hub-notif-ico' }, ico),
          el('div', { class: 'hub-notif-body' }, [
            el('p', null, m.body),
            el('div', { class: 'hub-notif-meta' }, [
              m.character ? el('a', { href: '#/card/' + m.character.id, class: 'hub-tag' }, 're: ' + m.character.name) : null,
              el('span', { class: 'hub-dim hub-small' }, ui.timeAgo(m.createdAt)),
            ]),
          ]),
        ]);
      }
      var notifPane = el('div', { class: 'hub-pane' },
        notifications.length
          ? notifications.map(notifNode)
          : [ui.emptyState('📣', 'No notifications yet', 'Approvals and review notes for your cards land here.')]);

      /* ---- chat tab ---- */
      function bubble(m) {
        return el('div', { class: 'hub-msg' + (m.fromMod ? ' mod' : ' me') }, [
          el('span', { class: 'hub-msg-who' }, m.fromMod ? 'Moderator' : 'You'),
          el('div', { class: 'hub-msg-body' }, [
            m.character ? el('span', { class: 'hub-msg-re' }, 're: ' + m.character.name) : null,
            el('p', null, m.body),
          ]),
          el('span', { class: 'hub-dim hub-small' }, ui.timeAgo(m.createdAt)),
        ]);
      }
      var thread = el('div', { class: 'hub-thread' },
        chat.length ? chat.map(bubble)
          : [ui.emptyState('💬', 'No conversation yet', 'Questions about a review or the rules? The mod team reads this thread.')]);
      var typingLine = el('p', { class: 'hub-typing hub-hidden' }, 'Moderator is typing…');

      var input = el('textarea', { class: 'hub-textarea', rows: '2', maxlength: '2000', placeholder: 'Write to the moderators…' });
      var sendBtn = el('button', { class: 'btn btn-amber', type: 'button', onclick: send }, 'Send');
      function send() {
        var body = input.value.trim();
        if (!body) return;
        sendBtn.disabled = true;
        Api.sendMessage(body).then(function (r) {
          input.value = '';
          if (thread.querySelector('.hub-empty')) thread.replaceChildren();
          thread.appendChild(bubble(r.message));
          thread.scrollTop = thread.scrollHeight;
        }).catch(function (e) { ui.toast(e.message, 'err'); })
          .finally(function () { sendBtn.disabled = false; });
      }
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
      });
      var typingTimer = null;
      input.addEventListener('input', function () {
        Api.ws.sendTyping(true);
        clearTimeout(typingTimer);
        typingTimer = setTimeout(function () { Api.ws.sendTyping(false); }, 2500);
      });

      var chatPane = el('div', { class: 'hub-pane hub-hidden' }, [
        thread, typingLine,
        el('div', { class: 'hub-composer' }, [input, sendBtn]),
      ]);

      /* ---- live updates while the inbox is the active view ---- */
      function inboxOpen() {
        return (location.hash || '').indexOf('#/inbox') === 0 && document.body.contains(thread);
      }
      liveMsgHandler = function (f) {
        var m = f.message;
        if (!m || !inboxOpen()) return;
        if (isSystem(m)) {
          if (notifPane.querySelector('.hub-empty')) notifPane.replaceChildren();
          notifPane.prepend(notifNode(m));
        } else if (m.fromMod) {
          if (thread.querySelector('.hub-empty')) thread.replaceChildren();
          thread.appendChild(bubble(m));
          thread.scrollTop = thread.scrollHeight;
        }
        Api.markRead().catch(function () {});
        S.app.setUnread(0);
      };
      liveTypingHandler = function (f) {
        if (!f.fromMod || !inboxOpen()) return;
        typingLine.classList.toggle('hub-hidden', !f.isTyping);
      };
      Api.ws.on('message', liveMsgHandler);
      Api.ws.on('typing', liveTypingHandler);

      /* ---- tabs ---- */
      var sysUnseen = notifications.length;
      var tabs = el('div', { class: 'hub-tabbar' }, [
        el('button', { class: 'hub-tab' + (activeTab === 'notifications' ? ' on' : ''), type: 'button', onclick: function (e) { pick('notifications', e); } },
          'Notifications' + (sysUnseen ? ' (' + sysUnseen + ')' : '')),
        el('button', { class: 'hub-tab' + (activeTab === 'chat' ? ' on' : ''), type: 'button', onclick: function (e) { pick('chat', e); } }, 'Moderator chat'),
      ]);
      function pick(tab, e) {
        activeTab = tab;
        tabs.querySelectorAll('.hub-tab').forEach(function (t) { t.classList.remove('on'); });
        e.currentTarget.classList.add('on');
        notifPane.classList.toggle('hub-hidden', tab !== 'notifications');
        chatPane.classList.toggle('hub-hidden', tab !== 'chat');
        if (tab === 'chat') thread.scrollTop = thread.scrollHeight;
      }
      if (activeTab === 'chat') {
        notifPane.classList.add('hub-hidden');
        chatPane.classList.remove('hub-hidden');
      }

      mount.replaceChildren(el('div', { class: 'hub-inbox' }, [
        el('h2', null, 'Inbox'),
        el('p', { class: 'hub-dim' }, 'One private thread between you and the moderation team. Decision notices are filed under Notifications.'),
        tabs, notifPane, chatPane,
      ]));
      thread.scrollTop = thread.scrollHeight;
    }).catch(function (e) {
      mount.replaceChildren(ui.emptyState('🌫️', 'Couldn’t load your inbox', e.message));
    });
  }

  /* ================================ account ================================ */
  function renderAccount(mount) {
    var u = Api.state.user || {};

    /* display name */
    var nameIn = el('input', { type: 'text', maxlength: '40', value: u.displayName || '' });
    var nameBtn = el('button', { class: 'btn btn-ghost', type: 'button', onclick: function () {
      nameBtn.disabled = true;
      Api.setDisplayName(nameIn.value.trim())
        .then(function () { ui.toast('Display name updated.'); S.app.paintHeader(); })
        .catch(function (e) { ui.toast(e.message, 'err'); })
        .finally(function () { nameBtn.disabled = false; });
    } }, 'Save');

    /* nsfw */
    var nsfwIn = el('input', { type: 'checkbox' });
    nsfwIn.checked = !!u.nsfwEnabled;
    nsfwIn.addEventListener('change', function () {
      Api.setNsfw(nsfwIn.checked)
        .then(function () { ui.toast(nsfwIn.checked ? 'NSFW cards are now visible.' : 'NSFW cards are hidden.'); })
        .catch(function (e) { nsfwIn.checked = !nsfwIn.checked; ui.toast(e.message, 'err'); });
    });

    /* password */
    var curPw = el('input', { type: 'password', autocomplete: 'current-password', placeholder: 'Current password' });
    var newPw = el('input', { type: 'password', autocomplete: 'new-password', minlength: '8', placeholder: 'New password (8+ characters)' });
    var pwBtn = el('button', { class: 'btn btn-ghost', type: 'button', onclick: function () {
      if (newPw.value.length < 8) return ui.toast('New password must be at least 8 characters.', 'err');
      pwBtn.disabled = true;
      Api.changePassword(curPw.value, newPw.value)
        .then(function () { curPw.value = newPw.value = ''; ui.toast('Password changed. Other sessions were signed out.'); })
        .catch(function (e) { ui.toast(e.message, 'err'); })
        .finally(function () { pwBtn.disabled = false; });
    } }, 'Change password');

    /* 2FA */
    var twoFaLine = el('span', { class: 'hub-dim' }, u.twoFactorEnabled ? 'Two-factor is on.' : 'Two-factor is off.');
    var twoFaBtn = el('button', { class: 'btn btn-ghost', type: 'button' }, u.twoFactorEnabled ? 'Turn off 2FA' : 'Set up 2FA');
    twoFaBtn.addEventListener('click', function () {
      if (u.twoFactorEnabled) {
        var codeOff = el('input', { type: 'text', inputmode: 'numeric', maxlength: '6', placeholder: '6-digit code' });
        ui.dialog('Turn off two-factor', [el('p', { class: 'hub-dim' }, 'Enter a current code to confirm.'), codeOff], [
          { label: 'Cancel', kind: 'btn-ghost' },
          { label: 'Turn off', kind: 'btn-danger', onclick: function () {
            Api.twoFaDisable(codeOff.value.trim())
              .then(function () { return Api.me(); })
              .then(function () { ui.toast('Two-factor disabled.'); renderAccount(mount); })
              .catch(function (e) { ui.toast(e.message, 'err'); });
          } },
        ]);
      } else {
        Api.twoFaSetup().then(function (setup) {
          var code = el('input', { type: 'text', inputmode: 'numeric', maxlength: '6', placeholder: '6-digit code' });
          var qr = el('img', { class: 'hub-qr', alt: '2FA QR code', src: setup.qrDataUrl });
          ui.dialog('Set up two-factor', [
            el('p', { class: 'hub-dim' }, 'Scan with any authenticator app, then enter the code it shows.'),
            qr,
            el('p', { class: 'hub-small hub-dim hub-mono' }, setup.secret),
            code,
          ], [
            { label: 'Cancel', kind: 'btn-ghost' },
            { label: 'Enable', kind: 'btn-amber', onclick: function () {
              Api.twoFaEnable(code.value.trim())
                .then(function () { return Api.me(); })
                .then(function () { ui.toast('Two-factor enabled. 🔒'); renderAccount(mount); })
                .catch(function (e) { ui.toast(e.message, 'err'); });
            } },
          ]);
        }).catch(function (e) { ui.toast(e.message, 'err'); });
      }
    });

    /* delete */
    var delBtn = el('button', { class: 'btn btn-danger', type: 'button', onclick: function () {
      var confirmIn = el('input', { type: 'text', placeholder: 'Type DELETE to confirm' });
      ui.dialog('Delete your Stoop account?', [
        el('p', { class: 'hub-dim' }, 'This permanently erases your account, your uploaded cards, your votes, and your messages — here and in the app. Copies other people already downloaded are beyond our control.'),
        confirmIn,
      ], [
        { label: 'Cancel', kind: 'btn-ghost' },
        { label: 'Delete everything', kind: 'btn-danger', autoClose: false, onclick: function (close) {
          if (confirmIn.value.trim() !== 'DELETE') { ui.toast('Type DELETE to confirm.', 'err'); return false; }
          Api.deleteAccount()
            .then(function () { close(); ui.toast('Account deleted. Take care out there.'); S.app.onLoggedOut(); })
            .catch(function (e) { ui.toast(e.message, 'err'); });
          return false;
        } },
      ]);
    } }, 'Delete account…');

    function section(title, rows) {
      return el('div', { class: 'hub-acct-sect' }, [el('h3', null, title)].concat(rows));
    }

    mount.replaceChildren(el('div', { class: 'hub-account' }, [
      el('h2', null, 'Account'),
      el('p', { class: 'hub-dim' }, ['Signed in as ', el('b', null, u.email || ''), ' — one account for the hub and the app.']),
      section('Profile', [
        el('div', { class: 'hub-acct-row' }, [nameIn, nameBtn]),
      ]),
      section('Content', [
        el('label', { class: 'hub-aup-check' }, [nsfwIn, el('span', null, 'Show NSFW cards (you confirmed you’re 18+ when you signed up)')]),
        el('p', { class: 'hub-small hub-dim' }, [
          'The rules of the road: ',
          el('a', { href: '#', onclick: function (e) { e.preventDefault(); S.viewsAuth.showPolicyDialog(); } }, 'Acceptable Use Policy'),
        ]),
      ]),
      section('Security', [
        el('div', { class: 'hub-acct-row' }, [curPw, newPw, pwBtn]),
        el('div', { class: 'hub-acct-row' }, [twoFaLine, twoFaBtn]),
      ]),
      section('Get the app', [
        el('p', { class: 'hub-dim' }, 'The Stoop is built into Front Porch AI — download cards straight into your library, with Realism, Needs, voices, and group casts.'),
        el('a', { class: 'btn btn-amber', href: 'https://frontporchai.app/#get', target: '_blank', rel: 'noopener' }, 'Download Front Porch AI'),
      ]),
      section('Danger zone', [
        el('div', { class: 'hub-acct-row' }, [
          el('button', { class: 'btn btn-ghost', type: 'button', onclick: function () {
            Api.logout().then(function () { S.app.onLoggedOut(); });
          } }, 'Sign out'),
          delBtn,
        ]),
      ]),
    ]));
  }

  window.Stoop.viewsInbox = {
    renderInbox: function (m) { el = S.ui.el; ui = S.ui; Api = S.api; renderInbox(m); },
    renderAccount: function (m) { el = S.ui.el; ui = S.ui; Api = S.api; renderAccount(m); },
  };
})();
