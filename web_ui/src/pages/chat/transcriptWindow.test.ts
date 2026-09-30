import { describe, expect, it } from 'vitest'
import { applyTranscriptSpan, revealOlderSpan, TRANSCRIPT_TAIL } from './transcriptWindow'

describe('transcript window', () => {
  it('opens a long chat on the latest lines', () => {
    const span = { start: 0, end: 0 }
    applyTranscriptSpan(span, {
      previousLength: 0,
      nextLength: 11270,
      opened: true,
      prepended: false,
      nearTop: false,
    })
    expect(span.end).toBe(11270)
    expect(span.start).toBe(11270 - TRANSCRIPT_TAIL)
  })

  it('keeps the reader in place when older rows arrive behind them', () => {
    const span = { start: 0, end: 24 }
    applyTranscriptSpan(span, {
      previousLength: 24,
      nextLength: 224,
      opened: false,
      prepended: true,
      nearTop: false,
    })
    expect(span.start).toBe(200)
    expect(span.end).toBe(224)
  })

  it('includes older rows when the reader is already at the top', () => {
    const span = { start: 0, end: 24 }
    applyTranscriptSpan(span, {
      previousLength: 24,
      nextLength: 224,
      opened: false,
      prepended: true,
      nearTop: true,
    })
    expect(span.start).toBe(0)
    expect(span.end).toBe(224)
    expect(revealOlderSpan(span, 224)).toBe(false)
  })
})
