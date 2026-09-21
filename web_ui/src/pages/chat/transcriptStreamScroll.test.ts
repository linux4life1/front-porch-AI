import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { applyTranscriptAutoScroll } from './transcriptAutoScroll';

describe('transcript stream scroll (option B)', () => {
  it('does not rewrite scrollTop on a stream tick', () => {
    const el = { scrollTop: 360, scrollHeight: 800 };
    applyTranscriptAutoScroll(el, 80);
    expect(el.scrollTop).toBe(360);
  });

  it('ChatMessageList does not pin the transcript or the inner think box', () => {
    const list = readFileSync(
      join(__dirname, '../../components/ChatMessageList.tsx'),
      'utf8',
    );
    expect(list).not.toMatch(/applyTranscriptAutoScroll/);
    expect(list).not.toMatch(/ownedTop/);
    expect(list).not.toMatch(/scrollTop\s*=\s*[^\n]*scrollHeight/);
    expect(list).not.toMatch(/className="bubble ai streaming" aria-live/);
  });

  it('chat-messages and thinking-body disable overflow-anchor', () => {
    const insight = readFileSync(join(__dirname, '../../styles/insight.css'), 'utf8');
    expect(insight).toMatch(/\.chat-messages\s*\{[^}]*overflow-anchor:\s*none/);
    expect(insight).toMatch(/\.thinking-body\s*\{[^}]*overflow-anchor:\s*none/);
  });
});
