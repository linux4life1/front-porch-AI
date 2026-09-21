import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { applyTranscriptAutoScroll } from './transcriptAutoScroll';

describe('transcript auto-scroll (option B)', () => {
  it('does not move a user-owned scrollTop on stream or new message', () => {
    const scrollTo = vi.fn();
    const el = { scrollTop: 80, scrollHeight: 400, scrollTo };
    applyTranscriptAutoScroll(el);
    expect(scrollTo).not.toHaveBeenCalled();
    expect(el.scrollTop).toBe(80);
  });

  it('useChatSession does not pin the transcript on messages.length or streaming', () => {
    const src = readFileSync(join(__dirname, 'useChatSession.ts'), 'utf8');
    expect(src).not.toMatch(/scrollTo\(\s*\{\s*top:\s*scrollRef/);
    expect(src).not.toMatch(/scrollHeight\s*\}\s*\)/);
  });
});
