import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { applyTranscriptAutoScroll } from './transcriptAutoScroll';

describe('transcript stream scroll (option B)', () => {
  it('restores a yanked scrollTop to the user-owned offset', () => {
    const el = { scrollTop: 360, scrollHeight: 800 };
    applyTranscriptAutoScroll(el, 80);
    expect(el.scrollTop).toBe(80);
  });

  it('does not move scrollTop when the user already owns that offset', () => {
    const el = { scrollTop: 80, scrollHeight: 800 };
    applyTranscriptAutoScroll(el, 80);
    expect(el.scrollTop).toBe(80);
  });

  it('ChatMessageList holds the transcript and does not pin inner think', () => {
    const list = readFileSync(
      join(__dirname, '../../components/ChatMessageList.tsx'),
      'utf8',
    );
    expect(list).toMatch(/applyTranscriptAutoScroll/);
    expect(list).not.toMatch(/scrollTop\s*=\s*[^\n]*scrollHeight/);
    expect(list).not.toMatch(/className="bubble ai streaming" aria-live/);
  });

  it('chat-messages and thinking-body disable overflow-anchor', () => {
    const insight = readFileSync(join(__dirname, '../../styles/insight.css'), 'utf8');
    expect(insight).toMatch(/\.chat-messages\s*\{[^}]*overflow-anchor:\s*none/);
    expect(insight).toMatch(/\.thinking-body\s*\{[^}]*overflow-anchor:\s*none/);
  });
});
