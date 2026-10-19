// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Find-in-chat (⌘F) query engine — the single semantic truth shared by the
/// desktop scan and the web route (`GET /api/chat/search`). Both highlight
/// renderers paint the ranges this scan returns; neither re-matches. Mirrors the reviewed mockup
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

import 'dart:async';
import 'dart:isolate';

const findRegionSender = 1;
const findRegionBody = 0;
const kFindMatchCap = 999;

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final RegExp _imageSpan = RegExp(r'!\[[^\]]*\]\((?:https?://[^)]+)\)');
const String _starSentinel = '\uE000';

/// Compiled form of one find-bar query: [bad], or a [pattern] to scan with
/// (+ [wordBounded] when it came from a glob). [needle] keeps the plain
/// query's text; it is empty (and [pattern] null) for a no-op search.
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
  // The query keeps its own case: the RegExp's caseSensitive flag folds both
  // sides, and lowering here first broke `İstanbul` (it lowers to `i̇`).
  final starred = query.replaceAll(r'\*', _starSentinel);
  if (!starred.contains('*')) {
    final needle = starred.replaceAll(_starSentinel, '*');
    return ChatQuerySpec._(
      needle: needle,
      // A case-folding RegExp rather than indexOf on toLowerCase(): folding
      // can change a string's length (`İ` lowers to two code units), which
      // would shift every range after it, and indexOf from idx+1 returned
      // overlapping hits ("aa" in "aaaa") that leaf splitters duplicated.
      pattern: needle.isEmpty
          ? null
          : RegExp(
              RegExp.escape(needle),
              caseSensitive: caseSensitive,
              unicode: true,
            ),
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

  /// 0-based occurrence within (messageIndex, region).
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

/// Non-overlapping ranges of [spec] inside one string. Manual word-boundary check for
/// globs; image spans are skipped. Empty needles match nothing.
List<({int start, int end})> chatQueryRanges(String text, ChatQuerySpec spec) {
  final out = <({int start, int end})>[];
  if (spec.isEmpty) return out;
  final images = _imageSpan
      .allMatches(text)
      .map((m) => (start: m.start, end: m.end))
      .toList();
  bool inImage(int start, int end) =>
      images.any((im) => start < im.end && end > im.start);

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

/// How long a regex-mode scan may run before find gives up on it.
const Duration kFindRegexTimeout = Duration(seconds: 2);

/// [scanTranscript] for regex mode, on a throwaway isolate that is killed
/// after [timeout]. A user pattern like `(a+)+$` backtracks for minutes on
/// a long transcript; on the UI (desktop) or server (web) isolate that
/// would freeze the app. Returns null when the scan ran out of time.
Future<List<ChatFindMatch>?> scanTranscriptBounded(
  List<({String text, String sender})> messages,
  String query, {
  required bool regexMode,
  required bool caseSensitive,
  Duration timeout = kFindRegexTimeout,
}) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_boundedScanEntry, (
    port.sendPort,
    messages,
    query,
    regexMode,
    caseSensitive,
  ));
  try {
    return await port.first.timeout(timeout) as List<ChatFindMatch>;
  } on TimeoutException {
    return null;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _boundedScanEntry(
  (SendPort, List<({String text, String sender})>, String, bool, bool) args,
) {
  final (reply, messages, query, regexMode, caseSensitive) = args;
  final spec = compileChatQuery(
    query,
    regexMode: regexMode,
    caseSensitive: caseSensitive,
  );
  reply.send(scanTranscript(messages, spec));
}

/// Outcome of one ⌘F find pass. [stale] means the session or the history
/// epoch moved under the scan (the UI re-runs it); [capped] means hit
/// collection stopped at [kFindMatchCap] and the counter must read "999+";
/// [tooSlow] means a regex scan hit [kFindRegexTimeout] and was abandoned.
class ChatFindOutcome {
  final bool badPattern;
  final bool stale;
  final bool capped;
  final bool tooSlow;
  final List<ChatFindMatch> matches;
  final int totalMessages;
  const ChatFindOutcome({
    this.badPattern = false,
    this.stale = false,
    this.capped = false,
    this.tooSlow = false,
    this.matches = const [],
    this.totalMessages = 0,
  });
}
