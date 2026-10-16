import { describe, expect, it } from 'vitest'
import { canonicalizeReasoning } from './reasoningMarkers'

describe('canonicalizeReasoning', () => {
  it('leaves plain prose alone', () => {
    expect(canonicalizeReasoning('Hello there.')).toBe('Hello there.')
  })

  it('converts Gemma 4 channels to <think>', () => {
    const out = canonicalizeReasoning(
      '<|channel>thought\nessay\n<channel|>"Stay."',
    )
    expect(out).toContain('<think>')
    expect(out).toContain('</think>')
    expect(out).toContain('"Stay."')
    expect(out).not.toContain('<|channel>')
  })

  it('does not treat "I thought about it" as a think block', () => {
    expect(canonicalizeReasoning('I thought about it on the porch.')).toBe(
      'I thought about it on the porch.',
    )
  })
})

// Nano-GPT hides Kimi K2.6's think channel server-side and, after a long
// think, leaves the tail of the closing tag at the head of the content
// (`hink> To impress…`). The Dart host strips it on ingest; this is the
// floor for text stored before the fix and for the live streaming view.
describe('stripped close-tag tail at the head of a reply', () => {
  it('drops the tail and keeps the reply', () => {
    expect(canonicalizeReasoning('hink> To impress, I stand.')).toBe(
      ' To impress, I stand.',
    )
    expect(canonicalizeReasoning('think> Hi.')).toBe(' Hi.')
    expect(canonicalizeReasoning('\n</think>\nHi.')).toBe('\nHi.')
    expect(canonicalizeReasoning('nk> Hi.')).toBe(' Hi.')
  })

  it('only at the head, never mid-reply, never a bare >', () => {
    expect(canonicalizeReasoning('The link> stays as typed.')).toBe(
      'The link> stays as typed.',
    )
    expect(canonicalizeReasoning('> quoted line')).toBe('> quoted line')
    expect(canonicalizeReasoning('k> too short')).toBe('k> too short')
    expect(canonicalizeReasoning('thinking aloud')).toBe('thinking aloud')
  })
})
