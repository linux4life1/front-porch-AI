/* The Stoop hub — browse grid, card detail, creator profile.
   Live score/download counters ride the ws 'cardStats' frames via the
   data-stats-* attributes every counter renders with. */
(function () {
  'use strict';
  var S = window.Stoop;
  var el, ui, Api;

  var TAKE = 24;
  // Solo and group casts are kept strictly apart — a group never shows up in the
  // solo grid. Groups get their own tab (with a loud FPAI-only warning).
  var FILTERS = [
    { key: 'solo', label: 'Solo characters', type: 'solo' },
    { key: 'group', label: '👥 Group casts', type: 'group' },
    { key: 'following', label: '☆ Following', type: 'all' },
  ];
  var SORTS = [
    { key: 'newest', label: 'Newest' },
    { key: 'top', label: 'Top rated' },
    { key: 'downloads', label: 'Most downloaded' },
  ];

  // Sticky controls so leaving to a detail page and coming back feels stable.
  var browseState = { filter: 'solo', sort: 'newest', q: '' };

  function nsfwOn() {
    return Api.state.user ? !!Api.state.user.nsfwEnabled : !!Api.state.guestAdult;
  }

  /* ---- share links ----
     Path-based URLs (no #) so Discord/Slack crawlers hit the server-side OG
     page (Caddy maps /card/* + /creator/* onto the API's /share/ routes) and
     unfurl the card's real name, summary, and art instead of the site logo. */
  var HUB_ORIGIN = location.hostname === 'hub.frontporchai.app' ? location.origin : 'https://hub.frontporchai.app';

  // Prefer the display name in creator URLs (vanity: #/creator/SosukeAizen).
  // Names are unique server-side (claimed first-come), but only route-safe
  // ones fit the hash routes — anything else falls back to the immutable id.
  function creatorRef(c) {
    var name = c && c.displayName;
    return name && /^[\w-]{2,40}$/.test(name) ? name : (c && c.id) || '';
  }

  function shareBtn(kind, id) {
    var url = HUB_ORIGIN + '/' + kind + '/' + id;
    var btn = el('button', { class: 'hub-linklike', type: 'button', title: 'Copy a link that unfurls nicely in Discord & friends' }, '🔗 Share');
    btn.addEventListener('click', function () {
      var done = function () { ui.toast('Link copied — paste it anywhere.'); };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(done, function () { window.prompt('Copy this link:', url); });
      } else {
        window.prompt('Copy this link:', url);
      }
    });
    return btn;
  }

  /* ================================ browse ================================ */
  function renderBrowse(mount) {
    var page = 0;
    var grid = el('div', { class: 'hub-grid' });
    var moreBtn = el('button', { class: 'btn btn-ghost hub-more', type: 'button', onclick: function () { load(page + 1); } }, 'Load more');
    var moreWrap = el('div', { class: 'hub-more-wrap hub-hidden' }, moreBtn);
    var status = el('div');
    var showcase = el('div', { class: 'hub-showcase' });     // Mod's Picks hero + carousel
    var groupWarn = el('div');                                 // strong FPAI-only warning

    function activeFilter() {
      return FILTERS.filter(function (f) { return f.key === browseState.filter; })[0] || FILTERS[0];
    }

    function params(p) {
      var f = activeFilter();
      return {
        sort: browseState.sort,
        type: f.type,
        following: browseState.filter === 'following' ? 'true' : undefined,
        q: browseState.q || undefined,
        page: p,
        take: TAKE,
      };
    }

    // The Mod's Picks hero belongs on the main (solo) discovery view only — not
    // on the group tab, a search, or the personal Following feed. Cleared
    // synchronously first so a stale hero never lingers through a tab switch.
    function refreshChrome() {
      var f = browseState.filter;
      showcase.replaceChildren();
      if (!browseState.q && f === 'solo') S.viewsPicks.renderPicksShowcase(showcase, 'solo');
      ui.mountChildren(groupWarn, f === 'group' ? groupWarning() : null);
    }

    function load(p) {
      page = p;
      if (p === 0) {
        grid.replaceChildren();
        status.replaceChildren(ui.spinner('Looking around the porch…'));
        refreshChrome();
      }
      moreBtn.disabled = true;
      Api.browse(params(p)).then(function (res) {
        status.replaceChildren();
        var items = res.items || [];
        items.forEach(function (c) { grid.appendChild(ui.cardTile(c)); });
        if (p === 0 && !items.length) {
          status.replaceChildren(ui.emptyState('🪑', 'Nothing here yet',
            browseState.q ? 'No cards match that search. Try @creator or #tag.' :
            browseState.filter === 'following' ? 'Follow some creators and their new cards will show up here.' :
            'Check back soon — the neighbours are still writing.'));
        }
        moreWrap.classList.toggle('hub-hidden', items.length < TAKE);
        moreBtn.disabled = false;
      }).catch(function (e) {
        status.replaceChildren(ui.emptyState('🌫️', 'Couldn’t load cards', e.message));
      });
    }

    var search = el('input', {
      class: 'hub-search', type: 'search', value: browseState.q,
      placeholder: 'Search cards… (@creator, #tag)',
      onkeydown: function (e) { if (e.key === 'Enter') { browseState.q = search.value.trim(); load(0); } },
    });
    var sortSel = el('select', { class: 'hub-select', onchange: function () { browseState.sort = sortSel.value; load(0); } },
      SORTS.map(function (s) {
        var o = el('option', { value: s.key }, s.label);
        if (s.key === browseState.sort) o.selected = true;
        return o;
      }));

    // NSFW toggle right on the bar — works for accounts (persisted server-side)
    // and guests (18+ self-cert). Fixes the "can't turn NSFW off" complaint.
    var nsfwBtn = el('button', { class: 'hub-nsfw-toggle', type: 'button' });
    function paintNsfw() {
      var on = nsfwOn();
      nsfwBtn.textContent = on ? '🔞 18+ on' : '🔞 18+ off';
      nsfwBtn.classList.toggle('on', on);
      nsfwBtn.title = on ? 'NSFW cards are showing — click to hide' : 'Show NSFW cards (18+)';
    }
    nsfwBtn.addEventListener('click', function () {
      if (Api.state.user) {
        var next = !Api.state.user.nsfwEnabled;
        nsfwBtn.disabled = true;
        Api.setNsfw(next).then(function () {
          paintNsfw(); load(0);
          ui.toast(next ? '18+ cards are now showing.' : '18+ cards are hidden.');
        }).catch(function (e) { ui.toast(e.message, 'err'); })
          .finally(function () { nsfwBtn.disabled = false; });
      } else if (Api.state.guestAdult) {
        Api.setGuestAdult(false); paintNsfw(); load(0);
        ui.toast('18+ cards are hidden.');
      } else {
        ui.confirmAdult(function () { Api.setGuestAdult(true); paintNsfw(); load(0); });
      }
    });
    paintNsfw();

    var chipRow = el('div', { class: 'hub-chips' }, FILTERS.map(function (f) {
      return el('button', {
        class: 'hub-chip' + (browseState.filter === f.key ? ' on' : ''),
        type: 'button',
        onclick: function (e) {
          browseState.filter = f.key;
          chipRow.querySelectorAll('.hub-chip').forEach(function (c) { c.classList.remove('on'); });
          e.currentTarget.classList.add('on');
          load(0);
        },
      }, f.label);
    }));

    ui.mountChildren(mount, [
      ui.fpaiBanner(),
      el('div', { class: 'hub-controls' }, [search, sortSel, nsfwBtn]),
      chipRow,
      showcase,
      groupWarn,
      status,
      grid,
      moreWrap,
    ]);
    load(0);
  }

  // The loud, unmissable group warning shown on the Groups tab.
  function groupWarning() {
    return el('div', { class: 'hub-groupwarn' }, [
      el('span', { class: 'hub-groupwarn-ico' }, '⚠️'),
      el('div', null, [
        el('strong', null, 'Group casts open ONLY in Front Porch AI.'),
        el('p', null, [
          'A group card bundles multiple characters, their lorebooks, and shared Realism state. ',
          el('strong', null, 'No other app can read it'),
          ' — not SillyTavern, not Backyard, nothing. Download one only if you use Front Porch AI. ',
          el('a', { href: 'https://frontporchai.app/#get', target: '_blank', rel: 'noopener' }, 'Get the app →'),
        ]),
      ]),
    ]);
  }

  /* ============================== card detail ============================== */
  var REPORT_CATEGORIES = [
    { key: 'SPAM', label: 'Spam' },
    { key: 'MISLABELED', label: 'Wrong / missing NSFW label' },
    { key: 'ILLEGAL', label: 'Illegal content' },
    { key: 'STOLEN', label: 'Stolen / uncredited' },
    { key: 'LOW_EFFORT', label: 'Low effort' },
    { key: 'PROHIBITED_IMAGE', label: 'Prohibited image' },
    { key: 'OTHER', label: 'Other' },
  ];

  function textSection(title, text, open) {
    if (!text) return null;
    return el('details', { class: 'hub-sect', open: !!open }, [
      el('summary', null, title),
      el('pre', { class: 'hub-sect-text' }, text),
    ]);
  }

  /* V2 character_book — the section the detail page silently dropped (a card
     with lore looked loreless on the hub). Disabled entries stay hidden; an
     entry with no trigger keys is constant/always-active lore. */
  function lorebookSection(book) {
    var entries = (book && Array.isArray(book.entries)) ? book.entries : [];
    entries = entries.filter(function (e) { return e && e.enabled !== false; });
    if (!entries.length) return null;
    return el('details', { class: 'hub-sect' }, [
      el('summary', null, 'Lorebook (' + entries.length + (entries.length === 1 ? ' entry' : ' entries') + ')'),
      el('div', { class: 'hub-lore' }, entries.map(function (e) {
        var label = e.name || e.comment || '';
        var keys = Array.isArray(e.keys) ? e.keys.filter(Boolean) : [];
        var trigger = keys.length ? 'triggers: ' + keys.join(', ') : 'always active';
        return el('div', { class: 'hub-lore-entry' }, [
          el('div', { class: 'hub-lore-head' }, [
            el('strong', null, label || (keys.length ? keys.join(', ') : 'Entry')),
            el('span', { class: 'hub-dim hub-small' }, ' · ' + trigger),
          ]),
          el('pre', { class: 'hub-sect-text' }, e.content || ''),
        ]);
      })),
    ]);
  }

  function renderCard(mount, id) {
    mount.replaceChildren(ui.spinner());
    Api.cardDetail(id).then(function (c) {
      var isGroup = c.type === 'GROUP';
      var card = c.card || {};
      var signedIn = !!Api.state.user;

      /* --- votes (account only) --- */
      var myVote = c.myVote || 0;
      var upBtn = el('button', { class: 'hub-vote', type: 'button', title: 'Upvote' }, '▲');
      var dnBtn = el('button', { class: 'hub-vote', type: 'button', title: 'Downvote' }, '▼');
      function paintVotes() {
        upBtn.classList.toggle('on', myVote === 1);
        dnBtn.classList.toggle('dn', myVote === -1);
      }
      function castVote(v) {
        var next = myVote === v ? 0 : v;
        Api.vote(id, next).then(function (r) {
          myVote = r.myVote;
          paintVotes();
          document.querySelectorAll('[data-stats-score="' + id + '"]').forEach(function (n) { n.textContent = ui.num(r.score); });
        }).catch(function (e) { ui.toast(e.message, 'err'); });
      }
      upBtn.addEventListener('click', function () { castVote(1); });
      dnBtn.addEventListener('click', function () { castVote(-1); });
      paintVotes();

      /* --- download (everyone, incl. guests) --- */
      var dlBtn = el('button', { class: 'btn btn-amber', type: 'button' }, '⤓ Download card');
      dlBtn.addEventListener('click', function () {
        ui.downloadCard({ id: id, name: c.name, type: c.type, primaryAssetId: c.primaryAssetId }, dlBtn);
      });

      /* --- report (account only) --- */
      function showReport() {
        var sel = el('select', { class: 'hub-select hub-wide' }, REPORT_CATEGORIES.map(function (r) {
          return el('option', { value: r.key }, r.label);
        }));
        var reason = el('textarea', { class: 'hub-textarea', rows: '3', maxlength: '500', placeholder: 'What’s wrong? (optional, but it helps)' });
        ui.dialog('Report “' + c.name + '”', [
          el('p', { class: 'hub-dim' }, 'Reports go straight to the moderators. Honest reports only — see the AUP.'),
          sel, reason,
        ], [
          { label: 'Cancel', kind: 'btn-ghost' },
          {
            label: 'Send report', kind: 'btn-danger',
            onclick: function () {
              Api.report(id, sel.value, reason.value.trim())
                .then(function () { ui.toast('Report sent. Thank you for keeping the porch clean.'); })
                .catch(function (e) { ui.toast(e.message, 'err'); });
            },
          },
        ]);
      }

      /* --- group members --- */
      var membersBlock = null;
      if (isGroup) {
        var members = card.raw_member_data || card.members || [];
        membersBlock = el('div', { class: 'hub-members' }, [
          el('h3', null, 'The cast (' + members.length + ')'),
          el('div', { class: 'hub-member-list' }, members.map(function (m) {
            return el('div', { class: 'hub-member' }, [
              el('b', null, m.name || 'Unnamed'),
              el('span', { class: 'hub-dim' }, (m.description || '').slice(0, 140) || '—'),
            ]);
          })),
        ]);
      }

      var caveat = isGroup
        ? el('div', { class: 'hub-caveat group' }, [
            el('span', { class: 'hub-caveat-ico' }, '⚠️'),
            el('div', null, [
              el('strong', null, 'This group cast opens ONLY in Front Porch AI. '),
              'A group card bundles multiple characters, their lorebooks, and shared Realism state into one file. ',
              el('strong', null, 'No other app can read it'),
              ' — not SillyTavern, not Backyard, nothing. Only download it if you use Front Porch AI, where it imports in one tap.',
            ]),
          ])
        : el('div', { class: 'hub-caveat' }, [
            el('strong', null, '🛋️ Best experienced in Front Porch AI. '),
            'This card works in any V2-compatible app, but its Realism & Needs data (moods, bond, trust) only comes alive in FPAI — the recommended app for every card on The Stoop.',
          ]);

      // Guests can download but not vote/report — invite them to join instead.
      // Sharing is for everyone.
      var actionExtras = signedIn
        ? [
            el('span', { class: 'hub-votebox' }, [upBtn, dnBtn]),
            shareBtn('card', id),
            el('button', { class: 'hub-linklike', type: 'button', onclick: showReport }, '⚑ Report'),
          ]
        : [shareBtn('card', id), el('a', { class: 'hub-signin-nudge', href: '#/signin' }, 'Sign in to vote, follow & report')];

      var alts = Array.isArray(card.alternate_greetings) ? card.alternate_greetings.filter(Boolean).join('\n\n———\n\n') : '';

      mount.replaceChildren(el('div', { class: 'hub-detail' }, [
        el('a', { class: 'hub-back', href: '#/' }, '← Back to browsing'),
        el('div', { class: 'hub-detail-top' }, [
          el('div', { class: 'hub-detail-art' }, [ui.avatarImg(c.primaryAssetId, c.name, 'hub-detail-img')]),
          el('div', { class: 'hub-detail-info' }, [
            el('div', { class: 'hub-detail-badges' }, [
              isGroup ? el('span', { class: 'hub-badge hub-badge-group' }, '👥 Group cast') : null,
              c.nsfw ? el('span', { class: 'hub-badge hub-badge-nsfw' }, '18+') : null,
              c.modPick ? el('span', { class: 'hub-badge hub-badge-pick' }, '★ Mod’s Pick') : null,
            ]),
            el('h2', { class: 'hub-detail-name' }, c.name),
            c.creator ? el('a', { class: 'hub-detail-creator', href: '#/creator/' + creatorRef(c.creator) }, (c.originalCreator ? 'uploaded by ' : 'by ') + c.creator.displayName + ' →') : null,
            c.originalCreator ? el('div', { class: 'hub-detail-origcreator' }, 'created by ' + c.originalCreator) : null,
            el('p', { class: 'hub-detail-summary' }, c.summary || ''),
            (c.tags && c.tags.length)
              ? el('div', { class: 'hub-tags' }, c.tags.map(function (t) {
                  return el('a', { class: 'hub-tag', href: '#/', onclick: function () { browseState.q = '#' + t; } }, '#' + t);
                }))
              : null,
            el('div', { class: 'hub-detail-stats' }, [
              ui.statsSpan(c),
              el('span', { class: 'hub-dim' }, 'v' + (c.version || 1) + (c.tokenCount ? ' · ~' + ui.num(c.tokenCount) + ' tokens' : '')),
            ]),
            el('div', { class: 'hub-detail-actions' }, [dlBtn].concat(actionExtras)),
            caveat,
          ]),
        ]),
        membersBlock,
        el('div', { class: 'hub-sects' }, [
          textSection('Description', card.description, true),
          textSection('Personality', card.personality),
          textSection('Scenario', card.scenario),
          textSection('First message', card.first_mes || card.first_message),
          textSection('Alternate greetings', alts),
          textSection('Example dialogue', card.mes_example),
          lorebookSection(card.character_book),
        ]),
      ]));
    }).catch(function (e) {
      mount.replaceChildren(ui.emptyState('🌫️', 'Couldn’t load that card', e.message));
    });
  }

  /* ============================ creator profile ============================ */
  function renderCreator(mount, id) {
    mount.replaceChildren(ui.spinner());
    Api.creator(id).then(function (cr) {
      var followBtn = null;
      if (!Api.state.user) {
        followBtn = el('a', { class: 'hub-signin-nudge', href: '#/signin' }, 'Sign in to follow');
      } else if (!cr.isMe) {
        followBtn = el('button', { class: 'btn ' + (cr.following ? 'btn-ghost' : 'btn-amber'), type: 'button' },
          cr.following ? '✓ Following' : '+ Follow');
        followBtn.addEventListener('click', function () {
          // Always follow by the resolved user id — the route param may be a
          // vanity display name, which the follow endpoints don't accept.
          var call = cr.following ? Api.unfollow(cr.id) : Api.follow(cr.id);
          call.then(function (r) {
            cr.following = r.following;
            cr.followers = r.followers;
            followBtn.textContent = cr.following ? '✓ Following' : '+ Follow';
            followBtn.className = 'btn ' + (cr.following ? 'btn-ghost' : 'btn-amber');
            followers.textContent = ui.num(cr.followers) + ' follower' + (cr.followers === 1 ? '' : 's');
          }).catch(function (e) { ui.toast(e.message, 'err'); });
        });
      }
      var followers = el('span', { class: 'hub-dim' }, ui.num(cr.followers) + ' follower' + (cr.followers === 1 ? '' : 's'));
      var cards = cr.cards || [];

      // Lifetime stats over every approved card (server-side, not the visible
      // slice) so SFW-only viewers see the same numbers.
      var stats = cr.stats || {};
      var totalCards = stats.cards != null ? stats.cards : cards.length;
      var statLine = el('span', { class: 'hub-dim' },
        ui.num(totalCards) + ' cards · ' +
        ui.num(stats.downloads || 0) + ' downloads · ' +
        ui.num(stats.score || 0) + ' net votes' +
        (cards.length < totalCards ? ' · some hidden (18+ off)' : ''));

      // Bio + external links (creator-controlled; the server only accepts
      // http(s) URLs). Links double as public self-attribution for creators
      // cross-posting their own catalogs from chub/Backyard.
      var bioBlock = (cr.bio || '').trim()
        ? el('p', { class: 'hub-creator-bio' }, cr.bio.trim())
        : null;
      var creatorLinks = cr.links || cr.profileLinks || [];
      var linkList = creatorLinks.length
        ? el('div', { class: 'hub-creator-links' }, creatorLinks.map(function (u) {
            var label = u.replace(/^https?:\/\//, '').replace(/\/$/, '');
            if (label.length > 42) label = label.slice(0, 40) + '…';
            return el('a', { href: u, target: '_blank', rel: 'noopener nofollow' }, '🔗 ' + label);
          }))
        : null;

      mount.replaceChildren(el('div', null, [
        el('a', { class: 'hub-back', href: '#/' }, '← Back to browsing'),
        el('div', { class: 'hub-creator-head' }, [
          el('h2', null, cr.displayName),
          followers,
          statLine,
          followBtn,
          shareBtn('creator', creatorRef(cr)),
        ]),
        bioBlock,
        linkList,
        cards.length
          ? el('div', { class: 'hub-grid' }, cards.map(ui.cardTile))
          : ui.emptyState('🪑', 'No public cards yet'),
      ]));
    }).catch(function (e) {
      mount.replaceChildren(ui.emptyState('🌫️', 'Couldn’t load that creator', e.message));
    });
  }

  window.Stoop.viewsBrowse = {
    renderBrowse: function (m) { el = S.ui.el; ui = S.ui; Api = S.api; renderBrowse(m); },
    renderCard: function (m, id) { el = S.ui.el; ui = S.ui; Api = S.api; renderCard(m, id); },
    renderCreator: function (m, id) { el = S.ui.el; ui = S.ui; Api = S.api; renderCreator(m, id); },
  };
})();
