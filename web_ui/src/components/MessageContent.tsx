// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders chat message text with:
//  - inline markdown images (![alt](url)) shown as actual images (parity with
//    the desktop's ExternalImageWidget), and
//  - RP text coloring (parity with the desktop AppColors): "quoted dialogue" →
//    amber, *actions* → italic blue, **emphasis** → bold blue.
// No HTML injection — only image src/alt are extracted, and the colored spans
// carry plain text content, never markup.

const IMAGE_RE = /!\[([^\]]*)\]\(([^)\s]+)\)/g;
// Order matters: **bold** before *action* so the double-star wins. Dialogue
// matches both straight "…" and curly “…” quotes (cards/LLMs often use curly).
const INLINE_RE = /(\*\*[^*\n]+\*\*)|(\*[^*\n]+\*)|("[^"\n]+"|“[^”\n]+”)/g;

// Color quoted dialogue / *action* / **emphasis** inside a plain text segment.
function renderInline(text: string, keyBase: string): React.ReactNode[] {
  const out: React.ReactNode[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  INLINE_RE.lastIndex = 0;
  while ((m = INLINE_RE.exec(text)) !== null) {
    if (m.index > last) out.push(text.slice(last, m.index));
    const key = `${keyBase}-${m.index}`;
    if (m[1]) {
      out.push(<span key={key} className="act bold">{m[1].slice(2, -2)}</span>);
    } else if (m[2]) {
      out.push(<span key={key} className="act">{m[2].slice(1, -1)}</span>);
    } else {
      out.push(<span key={key} className="dlg">{m[3]}</span>);
    }
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function MessageContent({ text }: { text: string }) {
  const parts: React.ReactNode[] = [];
  let last = 0;
  let seg = 0;
  let match: RegExpExecArray | null;
  IMAGE_RE.lastIndex = 0;
  while ((match = IMAGE_RE.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(...renderInline(text.slice(last, match.index), `t${seg++}`));
    }
    const alt = match[1] || 'image';
    const url = match[2];
    parts.push(
      <img key={`img-${match.index}-${url}`} className="chat-image" src={url} alt={alt} loading="lazy" />,
    );
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(...renderInline(text.slice(last), `t${seg++}`));

  return (
    <>
      {parts.map((p, i) => (typeof p === 'string' ? <span key={`s${i}`}>{p}</span> : p))}
    </>
  );
}
