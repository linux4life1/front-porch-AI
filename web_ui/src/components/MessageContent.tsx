// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders chat message text with:
//  - inline markdown images (![alt](https://...)) shown as actual images after
//    session consent (parity with the desktop ExternalImageWidget), and
//  - RP text coloring (parity with the desktop AppColors): "quoted dialogue" →
//    amber, *actions* → italic blue, **emphasis** → bold blue. The coloring
//    itself lives in the shared renderRpInline (also used by the composer).
// No HTML injection — only https?:// image src/alt are extracted, and the
// colored spans carry plain text content, never markup. img src is never set
// until the user consents (session flag).

import { memo, useEffect, useState, type ReactNode } from 'react';
import { renderRpInline } from './rpText';
import { markRanges, type FindSurface } from './chatSearch';

// Desktop only matches http(s) — data:/javascript:/relative stay as text.
const IMAGE_RE = /!\[([^\]]*)\]\((https?:\/\/[^)\s]+)\)/g;

const CONSENT_KEY = 'fpai_external_image_consent';

function readConsent(): boolean {
  try {
    return sessionStorage.getItem(CONSENT_KEY) === '1';
  } catch {
    return false;
  }
}

let sessionConsent = readConsent();
const consentListeners = new Set<() => void>();

function grantExternalImageConsent() {
  sessionConsent = true;
  try {
    sessionStorage.setItem(CONSENT_KEY, '1');
  } catch {
    /* memory flag still covers this tab */
  }
  consentListeners.forEach((l) => l());
}

function useExternalImageConsent() {
  const [allowed, setAllowed] = useState(sessionConsent);
  useEffect(() => {
    const onGrant = () => setAllowed(true);
    consentListeners.add(onGrant);
    return () => {
      consentListeners.delete(onGrant);
    };
  }, []);
  return { allowed, allow: grantExternalImageConsent };
}

/** Placeholder until session consent; never sets img src beforehand. */
function ExternalChatImage({ url, alt }: { url: string; alt: string }) {
  const { allowed, allow } = useExternalImageConsent();
  if (allowed) {
    return <img className="chat-image" src={url} alt={alt} loading="lazy" />;
  }
  const label = alt && alt !== 'image' ? ` (${alt})` : '';
  return (
    <div className="chat-image-consent">
      <span>External image{label}</span>
      <button type="button" onClick={allow}>
        Load external image?
      </button>
    </div>
  );
}

// Memoised: the chat refreshes its whole state on every WS event (token / done /
// chat_updated / realism processing), which re-renders the message list. Skipping
// re-render for messages whose text is unchanged stops the transcript re-parsing
// every bubble. ExternalChatImage owns consent state so a grant still updates
// already-mounted placeholders without busting this memo.
//
// ⌘F parity with the desktop: each colored run paints the slice of the
// server's hit ranges that falls inside it, by its offset into [text].
function MessageContentImpl({
  text,
  find,
  msgIndex,
}: {
  text: string;
  find?: FindSurface | null;
  msgIndex?: number;
}) {
  const hits = find && msgIndex != null ? find.byMessage.get(msgIndex) : undefined;
  const active = find?.active;
  const activeStart =
    active && active.messageIndex === msgIndex && active.region === 'body' ? active.start : null;
  const mark = hits?.body.length
    ? (plain: string, key: string, offset: number): ReactNode =>
        markRanges(plain, offset, hits.body, activeStart, key)
    : undefined;

  const parts: ReactNode[] = [];
  let last = 0;
  let seg = 0;
  let match: RegExpExecArray | null;
  IMAGE_RE.lastIndex = 0;
  while ((match = IMAGE_RE.exec(text)) !== null) {
    if (match.index > last) {
      parts.push(...renderRpInline(text.slice(last, match.index), `t${seg++}`, true, mark, last));
    }
    const alt = match[1] || 'image';
    const url = match[2];
    parts.push(
      <ExternalChatImage key={`img-${match.index}-${url}`} url={url} alt={alt} />,
    );
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(...renderRpInline(text.slice(last), `t${seg++}`, true, mark, last));

  return (
    <>
      {parts.map((p, i) => (typeof p === 'string' ? <span key={`s${i}`}>{p}</span> : p))}
    </>
  );
}

export const MessageContent = memo(MessageContentImpl);
