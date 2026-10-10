// Older history above vs new rows below, when the last line is the same
// before and after. The first row's stable id decides; an older page that
// starts with the same words as the old first row still reads as older
// history.
import { describe, expect, it } from 'vitest';
import {
  classifyTranscriptGrowth,
  isTranscriptPrepend,
  transcriptHeadKey,
  transcriptTipKey,
} from './transcriptAutoScroll';

type Row = { sender: string; text: string; rowKey?: number };
let next = 1;
const row = (text: string, sender = 'Iris'): Row => ({ sender, text, rowKey: next++ });

const prepend = (before: Row[], after: Row[]) =>
  isTranscriptPrepend({
    prevLen: before.length,
    prevTip: transcriptTipKey(before),
    nextLen: after.length,
    nextTip: transcriptTipKey(after),
    prevHead: transcriptHeadKey(before),
    nextHead: transcriptHeadKey(after),
  });

describe('transcript head identity', () => {
  const head = row('ok');
  const tip = row('See you tomorrow.');
  const before = [head, row('Night.', 'You'), tip];

  it('rows added below with a repeated last line are not older history', () => {
    const after = [...before, row('Night.', 'You'), row(tip.text)];
    expect(prepend(before, after)).toBe(false);
    expect(
      classifyTranscriptGrowth({
        sessionId: 's',
        prevSession: 's',
        prevLen: before.length,
        prevTip: transcriptTipKey(before),
        nextLen: after.length,
        nextTip: transcriptTipKey(after),
        prevHead: transcriptHeadKey(before),
        nextHead: transcriptHeadKey(after),
      }),
    ).toBe('other');
  });

  it('an older page is older history', () => {
    expect(prepend(before, [row('Morning.'), row('Hi.', 'You'), ...before])).toBe(true);
  });

  it('an older page that starts with the same words as the old first row is still older history', () => {
    expect(prepend(before, [row('ok'), row('Hi.', 'You'), ...before])).toBe(true);
  });

  it('rows with no id fall back to their text', () => {
    const a = [{ sender: 'Iris', text: 'ok' }];
    expect(transcriptHeadKey(a)).toBe(transcriptHeadKey([{ sender: 'Iris', text: 'ok' }]));
  });
});
