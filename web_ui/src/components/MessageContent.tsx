// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders chat message text with:
//  - inline markdown images (![alt](url)) shown as actual images (parity with
//    the desktop's ExternalImageWidget), and
//  - RP text coloring (parity with the desktop AppColors): "quoted dialogue" →
//    amber, *actions* → italic blue, **emphasis** → bold blue. The coloring
//    itself lives in the shared renderRpInline (also used by the composer).
// No HTML injection — only image src/alt are extracted, and the colored spans
// carry plain text content, never markup.

import { memo } from 'react';
import { renderRpInline } from './rpText';

const IMAGE_RE = /!\[([^\]]*)\]\(([^)\s]+)\)/g;

// Memoised: the chat refreshes its whole state on every WS event (token / done /
// chat_updated / realism processing), which re-renders the message list. Skipping
// re-render for messages whose text is unchanged stops the transcript re-parsing
// every bubble (and prevents inline <img> from flashing/refetching) on each tick.
function MessageContentImpl({ text }: { text: string }) {
  const parts: React.ReactNode[] = [];
  let last = 0;
  let seg = 0;
  let match: RegExpExecArray | null;
  IMAGE_RE.lastIndex = 0;
  while ((match = IMAGE_RE.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(...renderRpInline(text.slice(last, match.index), `t${seg++}`));
    }
    const alt = match[1] || 'image';
    const url = match[2];
    parts.push(
      <img key={`img-${match.index}-${url}`} className="chat-image" src={url} alt={alt} loading="lazy" />,
    );
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(...renderRpInline(text.slice(last), `t${seg++}`));

  return (
    <>
      {parts.map((p, i) => (typeof p === 'string' ? <span key={`s${i}`}>{p}</span> : p))}
    </>
  );
}

export const MessageContent = memo(MessageContentImpl);
