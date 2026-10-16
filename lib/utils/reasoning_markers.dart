// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

/// Industry think wrappers, sniffed from **bytes**, never from a model id.
///
/// Hosts that already split `reasoning_content` never hit this. Hosts that
/// dump thinking inside `content` (NanoGPT Gemma 4, MiniMax, some TC) get
/// the same `<think>…</think>` the rest of the app already parses.
///
/// New wrapper = one row. Not an `if (model.contains(…))`.
class ReasoningFence {
  const ReasoningFence(
    this.open,
    this.close, {
    this.startOnly = false,
    this.identity = false,
  });

  final String open;
  final String close;

  /// Only legal at the start of the assistant stream (stripped Gemma
  /// `<|channel>thought` → leftover `thought\n`).
  final bool startOnly;

  /// Already `<think>` — copy through, do not nest.
  final bool identity;
}

/// Longest open first so `<|channel|>thought` wins over a shorter prefix.
const List<ReasoningFence> kReasoningFences = [
  ReasoningFence('<｜begin▁of▁thinking｜>', '<｜end▁of▁thinking｜>'),
  ReasoningFence('<|begin_of_thinking|>', '<|end_of_thinking|>'),
  ReasoningFence('<|channel|>analysis\n', '<|channel|>final'),
  ReasoningFence('<|channel|>analysis', '<|channel|>final'),
  ReasoningFence('<|channel|>thought\n', '<channel|>'),
  ReasoningFence('<|channel>thought\n', '<channel|>'),
  ReasoningFence('<|channel|>thought', '<channel|>'),
  ReasoningFence('<|channel>thought', '<channel|>'),
  ReasoningFence('◁think▷', '◁/think▷'),
  ReasoningFence('<thinking>', '</thinking>'),
  ReasoningFence('<reasoning>', '</reasoning>'),
  ReasoningFence('<think>', '</think>', identity: true),
  ReasoningFence('thought\n', '<channel|>', startOnly: true),
];

const List<String> _kInnerSpecials = [
  '<|message|>',
  '<|end|>',
  '<|start|>assistant',
  '<|start|>',
];

/// What a provider that hides the think channel server-side can leave at the
/// head of the content: the tail of the closing tag it cut mid-token.
/// Nano-GPT on Kimi K2.6 thinking with `reasoning.exclude`, 2026-10-14:
/// three live captures opened with `hin` + `k> To impress…`; chat showed
/// `think>`. No `<` reaches the app, so the fences above cannot see it.
/// Head of the reply only, and at least three characters ending in `>`,
/// so a quoted line (`> …`) or a bare `k>` is never eaten.
const List<String> kStrippedCloseTails = [
  '</think>',
  '/think>',
  'think>',
  'hink>',
  'ink>',
  'nk>',
];

final RegExp _leadingCloseTail = RegExp(
  r'^\s*(?:</think>|/think>|think>|hink>|ink>|nk>)',
  caseSensitive: false,
);

String _dropLeadingCloseTail(String text) {
  final m = _leadingCloseTail.firstMatch(text);
  return m == null ? text : text.substring(m.end);
}

/// Whether [head] (whitespace allowed before it) could still grow into one
/// of [kStrippedCloseTails]: the stream has not shown enough to decide.
bool _couldBecomeCloseTail(String head) {
  final t = head.trimLeft().toLowerCase();
  if (t.isEmpty) return true;
  for (final tail in kStrippedCloseTails) {
    if (tail.length > t.length && tail.startsWith(t)) return true;
  }
  return false;
}

int get _maxOpenLen {
  var n = 1;
  for (final f in kReasoningFences) {
    if (f.open.length > n) n = f.open.length;
  }
  return n;
}

/// Cheap reject for the ChatMessage fast path (almost every bubble).
bool reasoningMarkersMayBePresent(String text) {
  if (text.isEmpty) return false;
  if (text.contains('<think') ||
      text.contains('<Think') ||
      text.contains('<THINK')) {
    return true;
  }
  if (text.contains('<|channel') || text.contains('<channel|')) return true;
  if (text.contains('◁think')) return true;
  if (text.contains('<reasoning') || text.contains('<thinking')) return true;
  if (text.contains('begin▁of▁thinking') ||
      text.contains('begin_of_thinking')) {
    return true;
  }
  if (_leadingCloseTail.hasMatch(text)) return true;
  return text.startsWith('thought\n') || text.startsWith('thought\r');
}

String _stripInnerSpecials(String s) {
  var out = s;
  for (final t in _kInnerSpecials) {
    out = out.replaceAll(t, '');
  }
  return out;
}

({ReasoningFence fence, int index})? _earliestOpen(
  String text,
  int from, {
  required bool allowStartOnly,
}) {
  ({ReasoningFence fence, int index})? best;
  for (final f in kReasoningFences) {
    if (f.startOnly && !allowStartOnly) continue;
    final at = f.startOnly
        ? (from == 0 && text.startsWith(f.open) ? 0 : -1)
        : text.indexOf(f.open, from);
    if (at < 0) continue;
    if (best == null ||
        at < best.index ||
        (at == best.index && f.open.length > best.fence.open.length)) {
      best = (fence: f, index: at);
    }
  }
  return best;
}

/// Full-string convert: any known wrapper → `<think>…</think>`. Idempotent
/// on already-canonical text. Unclosed open (cut mid-think) stays open.
String canonicalizeReasoning(String text) {
  if (text.isEmpty || !reasoningMarkersMayBePresent(text)) return text;
  text = _dropLeadingCloseTail(text);
  final buf = StringBuffer();
  var i = 0;
  var emitted = false;
  while (i < text.length) {
    final hit = _earliestOpen(text, i, allowStartOnly: !emitted && i == 0);
    if (hit == null) {
      buf.write(text.substring(i));
      break;
    }
    if (hit.index > i) {
      buf.write(text.substring(i, hit.index));
      emitted = true;
    }
    final innerStart = hit.index + hit.fence.open.length;
    final closeAt = text.indexOf(hit.fence.close, innerStart);
    final inner = closeAt < 0
        ? text.substring(innerStart)
        : text.substring(innerStart, closeAt);
    if (hit.fence.identity) {
      buf.write(hit.fence.open);
      buf.write(inner);
      if (closeAt >= 0) buf.write(hit.fence.close);
    } else {
      buf.write('<think>');
      buf.write(_stripInnerSpecials(inner));
      if (closeAt >= 0) buf.write('</think>\n');
    }
    emitted = true;
    if (closeAt < 0) break;
    i = closeAt + hit.fence.close.length;
  }
  return buf.toString();
}

/// Incremental cousin of [canonicalizeReasoning] for token streams.
///
/// Holds back only a suffix that could still complete an open marker, so
/// ordinary prose is not delayed. [keep] false (thinking requested off)
/// drops the think body and keeps the spoken tail.
class ReasoningMarkerRewriter {
  ReasoningMarkerRewriter({this.keep = true});

  final bool keep;

  final StringBuffer _hold = StringBuffer();
  ReasoningFence? _open;
  bool _emitted = false;

  /// The head of the stream has been judged for a stripped close tail.
  bool _headChecked = false;

  String push(String delta) {
    if (delta.isEmpty) return '';
    _hold.write(delta);
    return _drain(end: false);
  }

  String finish() => _drain(end: true);

  String _drain({required bool end}) {
    final out = StringBuffer();
    var s = _hold.toString();
    if (!_headChecked && _open == null) {
      final tail = _leadingCloseTail.firstMatch(s);
      if (tail != null) {
        s = s.substring(tail.end);
        _headChecked = true;
      } else if (!end && _couldBecomeCloseTail(s)) {
        return '';
      } else {
        _headChecked = true;
      }
    }
    var i = 0;
    while (i < s.length) {
      if (_open != null) {
        final closeAt = s.indexOf(_open!.close, i);
        if (closeAt < 0) {
          if (end) {
            if (keep) {
              out.write(_stripInnerSpecials(s.substring(i)));
              out.write('</think>\n');
            }
            i = s.length;
            _open = null;
          } else {
            final keepTo = i + _flushableLen(s.substring(i), [_open!.close]);
            if (keep && keepTo > i) {
              out.write(_stripInnerSpecials(s.substring(i, keepTo)));
            }
            i = keepTo;
          }
          break;
        }
        if (keep) {
          out.write(_stripInnerSpecials(s.substring(i, closeAt)));
          if (!_open!.identity) out.write('</think>\n');
          if (_open!.identity) out.write(_open!.close);
        }
        i = closeAt + _open!.close.length;
        _open = null;
        continue;
      }
      final hit = _earliestOpen(s, i, allowStartOnly: !_emitted && i == 0);
      if (hit == null) {
        if (end) {
          out.write(s.substring(i));
          i = s.length;
        } else {
          final opens = [
            for (final f in kReasoningFences)
              if (!(f.startOnly && _emitted)) f.open,
          ];
          final keepTo = i + _flushableLen(s.substring(i), opens);
          if (keepTo > i) {
            out.write(s.substring(i, keepTo));
            _emitted = true;
          }
          i = keepTo;
        }
        break;
      }
      if (hit.index > i) {
        out.write(s.substring(i, hit.index));
        _emitted = true;
      }
      _open = hit.fence;
      i = hit.index + hit.fence.open.length;
      if (keep) {
        out.write(hit.fence.identity ? hit.fence.open : '<think>');
        _emitted = true;
      }
    }
    _hold
      ..clear()
      ..write(s.substring(i));
    return out.toString();
  }
}

/// How much of [region] can be emitted: drop a suffix that is still a
/// prefix of one of [markers] (split token). Ordinary prose flushes whole.
int _flushableLen(String region, List<String> markers) {
  if (region.isEmpty) return 0;
  final maxHold = _maxOpenLen;
  final cap = region.length < maxHold ? region.length : maxHold;
  for (var hold = cap; hold >= 1; hold--) {
    final suffix = region.substring(region.length - hold);
    for (final m in markers) {
      if (m.startsWith(suffix)) return region.length - hold;
    }
  }
  return region.length;
}
