// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Find-in-chat (⌘F) query engine — the single semantic truth shared by the
/// desktop scan, the web route (`GET /api/chat/search`), and both highlight
/// renderers' leaf matching. Mirrors the reviewed mockup
/// (docs/design/mockups/chat-find-bar.html) exactly:
///
/// * no `*` typed        → plain substring, unchanged behaviour;
/// * `*` typed (not regex)→ word-anchored glob: `*` matches a run of word
///   characters inside ONE word, and the whole-word lock makes `*dog` mean
///   "ends with dog" (naive `.*` would reduce it to plain `dog`);
/// * regex mode          → the raw input is an ECMAScript pattern, unanchored
///   — the cross-space window (`lantern.*storm`) deliberately lives here;
/// * `\*`                → a literal asterisk (action text contains real `*`);
/// * boundaries are checked manually — Dart's RegExp has no lookbehind, and
///   the manual check is what keeps the JS mirror behaviour-identical;
/// * matches inside `![alt](url)` are invisible: the bubble renders those as
///   images, and find is scoped to what is visible.
library;

const findRegionSender = 1;
const findRegionBody = 0;
const kFindMatchCap = 999;

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final RegExp _imageSpan = RegExp(r'!\[[^\]]*\]\((?:https?://[^)]+)\)');
const String _starSentinel = '\uE000';

/// Compiled form of one find-bar query. Exactly one path is live:
/// [bad], [needle], or [pattern] (+ [wordBounded] when it came from a glob).
class ChatQuerySpec {
  final bool bad;
  final String? needle;
  final RegExp? pattern;
  final bool wordBounded;
  final bool caseSensitive;
  const ChatQuerySpec._({
    this.bad = false,
    this.needle,
    this.pattern,
    this.wordBounded = false,
    this.caseSensitive = false,
  });

  bool get isEmpty => !bad && needle != null && needle!.isEmpty;
}

ChatQuerySpec compileChatQuery(
  String raw, {
  bool regexMode = false,
  bool caseSensitive = false,
}) {
  final query = raw.trim();
  if (regexMode) {
    if (query.isEmpty) return const ChatQuerySpec._(needle: '');
    try {
      return ChatQuerySpec._(
        pattern: RegExp(query, caseSensitive: caseSensitive, unicode: true),
        caseSensitive: caseSensitive,
      );
    } on FormatException {
      return const ChatQuerySpec._(bad: true);
    }
  }
  final folded = caseSensitive ? query : query.toLowerCase();
  final starred = folded.replaceAll(r'\*', _starSentinel);
  if (!starred.contains('*')) {
    return ChatQuerySpec._(
      needle: starred.replaceAll(_starSentinel, '*'),
      caseSensitive: caseSensitive,
    );
  }
  final parts = starred
      .split('*')
      .map((p) {
        final escaped = p.replaceAllMapped(
          RegExp(r'[.*+?^${}()|[\]\\]'),
          (m) => '\\${m[0]}',
        );
        return escaped.replaceAll(_starSentinel, r'\*');
      })
      .join(r'[\p{L}\p{N}_]*');
  return ChatQuerySpec._(
    pattern: RegExp(parts, caseSensitive: caseSensitive, unicode: true),
    wordBounded: true,
    caseSensitive: caseSensitive,
  );
}

/// One navigation unit: one highlighted range in one region of one message.
class ChatFindMatch {
  final int messageIndex;

  /// [findRegionBody] or [findRegionSender].
  final int region;

  /// 0-based occurrence within (messageIndex, region) — the leaf highlighters
  /// count in the same order and paint the active occurrence strong.
  final int occurrenceInRegion;

  /// Range into the region's string (body = displayText, sender = sender).
  final int startInRegion;
  final int endInRegion;

  const ChatFindMatch({
    required this.messageIndex,
    required this.region,
    required this.occurrenceInRegion,
    required this.startInRegion,
    required this.endInRegion,
  });
}

/// Ranges of [spec] inside one string — the same pass leaf renderers use to
/// split their spans. Manual word-boundary check for globs; image spans are
/// skipped. Empty needles match nothing.
List<({int start, int end})> chatQueryRanges(String text, ChatQuerySpec spec) {
  final out = <({int start, int end})>[];
  if (spec.isEmpty) return out;
  final images = _imageSpan
      .allMatches(text)
      .map((m) => (start: m.start, end: m.end))
      .toList();
  bool inImage(int start, int end) =>
      images.any((im) => start < im.end && end > im.start);

  final needle = spec.needle;
  if (needle != null) {
    final hay = spec.caseSensitive ? text : text.toLowerCase();
    var idx = hay.indexOf(needle);
    while (idx != -1) {
      final end = idx + needle.length;
      if (!inImage(idx, end)) out.add((start: idx, end: end));
      idx = hay.indexOf(needle, idx + 1);
    }
    return out;
  }
  final pattern = spec.pattern;
  if (pattern == null) return out;
  for (final m in pattern.allMatches(text)) {
    if (m.end == m.start) continue;
    if (spec.wordBounded && !_wordBounded(text, m.start, m.end)) continue;
    if (inImage(m.start, m.end)) continue;
    out.add((start: m.start, end: m.end));
  }
  return out;
}

bool _wordBounded(String text, int start, int end) {
  if (start > 0 && _wordChar.hasMatch(text[start - 1])) return false;
  if (end < text.length && _wordChar.hasMatch(text[end])) return false;
  return true;
}

/// Ordered hit list over a window (or the whole archive) of messages.
/// Sender names are one region ordered before the body. Caps at [cap] hits.
List<ChatFindMatch> scanTranscript(
  Iterable<({String text, String sender})> messages,
  ChatQuerySpec spec, {
  int cap = kFindMatchCap,
}) {
  final hits = <ChatFindMatch>[];
  if (spec.bad || spec.isEmpty) return hits;
  var messageIndex = 0;
  for (final message in messages) {
    final senderHits = chatQueryRanges(message.sender, spec);
    var occurrence = 0;
    for (final r in senderHits) {
      if (hits.length >= cap) return hits;
      hits.add(
        ChatFindMatch(
          messageIndex: messageIndex,
          region: findRegionSender,
          occurrenceInRegion: occurrence++,
          startInRegion: r.start,
          endInRegion: r.end,
        ),
      );
    }
    final bodyHits = chatQueryRanges(message.text, spec);
    occurrence = 0;
    for (final r in bodyHits) {
      if (hits.length >= cap) return hits;
      hits.add(
        ChatFindMatch(
          messageIndex: messageIndex,
          region: findRegionBody,
          occurrenceInRegion: occurrence++,
          startInRegion: r.start,
          endInRegion: r.end,
        ),
      );
    }
    messageIndex++;
  }
  return hits;
}
