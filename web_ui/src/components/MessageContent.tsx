// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders chat message text with inline markdown images (![alt](url)) shown as
// actual images — parity with the desktop chat's ExternalImageWidget. Plain text
// segments keep their whitespace; everything else renders verbatim (no HTML
// injection — only the image src/alt are extracted from the markdown).

const IMAGE_RE = /!\[([^\]]*)\]\(([^)\s]+)\)/g;

export function MessageContent({ text }: { text: string }) {
  if (!text.includes('![')) return <>{text}</>;

  const parts: React.ReactNode[] = [];
  let last = 0;
  let match: RegExpExecArray | null;
  IMAGE_RE.lastIndex = 0;
  while ((match = IMAGE_RE.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(text.slice(last, match.index));
    }
    const alt = match[1] || 'image';
    const url = match[2];
    parts.push(
      <img key={`${match.index}-${url}`} className="chat-image" src={url} alt={alt} loading="lazy" />,
    );
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));

  return (
    <>
      {parts.map((p, i) => (typeof p === 'string' ? <span key={i}>{p}</span> : p))}
    </>
  );
}
