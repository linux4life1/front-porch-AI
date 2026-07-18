#!/usr/bin/env node
/**
 * frontporchai.app static site generator.
 * Reads the canonical markdown docs from ../docs/*.md, renders them into the
 * site shell, and emits a fully static site into dist/.
 *
 *   node build.mjs          → build into dist/
 *
 * No framework, one dependency (marked). The docs stay plain markdown in the
 * repo (GitHub renders them fine); this script is the only thing that knows
 * how to turn them into frontporchai.app.
 */
import { marked } from 'marked';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(ROOT, '..');
const DOCS_DIR = path.join(REPO, 'docs');
const SRC = path.join(ROOT, 'src');
const DIST = path.join(ROOT, 'dist');
// The Stoop hub is a separate origin (its own Caddy site block), so it builds
// into its own self-contained tree: rsync dist-hub/ → the hub's web root.
const DIST_HUB = path.join(ROOT, 'dist-hub');

const SITE = 'https://frontporchai.app';
const HUB = 'https://hub.frontporchai.app';

// Cache-buster: Caddy serves /assets with a 7-day max-age, so every css/js URL
// carries a short content hash — the URL changes exactly when the file's bytes
// change, and a plain page load picks up new code immediately after a deploy.
const stampCache = new Map();
function stamp(file) {
  if (!stampCache.has(file)) {
    stampCache.set(file, createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 8));
  }
  return stampCache.get(file);
}
const STABLE_VERSION = 'v0.9.9.1.3';

/** The docs that make up the site, in reading order. */
const DOCS = [
  { slug: 'getting-started', file: 'getting-started.md', title: 'Getting Started', group: 'Start Here', desc: 'From download to your first chat' },
  { slug: 'install', file: 'install.md', title: 'Installation', group: 'Start Here', desc: 'Windows, macOS, and Linux' },
  { slug: 'user-guide', file: 'user-guide.md', title: 'User Guide', group: 'Using the App', desc: 'The complete reference' },
  { slug: 'characters', file: 'characters.md', title: 'Characters', group: 'Using the App', desc: 'Create, import & organize' },
  { slug: 'realism-engine', file: 'realism-engine.md', title: 'Realism Engine', group: 'Using the App', desc: 'Living, feeling characters' },
  { slug: 'faq', file: 'faq.md', title: 'FAQ', group: 'Help', desc: 'Quick answers' },
  { slug: 'troubleshooting', file: 'troubleshooting.md', title: 'Troubleshooting', group: 'Help', desc: 'When something goes wrong' },
  { slug: 'keyboard-shortcuts', file: 'keyboard-shortcuts.md', title: 'Keyboard Shortcuts', group: 'Reference', desc: 'Work faster' },
  { slug: 'release-notes', file: 'release-notes.md', title: 'Release Notes', group: 'Reference', desc: 'What shipped, when' },
];
const MD_TO_SLUG = Object.fromEntries(DOCS.map((d) => [d.file, d.slug]));

/* ---------------------------------------------------------------- utils */

const read = (p) => fs.readFileSync(p, 'utf8');
const out = (rel, html, base = DIST) => {
  const p = path.join(base, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, html);
};
const esc = (s) =>
  s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/** Decode the HTML entities marked leaves in rendered inline text. */
const decodeEntities = (s) =>
  s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"');

/** GitHub-compatible heading slugs (matches github-slugger: strip punctuation,
 *  then EACH space becomes a hyphen — runs are not collapsed). */
function slugify(text, seen) {
  let s = decodeEntities(text.replace(/<[^>]+>/g, ''))
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N} _-]/gu, '')
    .replace(/ /g, '-');
  if (seen.has(s)) {
    let n = 1;
    while (seen.has(`${s}-${n}`)) n++;
    s = `${s}-${n}`;
  }
  seen.add(s);
  return s;
}

const stripHtml = (s) => s.replace(/<[^>]+>/g, '');

/* ------------------------------------------------------- markdown setup */

/** Build a marked instance for a given doc page. Collects headings + links. */
function renderMarkdown(md, { collectHeadings, collectLinks }) {
  const seen = new Set();
  const renderer = {
    heading(text, level) {
      const id = slugify(stripHtml(text), seen);
      if (collectHeadings && (level === 2 || level === 3)) {
        collectHeadings.push({ id, level, text: decodeEntities(stripHtml(text)) });
      }
      if (level === 1) return `<h1 id="${id}">${text}</h1>\n`;
      return `<h${level} id="${id}"><a class="hlink" href="#${id}">${text}</a></h${level}>\n`;
    },
    link(href, title, text) {
      let h = href ?? '';
      // rewrite intra-doc markdown links → site urls
      const m = h.match(/^(?:\.\/)?([\w-]+\.md)(#.*)?$/);
      if (m && MD_TO_SLUG[m[1]]) h = `/docs/${MD_TO_SLUG[m[1]]}/${m[2] ?? ''}`;
      if (collectLinks) collectLinks.push(h);
      const t = title ? ` title="${esc(title)}"` : '';
      const ext = /^https?:\/\//.test(h) ? ' target="_blank" rel="noopener"' : '';
      return `<a href="${h}"${t}${ext}>${text}</a>`;
    },
    image(href, title, text) {
      let h = href ?? '';
      // docs reference screenshots/x.png (or the old broken ../screenshots/) —
      // the site serves recompressed jpegs from /screenshots/
      const m = h.match(/^(?:\.\.\/)?screenshots\/(.+)\.(png|jpg|jpeg)$/i);
      if (m) h = `/screenshots/${m[1]}.jpg`;
      return `<img src="${h}" alt="${esc(text || '')}" loading="lazy">`;
    },
    code(code, lang) {
      return (
        `<div class="codeblock"><button class="copy" type="button" aria-label="Copy code">copy</button>` +
        `<pre><code${lang ? ` class="lang-${esc(lang)}"` : ''}>${esc(code)}</code></pre></div>\n`
      );
    },
    table(header, body) {
      return `<div class="table-scroll"><table><thead>${header}</thead><tbody>${body}</tbody></table></div>\n`;
    },
    blockquote(quote) {
      // classify callouts by their opening bold word
      const m = quote.match(/^\s*<p>(?:<strong>)?\s*(?:[^\w<]*)?\s*<strong>?\s*([A-Za-z][A-Za-z' -]{0,24})/);
      const key = (m?.[1] ?? '').toLowerCase();
      let cls = 'callout';
      if (/tip|pro tip|hint/.test(key)) cls += ' callout-tip';
      else if (/warn|caution|danger|careful|heads/.test(key)) cls += ' callout-warn';
      else if (/beta|nightly|privacy|new/.test(key)) cls += ' callout-info';
      return `<blockquote class="${cls}">\n${quote}</blockquote>\n`;
    },
  };
  marked.use({ renderer, mangle: false, headerIds: false });
  return marked.parse(md);
}

/* ------------------------------------------------------------ templates */

const NAV = `
<div class="nav-wrap"><nav>
  <a href="/" class="logo"><img src="/assets/images/front_porch_ai_icon.png" alt="">Front Porch AI</a>
  <button class="nav-toggle" type="button" aria-label="Menu">☰</button>
  <div class="links">
    <a href="/docs/getting-started/" data-nav="docs">Docs</a>
    <a href="${HUB}/" data-nav="stoop">The Stoop</a>
    <a href="https://github.com/linux4life1/front-porch-AI" target="_blank" rel="noopener">GitHub</a>
    <a href="https://discord.gg/e4tET6rpdv" target="_blank" rel="noopener">Discord</a>
    <a href="/#get" class="cta">Download</a>
  </div>
</nav></div>`;

const FOOTER = `
<footer>
  <div class="cols">
    <div class="brand"><img src="/assets/images/front_porch_ai_icon.png" alt="">Front Porch AI</div>
    <div class="links">
      <a href="/docs/getting-started/">Docs</a>
      <a href="https://github.com/linux4life1/front-porch-AI" target="_blank" rel="noopener">GitHub</a>
      <a href="https://github.com/linux4life1/front-porch-AI/releases" target="_blank" rel="noopener">Releases</a>
      <a href="https://discord.gg/e4tET6rpdv" target="_blank" rel="noopener">Discord</a>
      <a href="/privacy.html">Privacy</a>
    </div>
  </div>
  <p class="fine">Free &amp; open source under <a href="https://github.com/linux4life1/front-porch-AI/blob/main/LICENSE" target="_blank" rel="noopener">AGPL-3.0</a>.
  Your characters, your chats, your machine — nothing leaves it unless you say so.</p>
</footer>`;

function shell({ title, desc, canonical, body, extraHead = '', bodyClass = '', nav = NAV, footer = FOOTER, origin = SITE }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${canonical}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:type" content="website">
<meta property="og:url" content="${canonical}">
<meta property="og:image" content="${origin}/assets/images/front_porch_ai_icon.png">
<link rel="icon" type="image/png" href="/assets/images/front_porch_ai_icon.png">
<link rel="apple-touch-icon" href="/assets/images/front_porch_ai_icon.png">
<link rel="stylesheet" href="/assets/site.css?v=${stamp(path.join(SRC, 'site.css'))}">
${extraHead}
</head>
<body${bodyClass ? ` class="${bodyClass}"` : ''}>
<div class="sky"></div><div class="flies" aria-hidden="true"></div>
${nav}
${body}
${footer}
<script src="/assets/main.js?v=${stamp(path.join(SRC, 'main.js'))}" defer></script>
</body>
</html>`;
}

/* ----------------------------------------------------------- docs pages */

function sidebar(current) {
  const groups = [];
  for (const d of DOCS) {
    let g = groups.find((x) => x.name === d.group);
    if (!g) groups.push((g = { name: d.group, items: [] }));
    g.items.push(d);
  }
  const inner = groups
    .map(
      (g) => `<div class="group"><div class="group-name">${g.name}</div>${g.items
        .map((d) => `<a href="/docs/${d.slug}/"${d.slug === current ? ' class="current"' : ''}>${d.title}</a>`)
        .join('')}</div>`,
    )
    .join('');
  return `<aside class="side"><details open><summary>Documentation</summary>${inner}</details></aside>`;
}

function tocHtml(headings) {
  if (headings.length < 2) return '<div class="toc"></div>';
  return `<aside class="toc"><div class="toc-title">On this page</div>${headings
    .slice(0, 40)
    .map((h) => `<a href="#${h.id}" class="${h.level === 3 ? 'h3' : 'h2'}">${esc(h.text)}</a>`)
    .join('')}</aside>`;
}

function pager(idx) {
  const prev = DOCS[idx - 1];
  const next = DOCS[idx + 1];
  if (!prev && !next) return '';
  return `<div class="pager">${
    prev ? `<a href="/docs/${prev.slug}/"><small>← Previous</small>${prev.title}</a>` : '<span></span>'
  }${next ? `<a class="next" href="/docs/${next.slug}/"><small>Next →</small>${next.title}</a>` : ''}</div>`;
}

function buildDocs() {
  const anchorsBySlug = {};
  const pendingLinks = [];

  DOCS.forEach((doc, idx) => {
    let md = read(path.join(DOCS_DIR, doc.file));
    // Drop the doc's own "Table of Contents" section on the website — the
    // right-hand "On this page" rail replaces it. (It stays in the markdown
    // so GitHub readers still get navigation.)
    md = md
      .replace(/^#{2,3}[^\S\n]*(?:[^\w\n]*\s)?Table of Contents[^\n]*\n[\s\S]*?(?=^#{1,3}[^\S\n]|^---$)/im, '')
      // collapse the doubled separator the TOC removal can leave behind
      .replace(/^---[^\S\n]*\n(?:\s*\n)*---[^\S\n]*$/m, '---');
    const headings = [];
    const links = [];
    const article = renderMarkdown(md, { collectHeadings: headings, collectLinks: links });

    // record anchors + internal links for the validation pass
    const ids = new Set([...article.matchAll(/ id="([^"]+)"/g)].map((m) => m[1]));
    anchorsBySlug[doc.slug] = ids;
    links
      .filter((h) => h.startsWith('/docs/') || h.startsWith('#'))
      .forEach((h) => pendingLinks.push({ from: doc.slug, href: h }));

    const body = `
<div class="docs-layout">
  ${sidebar(doc.slug)}
  <main class="doc">
    <div class="doc-head"><div class="crumb"><a href="/">Home</a> / <a href="/docs/getting-started/">Docs</a> / ${doc.title}</div></div>
    <article class="prose">${article}</article>
    ${pager(idx)}
  </main>
  ${tocHtml(headings)}
</div>`;
    out(
      `docs/${doc.slug}/index.html`,
      shell({
        title: `${doc.title} — Front Porch AI`,
        desc: `${doc.desc}. Front Porch AI documentation.`,
        canonical: `${SITE}/docs/${doc.slug}/`,
        body,
      }),
    );
  });

  // ---- link validation (fails the build on broken cross-doc anchors)
  const problems = [];
  for (const { from, href } of pendingLinks) {
    if (href.startsWith('#')) {
      if (!anchorsBySlug[from].has(href.slice(1))) problems.push(`${from}: dead same-page anchor ${href}`);
      continue;
    }
    const m = href.match(/^\/docs\/([\w-]+)\/(#(.*))?$/);
    if (!m) continue;
    const [, slug, , frag] = m;
    if (!anchorsBySlug[slug]) problems.push(`${from}: link to unknown doc /docs/${slug}/`);
    else if (frag && !anchorsBySlug[slug].has(frag)) problems.push(`${from}: dead anchor /docs/${slug}/#${frag}`);
  }
  if (problems.length) {
    console.error(`\n⚠ link check: ${problems.length} problem(s)`);
    problems.forEach((p) => console.error('  - ' + p));
  } else {
    console.log('✓ link check: all cross-doc links + anchors resolve');
  }
  return problems;
}

/* -------------------------------------------------------- landing & co. */

function buildLanding() {
  const bodyHtml = read(path.join(SRC, 'index.html')).replaceAll('{{STABLE_VERSION}}', STABLE_VERSION);
  out(
    'index.html',
    shell({
      title: 'Front Porch AI — Private AI Character Chat',
      desc: 'A free, open-source desktop app for AI character chat that runs entirely on your machine. Local models, a Realism Engine, voice, long-term memory, and The Stoop community hub.',
      canonical: `${SITE}/`,
      body: bodyHtml,
      bodyClass: 'landing',
    }),
  );
}

function buildPrivacy() {
  const bodyHtml = `<main class="page-plain prose">${read(path.join(SRC, 'privacy.html'))}</main>`;
  out(
    'privacy.html',
    shell({
      title: 'Privacy Policy — Front Porch AI',
      desc: 'Front Porch AI is local-first: offline use collects nothing. The optional Stoop community hub is the only feature that involves an account.',
      canonical: `${SITE}/privacy.html`,
      body: bodyHtml,
    }),
  );
}

function build404() {
  out(
    '404.html',
    shell({
      title: 'Page not found — Front Porch AI',
      desc: 'That page wandered off the porch.',
      canonical: `${SITE}/404.html`,
      body: `<main class="err"><h1>404</h1><p>That page wandered off the porch. The fireflies are looking for it.</p>
<a class="btn btn-amber" href="/">Back to the porch</a>&nbsp;&nbsp;<a class="btn btn-ghost" href="/docs/getting-started/">Read the docs</a></main>`,
    }),
  );
}

/* -------------------------------------------------- The Stoop hub (dist-hub) */

/** The hub lives on its own subdomain, so shared chrome links point back at
 *  the apex site while /assets/ stays local (the hub tree carries its own
 *  copy of every asset — no cross-origin requests for CSS/fonts). */
function absolutizeChrome(html) {
  return html.replaceAll('href="/', `href="${SITE}/`);
}

function buildHub() {
  const STOOP_SRC = path.join(SRC, 'stoop');
  const hubNav = absolutizeChrome(NAV).replace('data-nav="stoop"', 'data-nav="stoop" class="active"');
  const hubFooter = absolutizeChrome(FOOTER);
  const scripts = ['png.js', 'api.js', 'ui.js', 'views-auth.js', 'views-picks.js', 'views-browse.js', 'views-my.js', 'views-inbox.js', 'app.js'];

  // self-contained asset tree
  fs.mkdirSync(path.join(DIST_HUB, 'assets/fonts'), { recursive: true });
  fs.mkdirSync(path.join(DIST_HUB, 'assets/images'), { recursive: true });
  fs.mkdirSync(path.join(DIST_HUB, 'assets/stoop'), { recursive: true });
  fs.copyFileSync(path.join(SRC, 'site.css'), path.join(DIST_HUB, 'assets/site.css'));
  fs.copyFileSync(path.join(SRC, 'main.js'), path.join(DIST_HUB, 'assets/main.js'));
  fs.copyFileSync(path.join(STOOP_SRC, 'stoop.css'), path.join(DIST_HUB, 'assets/stoop.css'));
  for (const f of fs.readdirSync(path.join(SRC, 'fonts'))) {
    fs.copyFileSync(path.join(SRC, 'fonts', f), path.join(DIST_HUB, 'assets/fonts', f));
  }
  fs.copyFileSync(
    path.join(DOCS_DIR, 'assets/images/front_porch_ai_icon.png'),
    path.join(DIST_HUB, 'assets/images/front_porch_ai_icon.png'),
  );
  for (const s of scripts) {
    fs.copyFileSync(path.join(STOOP_SRC, s), path.join(DIST_HUB, 'assets/stoop', s));
  }

  out(
    'index.html',
    shell({
      title: 'The Stoop — Front Porch AI Community Character Hub',
      desc: 'Browse, share, vote on, and download AI character cards from The Stoop — the Front Porch AI community hub. Live in your browser, strictly 18+, one account works everywhere.',
      canonical: `${HUB}/`,
      body: read(path.join(STOOP_SRC, 'index.html')),
      bodyClass: 'stoop-hub',
      nav: hubNav,
      footer: hubFooter,
      origin: HUB,
      extraHead: [
        `<link rel="stylesheet" href="/assets/stoop.css?v=${stamp(path.join(STOOP_SRC, 'stoop.css'))}">`,
        ...scripts.map(
          (s) => `<script src="/assets/stoop/${s}?v=${stamp(path.join(STOOP_SRC, s))}" defer></script>`,
        ),
      ].join('\n'),
    }),
    DIST_HUB,
  );
  // The hub is auth-walled; keep crawlers on the marketing site.
  out('robots.txt', `User-agent: *\nDisallow: /\n`, DIST_HUB);

  // Courtesy redirect: frontporchai.app/stoop/ → the hub subdomain.
  out(
    'stoop/index.html',
    `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>The Stoop</title>
<meta http-equiv="refresh" content="0; url=${HUB}/"><link rel="canonical" href="${HUB}/">
</head><body><p>The Stoop moved to <a href="${HUB}/">${HUB.replace('https://', '')}</a>.</p></body></html>`,
  );
}

/* ------------------------------------------------------------ assets */

function copyAssets() {
  // css + js + fonts + icon
  fs.mkdirSync(path.join(DIST, 'assets/fonts'), { recursive: true });
  fs.mkdirSync(path.join(DIST, 'assets/images'), { recursive: true });
  fs.copyFileSync(path.join(SRC, 'site.css'), path.join(DIST, 'assets/site.css'));
  fs.copyFileSync(path.join(SRC, 'main.js'), path.join(DIST, 'assets/main.js'));
  for (const f of fs.readdirSync(path.join(SRC, 'fonts'))) {
    fs.copyFileSync(path.join(SRC, 'fonts', f), path.join(DIST, 'assets/fonts', f));
  }
  fs.copyFileSync(
    path.join(DOCS_DIR, 'assets/images/front_porch_ai_icon.png'),
    path.join(DIST, 'assets/images/front_porch_ai_icon.png'),
  );
}

/** Recompress the repo's PNG screenshots into web-weight JPEGs via sips (macOS). */
function convertScreenshots() {
  const srcDir = path.join(DOCS_DIR, 'screenshots');
  const outDir = path.join(DIST, 'screenshots');
  fs.mkdirSync(outDir, { recursive: true });
  const files = fs.readdirSync(srcDir).filter((f) => f.toLowerCase().endsWith('.png'));
  for (const f of files) {
    const dest = path.join(outDir, f.replace(/\.png$/i, '.jpg'));
    const srcP = path.join(srcDir, f);
    if (fs.existsSync(dest) && fs.statSync(dest).mtimeMs > fs.statSync(srcP).mtimeMs) continue;
    execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '80', '--resampleWidth', '1800', srcP, '--out', dest], { stdio: 'ignore' });
  }
  console.log(`✓ screenshots: ${files.length} converted to jpg`);
}

function buildMeta() {
  const urls = [`${SITE}/`, `${SITE}/privacy.html`, ...DOCS.map((d) => `${SITE}/docs/${d.slug}/`)];
  out(
    'sitemap.xml',
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls
      .map((u) => `  <url><loc>${u}</loc></url>`)
      .join('\n')}\n</urlset>\n`,
  );
  out('robots.txt', `User-agent: *\nAllow: /\nSitemap: ${SITE}/sitemap.xml\n`);
}

/* ---------------------------------------------------------------- main */

fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });
fs.rmSync(DIST_HUB, { recursive: true, force: true });
fs.mkdirSync(DIST_HUB, { recursive: true });

copyAssets();
convertScreenshots();
buildLanding();
buildPrivacy();
build404();
buildHub();
const problems = buildDocs();
buildMeta();

const count = fs.readdirSync(DIST, { recursive: true }).length;
const hubCount = fs.readdirSync(DIST_HUB, { recursive: true }).length;
console.log(`✓ built ${count} files → dist/ + ${hubCount} → dist-hub/`);
if (problems.length) process.exitCode = 1;
