// Mirrors lib/utils/reasoning_markers.dart — sniff wrappers from bytes,
// never from a model id. Stream ingest on the Dart host already canonicalizes;
// this is the floor for live streaming + old stored text.

type Fence = { open: string; close: string; startOnly?: boolean; identity?: boolean }

export const REASONING_FENCES: Fence[] = [
  { open: '<｜begin▁of▁thinking｜>', close: '<｜end▁of▁thinking｜>' },
  { open: '<|begin_of_thinking|>', close: '<|end_of_thinking|>' },
  { open: '<|channel|>analysis\n', close: '<|channel|>final' },
  { open: '<|channel|>analysis', close: '<|channel|>final' },
  { open: '<|channel|>thought\n', close: '<channel|>' },
  { open: '<|channel>thought\n', close: '<channel|>' },
  { open: '<|channel|>thought', close: '<channel|>' },
  { open: '<|channel>thought', close: '<channel|>' },
  { open: '◁think▷', close: '◁/think▷' },
  { open: '<thinking>', close: '</thinking>' },
  { open: '<reasoning>', close: '</reasoning>' },
  { open: '<think>', close: '</think>', identity: true },
  { open: 'thought\n', close: '<channel|>', startOnly: true },
]

const INNER = ['<|message|>', '<|end|>', '<|start|>assistant', '<|start|>']

// A provider that hides the think channel server-side can leave the tail of
// the closing tag at the head of the content (Nano-GPT on Kimi K2.6 thinking:
// `hink> To impress…`). Head only, three characters or more ending in `>`,
// so a quoted line or a bare `k>` is never eaten.
const LEADING_CLOSE_TAIL = /^\s*(?:<\/think>|\/think>|think>|hink>|ink>|nk>)/i

export function reasoningMarkersMayBePresent(text: string): boolean {
  if (!text) return false
  if (LEADING_CLOSE_TAIL.test(text)) return true
  if (/<think/i.test(text)) return true
  if (text.includes('<|channel') || text.includes('<channel|')) return true
  if (text.includes('◁think')) return true
  if (text.includes('<reasoning') || text.includes('<thinking')) return true
  if (text.includes('begin▁of▁thinking') || text.includes('begin_of_thinking')) {
    return true
  }
  return text.startsWith('thought\n') || text.startsWith('thought\r')
}

function stripInner(s: string): string {
  let out = s
  for (const t of INNER) out = out.split(t).join('')
  return out
}

function earliestOpen(
  text: string,
  from: number,
  allowStartOnly: boolean,
): { fence: Fence; index: number } | null {
  let best: { fence: Fence; index: number } | null = null
  for (const f of REASONING_FENCES) {
    if (f.startOnly && !allowStartOnly) continue
    const at = f.startOnly
      ? from === 0 && text.startsWith(f.open) ? 0 : -1
      : text.indexOf(f.open, from)
    if (at < 0) continue
    if (
      !best ||
      at < best.index ||
      (at === best.index && f.open.length > best.fence.open.length)
    ) {
      best = { fence: f, index: at }
    }
  }
  return best
}

export function canonicalizeReasoning(text: string): string {
  if (!text || !reasoningMarkersMayBePresent(text)) return text
  text = text.replace(LEADING_CLOSE_TAIL, '')
  let out = ''
  let i = 0
  let emitted = false
  while (i < text.length) {
    const hit = earliestOpen(text, i, !emitted && i === 0)
    if (!hit) {
      out += text.slice(i)
      break
    }
    if (hit.index > i) {
      out += text.slice(i, hit.index)
      emitted = true
    }
    const innerStart = hit.index + hit.fence.open.length
    const closeAt = text.indexOf(hit.fence.close, innerStart)
    const inner = closeAt < 0 ? text.slice(innerStart) : text.slice(innerStart, closeAt)
    if (hit.fence.identity) {
      out += hit.fence.open + inner
      if (closeAt >= 0) out += hit.fence.close
    } else {
      out += '<think>' + stripInner(inner)
      if (closeAt >= 0) out += '</think>\n'
    }
    emitted = true
    if (closeAt < 0) break
    i = closeAt + hit.fence.close.length
  }
  return out
}
