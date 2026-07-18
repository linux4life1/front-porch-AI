/* The Stoop hub — "My cards" (uploads + status + downloads) and Submit.
   Submitting from the browser starts from a card FILE (the PNG or JSON your
   app exports): we read the embedded 'chara' / 'fpa_group' data client-side,
   prefill the form, and ship the same multipart payload the desktop app sends. */
(function () {
  'use strict';
  var S = window.Stoop;
  var el, ui, Api;

  var STATUS_META = {
    PENDING: { label: 'Pending review', cls: 'pending' },
    APPROVED: { label: 'Live on The Stoop', cls: 'approved' },
    REJECTED: { label: 'Not approved', cls: 'rejected' },
    TAKEN_DOWN: { label: 'Taken down', cls: 'rejected' },
  };

  /* ================================ my cards ================================ */
  function renderMine(mount) {
    mount.replaceChildren(ui.spinner());
    Promise.all([Api.myCharacters(), Api.myDownloads().catch(function () { return { items: [] }; })])
      .then(function (res) {
        var mine = res[0].items || [];
        var downloads = res[1].items || [];

        var uploadRows = mine.map(function (ch) {
          var meta = STATUS_META[ch.status] || { label: ch.status, cls: 'pending' };
          return el('div', { class: 'hub-mycard' }, [
            ui.avatarImg(ch.primaryAssetId, ch.name, 'hub-mycard-img'),
            el('div', { class: 'hub-mycard-info' }, [
              el('div', { class: 'hub-mycard-head' }, [
                el('b', null, ch.name),
                ch.type === 'GROUP' ? el('span', { class: 'hub-badge hub-badge-group' }, '👥') : null,
                ch.nsfw ? el('span', { class: 'hub-badge hub-badge-nsfw' }, '18+') : null,
                el('span', { class: 'hub-status ' + meta.cls }, meta.label),
              ]),
              el('p', { class: 'hub-dim' }, ch.summary || ''),
              ch.rejectionNote ? el('p', { class: 'hub-reject-note' }, ['Moderator note: ', ch.rejectionNote]) : null,
              el('p', { class: 'hub-dim hub-small' }, 'v' + (ch.version || 1) + ' · ' + ui.num(ch.downloadCount) + ' downloads'),
            ]),
            el('div', { class: 'hub-mycard-actions' }, [
              ch.status === 'APPROVED' ? el('a', { class: 'hub-linklike', href: '#/card/' + ch.id }, 'View') : null,
              el('button', {
                class: 'hub-linklike', type: 'button',
                onclick: function () { location.hash = '#/submit/' + ch.id; },
              }, 'Update'),
              el('button', {
                class: 'hub-linklike danger', type: 'button',
                onclick: function () {
                  ui.confirmDialog('Remove “' + ch.name + '”?',
                    'This takes the card off The Stoop for everyone. Copies people already downloaded stay with them.',
                    'Remove card',
                    function () {
                      Api.deleteCharacter(ch.id)
                        .then(function () { ui.toast('Card removed.'); renderMine(mount); })
                        .catch(function (e) { ui.toast(e.message, 'err'); });
                    }, true);
                },
              }, 'Delete'),
            ]),
          ]);
        });

        mount.replaceChildren(el('div', null, [
          el('div', { class: 'hub-head-row' }, [
            el('h2', null, 'My cards'),
            el('a', { class: 'btn btn-amber', href: '#/submit' }, '+ Share a card'),
          ]),
          mine.length ? el('div', { class: 'hub-mylist' }, uploadRows)
            : ui.emptyState('🎴', 'Nothing shared yet', 'Share a character or group card and it shows up here with its review status.'),
          el('h2', { class: 'hub-h2-space' }, 'My downloads'),
          downloads.length
            ? el('div', { class: 'hub-grid' }, downloads.map(ui.cardTile))
            : el('p', { class: 'hub-dim' }, 'Cards you download show up here for easy re-downloading.'),
        ]));
      })
      .catch(function (e) { mount.replaceChildren(ui.emptyState('🌫️', 'Couldn’t load your cards', e.message)); });
  }

  /* ================================= submit ================================= */
  function renderSubmit(mount, updateId) {
    var parsed = null; // { type, card, pngBytes }
    var avatarOverride = null; // File (required for .json uploads)

    var nameIn = el('input', { type: 'text', maxlength: '80', placeholder: 'Card name' });
    var summaryIn = el('textarea', { class: 'hub-textarea', rows: '2', maxlength: '280', placeholder: 'One or two lines that sell the character (required)' });
    var tagsIn = el('input', { type: 'text', placeholder: 'Comma-separated tags, e.g. fantasy, slow-burn' });
    var creatorIn = el('input', { type: 'text', maxlength: '120', placeholder: 'Leave blank if this is your own work' });
    var nsfwIn = el('input', { type: 'checkbox' });
    var changelogIn = el('textarea', { class: 'hub-textarea', rows: '2', maxlength: '500', placeholder: updateId ? 'What changed in this version?' : 'Anything reviewers should know? (optional)' });
    var errBox = el('p', { class: 'hub-form-err', role: 'alert' });
    var fileInfo = el('p', { class: 'hub-dim' }, 'No card loaded yet.');
    var preview = el('div', { class: 'hub-submit-preview' });
    var avatarRow = el('div', { class: 'hub-hidden' });

    var fileIn = el('input', { type: 'file', accept: '.png,.json', class: 'hub-hidden' });
    var avatarIn = el('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', class: 'hub-hidden' });

    var submitBtn = el('button', { class: 'btn btn-amber', type: 'button', disabled: true, onclick: doSubmit },
      updateId ? 'Publish new version' : 'Submit for review');

    function setError(msg) { errBox.textContent = msg || ''; }

    fileIn.addEventListener('change', function () {
      var f = fileIn.files && fileIn.files[0];
      if (!f) return;
      setError('');
      S.png.parseCardFile(f).then(function (res) {
        parsed = res;
        var card = res.card || {};
        if (!nameIn.value) nameIn.value = card.name || '';
        // Card files often carry the author in their V2 `creator` field —
        // prefill the credit when it isn't the signed-in user's own handle.
        var embedded = typeof card.creator === 'string' ? card.creator.trim() : '';
        var myName = (Api.state.user && Api.state.user.displayName) || '';
        if (!creatorIn.value && embedded && embedded.toLowerCase() !== myName.toLowerCase()) {
          creatorIn.value = embedded;
        }
        fileInfo.textContent = f.name + ' · ' + (res.type === 'GROUP' ? 'Group cast ('
          + ((card.raw_member_data || card.members || []).length) + ' members)' : 'Solo character');
        preview.replaceChildren();
        if (res.pngBytes) {
          var img = el('img', { class: 'hub-submit-img', alt: 'Card art' });
          img.src = URL.createObjectURL(new Blob([res.pngBytes], { type: 'image/png' }));
          preview.appendChild(img);
          avatarRow.classList.add('hub-hidden');
          avatarOverride = null;
        } else {
          avatarRow.classList.remove('hub-hidden'); // JSON card → needs separate art
        }
        submitBtn.disabled = false;
      }).catch(function (e) {
        parsed = null;
        submitBtn.disabled = true;
        setError(e.message);
      });
    });

    avatarIn.addEventListener('change', function () {
      avatarOverride = (avatarIn.files && avatarIn.files[0]) || null;
      preview.replaceChildren();
      if (avatarOverride) {
        var img = el('img', { class: 'hub-submit-img', alt: 'Card art' });
        img.src = URL.createObjectURL(avatarOverride);
        preview.appendChild(img);
      }
    });

    function doSubmit() {
      if (!parsed) return setError('Load a card file first.');
      var name = nameIn.value.trim();
      var summary = summaryIn.value.trim();
      if (!name) return setError('Give the card a name.');
      if (!summary) return setError('Write a short summary — it’s what people see while browsing.');
      var avatarBlob = avatarOverride
        || (parsed.pngBytes ? new Blob([parsed.pngBytes], { type: 'image/png' }) : null);
      if (!avatarBlob) return setError('Add card art (PNG, JPEG, or WebP).');
      var tags = tagsIn.value.split(',').map(function (t) { return t.trim().toLowerCase(); })
        .filter(Boolean).slice(0, 20);
      var payload = {
        name: name,
        summary: summary,
        type: parsed.type,
        nsfw: nsfwIn.checked,
        tags: tags,
        card: parsed.card,
        changelog: changelogIn.value.trim() || (updateId ? 'Updated' : 'Initial upload'),
        // Attribution ('' = own work; on update, '' clears an old credit).
        originalCreator: creatorIn.value.trim(),
      };
      setError('');
      submitBtn.disabled = true;
      submitBtn.textContent = 'Sending to the porch…';
      var call = updateId
        ? Api.uploadVersion(updateId, payload, avatarBlob, 'avatar.png')
        : Api.uploadCharacter(payload, avatarBlob, 'avatar.png');
      call.then(function () {
        mount.replaceChildren(el('div', { class: 'hub-submitted' }, [
          el('div', { class: 'hub-empty-ico' }, '🏡'),
          el('h2', null, 'It’s on the porch!'),
          el('p', { class: 'hub-dim' }, 'Every card is reviewed by a moderator before it goes public. You’ll get a notification here (and in the app) once it’s approved — or a note explaining what needs a tweak.'),
          el('div', { class: 'hub-gate-actions' }, [
            el('a', { class: 'btn btn-ghost', href: '#/mine' }, 'My cards'),
            el('a', { class: 'btn btn-amber', href: '#/' }, 'Keep browsing'),
          ]),
        ]));
      }).catch(function (e) {
        submitBtn.disabled = false;
        submitBtn.textContent = updateId ? 'Publish new version' : 'Submit for review';
        setError(e.message);
      });
    }

    avatarRow.appendChild(el('div', { class: 'hub-filebtn-row' }, [
      el('button', { class: 'btn btn-ghost', type: 'button', onclick: function () { avatarIn.click(); } }, 'Choose card art…'),
      el('span', { class: 'hub-dim hub-small' }, 'JSON cards need a separate image (non-pornographic — see the AUP).'),
    ]));

    mount.replaceChildren(el('div', { class: 'hub-submit' }, [
      el('a', { class: 'hub-back', href: '#/mine' }, '← My cards'),
      el('h2', null, updateId ? 'Update your card' : 'Share a card on The Stoop'),
      el('p', { class: 'hub-dim' }, [
        'Start from a card file: a character PNG (V2 “chara” cards from Front Porch AI, SillyTavern, and friends), a Front Porch ',
        el('code', null, '.group.png'),
        ' group card, or a raw JSON card. Everything is reviewed before it goes public — the ',
        el('a', { href: '#', onclick: function (e) { e.preventDefault(); S.viewsAuth.showPolicyDialog(); } }, 'content standards'),
        ' apply.',
      ]),
      el('div', { class: 'hub-dropzone', onclick: function () { fileIn.click(); },
        ondragover: function (e) { e.preventDefault(); e.currentTarget.classList.add('over'); },
        ondragleave: function (e) { e.currentTarget.classList.remove('over'); },
        ondrop: function (e) {
          e.preventDefault();
          e.currentTarget.classList.remove('over');
          if (e.dataTransfer.files && e.dataTransfer.files[0]) {
            fileIn.files = e.dataTransfer.files;
            fileIn.dispatchEvent(new Event('change'));
          }
        },
      }, [el('span', { class: 'hub-drop-ico' }, '🎴'), el('span', null, 'Drop a card file here, or click to choose'), fileInfo]),
      fileIn, avatarIn, avatarRow, preview,
      el('div', { class: 'hub-form' }, [
        el('label', { class: 'hub-field' }, [el('span', null, 'Name'), nameIn]),
        el('label', { class: 'hub-field' }, [el('span', null, 'Summary'), summaryIn]),
        el('label', { class: 'hub-field' }, [el('span', null, 'Tags'), tagsIn]),
        el('label', { class: 'hub-field' }, [
          el('span', null, 'Original creator (optional)'),
          creatorIn,
          el('span', { class: 'hub-dim hub-small' },
            'Sharing someone else\u2019s character? Credit them here \u2014 the card will show \u201ccreated by \u2026\u201d. The AUP requires this for reposts.'),
        ]),
        el('label', { class: 'hub-aup-check' }, [nsfwIn, el('span', null, 'This card is NSFW (mislabeling is an AUP violation)')]),
        el('label', { class: 'hub-field' }, [el('span', null, updateId ? 'Changelog' : 'Note to reviewers'), changelogIn]),
        errBox,
        submitBtn,
      ]),
    ]));

    // Update mode: pull the post's current credit so re-publishing keeps it
    // unless the field is deliberately cleared.
    if (updateId) {
      Api.cardDetail(updateId).then(function (d) {
        if (!creatorIn.value && d && d.originalCreator) creatorIn.value = d.originalCreator;
      }).catch(function () { /* prefill only — the form still works without it */ });
    }
  }

  window.Stoop.viewsMy = {
    renderMine: function (m) { el = S.ui.el; ui = S.ui; Api = S.api; renderMine(m); },
    renderSubmit: function (m, updateId) { el = S.ui.el; ui = S.ui; Api = S.api; renderSubmit(m, updateId); },
  };
})();
