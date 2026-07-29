/* frontporchai.app — tiny enhancements. No frameworks, no tracking. */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---- fireflies ---------------------------------------------------- */
  var flies = document.querySelector('.flies');
  if (flies && !reduced) {
    var n = window.innerWidth < 700 ? 8 : 15;
    for (var i = 0; i < n; i++) {
      var f = document.createElement('span');
      f.className = 'fly';
      f.style.left = Math.random() * 100 + 'vw';
      f.style.top = 8 + Math.random() * 84 + 'vh';
      f.style.setProperty('--dx', (Math.random() * 160 - 80).toFixed(0) + 'px');
      f.style.setProperty('--dy', (Math.random() * -140 - 20).toFixed(0) + 'px');
      f.style.setProperty('--dur', (16 + Math.random() * 18).toFixed(1) + 's');
      f.style.setProperty('--delay', (-Math.random() * 20).toFixed(1) + 's');
      f.style.setProperty('--peak', (0.35 + Math.random() * 0.55).toFixed(2));
      flies.appendChild(f);
    }
  }

  /* ---- docs sidebar: start collapsed on phones ------------------------ */
  var sideDetails = document.querySelector('.side details');
  if (sideDetails && window.innerWidth <= 880) sideDetails.removeAttribute('open');

  /* ---- mobile nav ---------------------------------------------------- */
  var toggle = document.querySelector('.nav-toggle');
  var links = document.querySelector('nav .links');
  if (toggle && links) {
    toggle.addEventListener('click', function () {
      links.classList.toggle('open');
    });
  }

  /* ---- mark Docs nav item active on docs pages ----------------------- */
  if (location.pathname.indexOf('/docs/') === 0) {
    var d = document.querySelector('nav a[data-nav="docs"]');
    if (d) d.classList.add('active');
  }

  /* ---- scroll reveal -------------------------------------------------- */
  var reveals = document.querySelectorAll('.reveal');
  if (reveals.length && 'IntersectionObserver' in window && !reduced) {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add('in');
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('in'); });
  }

  /* ---- keep the release version fresh (landing page) ------------------ */
  var verEl = document.getElementById('stable-ver');
  var bannerEl = document.getElementById('latest-banner');
  if (verEl || bannerEl) {
    fetch('https://api.github.com/repos/linux4life1/front-porch-AI/releases/latest')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (rel) {
        if (!rel || !rel.tag_name) return;
        if (verEl) verEl.textContent = rel.tag_name;
        if (bannerEl) bannerEl.textContent = '🎉 New release: ' + (rel.name || rel.tag_name);
      })
      .catch(function () { /* offline or rate-limited — the baked-in version stands */ });
  }

  /* ---- OS hint in the download section -------------------------------- */
  var hint = document.getElementById('os-hint');
  if (hint) {
    var ua = navigator.userAgent;
    var msg = '';
    if (/Windows/i.test(ua)) msg = 'Looks like you’re on Windows — grab the .exe installer.';
    else if (/Macintosh|Mac OS X/i.test(ua)) msg = 'Looks like you’re on a Mac — grab the .pkg installer (signed & Apple-notarized, no Gatekeeper warnings).';
    else if (/Linux/i.test(ua) && !/Android/i.test(ua)) msg = '🐧 On Linux? The one-line install below is the easy way.';
    if (msg) {
      hint.textContent = msg;
      hint.classList.add('show');
    }
  }

  /* ---- code copy buttons (docs pages) ---------------------------------- */
  document.querySelectorAll('.codeblock .copy').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var code = btn.parentElement.querySelector('code');
      if (!code) return;
      navigator.clipboard.writeText(code.innerText).then(function () {
        btn.textContent = 'copied!';
        btn.classList.add('ok');
        setTimeout(function () {
          btn.textContent = 'copy';
          btn.classList.remove('ok');
        }, 1600);
      });
    });
  });

  /* ---- "on this page" active-section highlight ------------------------- */
  var toc = document.querySelector('.toc');
  if (toc && 'IntersectionObserver' in window) {
    var map = {};
    var tocLinks = toc.querySelectorAll('a[href^="#"]');
    tocLinks.forEach(function (a) { map[a.getAttribute('href').slice(1)] = a; });
    var current = null;
    var hio = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting && map[e.target.id]) {
            if (current) current.classList.remove('active');
            current = map[e.target.id];
            current.classList.add('active');
          }
        });
      },
      { rootMargin: '-60px 0px -70% 0px' }
    );
    Object.keys(map).forEach(function (id) {
      var h = document.getElementById(id);
      if (h) hio.observe(h);
    });
  }
})();
