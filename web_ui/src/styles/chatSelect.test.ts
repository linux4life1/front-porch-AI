import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

function read(rel: string): string {
  return readFileSync(join(__dirname, rel), 'utf8');
}

describe('chat select/copy CSS', () => {
  it('marks bubble body and thought as selectable', () => {
    const insight = read('./insight.css');
    expect(insight).toMatch(/\.bubble\s*\{[^}]*user-select:\s*text/);
    expect(insight).toMatch(/\.thinking-body\s*\{[^}]*user-select:\s*text/);
    expect(insight).toMatch(/\.msg-speaker\s*\{[^}]*user-select:\s*none/);
  });

  it('keeps action chrome unselectable', () => {
    const messages = read('./messages.css');
    expect(messages).toMatch(/\.msg-actions\s*\{[^}]*user-select:\s*none/);
    expect(messages).toMatch(/\.swipe\s*\{[^}]*user-select:\s*none/);
  });

  it('marks dream banners selectable', () => {
    const living = read('./living-time.css');
    expect(living).toMatch(/\.dream-banner\s*\{[^}]*user-select:\s*text/);
  });
});
