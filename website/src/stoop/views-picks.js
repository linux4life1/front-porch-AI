/* The Stoop hub — Mod's Picks showcase: the newest pick as a hero banner,
   the rest as a horizontal carousel. Rendered at the top of the default
   (solo) browse view. Curated + clearly badged; the browsing grid below it
   stays strictly one card type. */
(function () {
  'use strict';
  var S = window.Stoop;
  var el, ui, Api;

  function hero(card) {
    var dlBtn = el('button', { class: 'btn btn-amber', type: 'button' }, '⤓ Download');
    dlBtn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      ui.downloadCard(card, dlBtn);
    });

    // Blurred, darkened cover-fill of the same art backs a SHARP portrait shown
    // at its true 3:4 aspect — so portrait card art is never cropped across the
    // wide banner (mirrors the desktop app's spotlight).
    var bg = el('div', { class: 'hub-pickhero-bg' });
    var portraitImg = el('img', { class: 'hub-pickhero-portrait-img', alt: card.name, loading: 'lazy' });
    portraitImg.style.opacity = '0';
    if (card.primaryAssetId) {
      Api.avatarUrl(card.primaryAssetId).then(function (url) {
        if (!url) return;
        bg.style.backgroundImage = 'url("' + url + '")';
        portraitImg.src = url;
        portraitImg.style.opacity = '';
      });
    }

    return el('a', { class: 'hub-pickhero', href: '#/card/' + card.id }, [
      bg,
      el('div', { class: 'hub-pickhero-scrim' }),
      el('div', { class: 'hub-pickhero-inner' }, [
        el('div', { class: 'hub-pickhero-portrait' }, [portraitImg]),
        el('div', { class: 'hub-pickhero-body' }, [
          el('div', { class: 'hub-pickhero-badges' }, [
            el('span', { class: 'hub-badge hub-badge-pick' }, '★ Mod’s Pick'),
            card.type === 'GROUP' ? el('span', { class: 'hub-badge hub-badge-group' }, '👥 Group cast') : null,
            card.nsfw ? el('span', { class: 'hub-badge hub-badge-nsfw' }, '18+') : null,
          ]),
          el('h2', { class: 'hub-pickhero-name' }, card.name),
          (card.creator || card.originalCreator) ? el('div', { class: 'hub-pickhero-creator' },
            (card.creator ? 'by ' + card.creator.displayName : '')
            + (card.originalCreator ? (card.creator ? ' · ' : '') + 'created by ' + card.originalCreator : '')) : null,
          el('p', { class: 'hub-pickhero-summary' }, card.summary || ''),
          el('div', { class: 'hub-pickhero-foot' }, [
            ui.statsSpan(card),
            el('span', { class: 'hub-pickhero-cta' }, [
              el('span', { class: 'btn btn-ghost hub-pickhero-view' }, 'View card'),
              dlBtn,
            ]),
          ]),
        ]),
      ]),
    ]);
  }

  function carouselTile(card) {
    return el('a', { class: 'hub-picktile', href: '#/card/' + card.id }, [
      el('div', { class: 'hub-picktile-art' }, [ui.avatarImg(card.primaryAssetId, card.name, 'hub-picktile-img')]),
      el('div', { class: 'hub-picktile-badges' }, [
        card.type === 'GROUP' ? el('span', { class: 'hub-badge hub-badge-group' }, '👥') : null,
        card.nsfw ? el('span', { class: 'hub-badge hub-badge-nsfw' }, '18+') : null,
      ]),
      el('div', { class: 'hub-picktile-name' }, card.name),
    ]);
  }

  /** Populate `container` with the picks showcase for the given card type
      ('solo' | 'group'). Empties the container if there are no picks. */
  function renderPicksShowcase(container, type) {
    Api.browse({ pick: 'true', sort: 'newest', type: type || 'solo', take: 12 })
      .then(function (res) {
        var items = res.items || [];
        if (!items.length) { container.replaceChildren(); return; }
        var rest = items.slice(1);
        ui.mountChildren(container, [
          el('div', { class: 'hub-pick-head' }, [
            el('span', { class: 'hub-pick-eyebrow' }, '★ Mod’s Picks'),
            el('span', { class: 'hub-dim hub-small' }, 'Hand-picked by the moderators'),
          ]),
          hero(items[0]),
          rest.length
            ? el('div', { class: 'hub-pickrow' }, rest.map(carouselTile))
            : null,
        ]);
      })
      .catch(function () { container.replaceChildren(); });
  }

  window.Stoop.viewsPicks = {
    renderPicksShowcase: function (c, type) { el = S.ui.el; ui = S.ui; Api = S.api; renderPicksShowcase(c, type); },
  };
})();
