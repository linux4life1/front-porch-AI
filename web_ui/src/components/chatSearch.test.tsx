// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// ⌘F marks paint the server's ranges. The ranges here stand in for what
// the Dart engine sends: one pass of the pattern over the WHOLE message
// text, so they cross colored runs and stripped `*` markers like real hits.

import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { MessageContent } from './MessageContent';
import type { FindRange, FindSurface } from './chatSearch';

const BODY = 'Rain falls. *He lifts the lantern.* "Storm\'s coming," he says. The lantern sways.';

function engineRanges(text: string, pattern: string): FindRange[] {
  return [...text.matchAll(new RegExp(pattern, 'gu'))].map((m) => [m.index!, m.index! + m[0].length]);
}

function marks(pattern: string, active = 0) {
  const body = engineRanges(BODY, pattern);
  const find: FindSurface = {
    byMessage: new Map([[3, { body, sender: [] }]]),
    active: { messageIndex: 3, region: 'body', start: body[active][0] },
  };
  const html = renderToStaticMarkup(<MessageContent text={BODY} find={find} msgIndex={3} />);
  return [...html.matchAll(/<mark class="([^"]+)">([^<]*)<\/mark>/g)].map((m) => ({
    active: m[1].includes('active'),
    text: m[2].replace(/&quot;/g, '"').replace(/&#x27;/g, "'"),
  }));
}

describe('find marks paint the engine ranges', () => {
  it('an anchored pattern lights one hit, not the start of every run', () => {
    expect(marks('^.')).toEqual([{ active: true, text: 'R' }]);
  });

  it('a hit crossing from action into dialogue is lit end to end', () => {
    const lit = marks('lantern.*Storm');
    expect(lit.map((m) => m.text).join('')).toBe('lantern. "Storm');
    expect(lit.every((m) => m.active)).toBe(true);
  });

  it('the active mark is the hit the server selected', () => {
    expect(marks('lantern', 1).map((m) => m.active)).toEqual([false, true]);
  });

  it('a message with no hits renders no marks', () => {
    const find: FindSurface = { byMessage: new Map(), active: null };
    const html = renderToStaticMarkup(<MessageContent text={BODY} find={find} msgIndex={3} />);
    expect(html).not.toContain('<mark');
  });
});
