import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  applyTranscriptAutoScroll,
  classifyTranscriptGrowth,
  DEFAULT_FOLLOW_STREAMING,
  followTranscriptWhileStreaming,
  holdTranscriptAfterPrepend,
  pinTranscriptToLatest,
} from './transcriptAutoScroll';

describe('transcript stream scroll (option B)', () => {
  it('does not rewrite scrollTop on a stream tick', () => {
    const el = { scrollTop: 360, scrollHeight: 800 };
    applyTranscriptAutoScroll(el, 80);
    expect(el.scrollTop).toBe(360);
  });

  it('open/load pins a forward list to the latest messages once', () => {
    const el = { scrollTop: 0, scrollHeight: 800 };
    pinTranscriptToLatest(el);
    expect(el.scrollTop).toBe(800);
    applyTranscriptAutoScroll(el, 0);
    expect(el.scrollTop).toBe(800);
  });

  it('classifies open vs backward prepend vs a new tip', () => {
    expect(
      classifyTranscriptGrowth({
        prevSession: null,
        prevLen: 0,
        prevTip: '',
        nextLen: 10,
        nextTip: 'Iris\0latest',
      }),
    ).toBe('open');
    expect(
      classifyTranscriptGrowth({
        sessionId: 's1',
        prevSession: null,
        prevLen: 0,
        prevTip: '',
        nextLen: 24,
        nextTip: 'Iris\0latest',
      }),
    ).toBe('open');
    expect(
      classifyTranscriptGrowth({
        sessionId: 's1',
        prevSession: 's1',
        prevLen: 24,
        prevTip: 'Iris\0latest',
        nextLen: 224,
        nextTip: 'Iris\0latest',
      }),
    ).toBe('prepend');
    expect(
      classifyTranscriptGrowth({
        sessionId: 's1',
        prevSession: 's1',
        prevLen: 224,
        prevTip: 'Iris\0latest',
        nextLen: 225,
        nextTip: 'Iris\0new reply',
      }),
    ).toBe('other');
    expect(
      classifyTranscriptGrowth({
        sessionId: 's1',
        prevSession: 's1',
        prevLen: 224,
        prevTip: 'Iris\0latest',
        nextLen: 224,
        nextTip: 'Iris\0latest',
      }),
    ).toBe('other');
  });

  it('prepend holds the viewport instead of dumping at first_message', () => {
    const el = { scrollTop: 400, scrollHeight: 2500 };
    holdTranscriptAfterPrepend(el, 500);
    expect(el.scrollTop).toBe(2400);
  });

  it('ChatMessageList one-shot pins on session, holds prepend, not stream', () => {
    const list = readFileSync(
      join(__dirname, '../../components/ChatMessageList.tsx'),
      'utf8',
    );
    expect(list).toMatch(/pinTranscriptToLatest/);
    expect(list).toMatch(/rowKey/);
    expect(list).not.toMatch(/scrollTop\s*=\s*.*scrollHeight/);
    expect(list).toMatch(/holdTranscriptAfterPrepend/);
    expect(list).toMatch(/followTranscriptWhileStreaming/);
    expect(list).toMatch(/classifyTranscriptGrowth/);
    expect(list).not.toMatch(/applyTranscriptAutoScroll/);
    expect(list).not.toMatch(/ownedTop/);
    expect(list).not.toMatch(/className="bubble ai streaming" aria-live/);
    const session = readFileSync(join(__dirname, 'useChatSession.ts'), 'utf8');
    expect(session).toMatch(/history-older/);
  });

  it('follow defaults on; OFF and scrolled-away do not chase', () => {
    expect(DEFAULT_FOLLOW_STREAMING).toBe(true);
    const atBottom = { scrollTop: 736, scrollHeight: 900, clientHeight: 64 };
    expect(
      followTranscriptWhileStreaming(atBottom, {
        followEnabled: true,
        generating: true,
        previousHeight: 800,
      }),
    ).toBe(true);
    expect(atBottom.scrollTop).toBe(900);

    const off = { scrollTop: 736, scrollHeight: 900, clientHeight: 64 };
    expect(
      followTranscriptWhileStreaming(off, {
        followEnabled: false,
        generating: true,
        previousHeight: 800,
      }),
    ).toBe(false);
    expect(off.scrollTop).toBe(736);

    const away = { scrollTop: 80, scrollHeight: 900, clientHeight: 64 };
    expect(
      followTranscriptWhileStreaming(away, {
        followEnabled: true,
        generating: true,
        previousHeight: 800,
      }),
    ).toBe(false);
    expect(away.scrollTop).toBe(80);
  });

  it('Settings places Follow streaming replies above Reading size', () => {
    const page = readFileSync(join(__dirname, '../SettingsPage.tsx'), 'utf8');
    const follow = page.indexOf('<FollowStreamingSettings');
    const reading = page.indexOf('<ReadingSizeSettings');
    expect(follow).toBeGreaterThan(-1);
    expect(reading).toBeGreaterThan(follow);
  });

  it('chat-messages and thinking-body disable overflow-anchor', () => {
    const insight = readFileSync(join(__dirname, '../../styles/insight.css'), 'utf8');
    expect(insight).toMatch(/\.chat-messages\s*\{[^}]*overflow-anchor:\s*none/);
    expect(insight).toMatch(/\.thinking-body\s*\{[^}]*overflow-anchor:\s*none/);
  });
});
