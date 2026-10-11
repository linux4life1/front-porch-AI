// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Token alternatives (KoboldCpp only): the words the model nearly wrote.
// A reply's per-token probabilities are aligned to the reply's visible body;
// the places where the model was unsure are kept on that swipe's metadata,
// each with the other words it weighed. Picking one rewrites the reply from
// that point as a new swipe.

import 'dart:math' as math;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Swipe-metadata key holding a list of [TokenAlternative.toJson] maps.
const kTokenAltsKey = 'token_alts';

/// A word is listed when the model gave the word it wrote less than this.
const kTokenAltsMaxChosenP = 0.5;

/// An alternative below this probability is not worth offering.
const kTokenAltsMinAltP = 0.02;

/// At most this many places are kept per reply (the least certain ones).
const kTokenAltsCap = 40;

/// One place in a reply where the model was unsure.
class TokenAlternative {
  /// Character offset of [token] in the reply's visible body.
  final int offset;
  final String token;
  final double p;

  /// The other words, most likely first.
  final List<({String token, double p})> alts;

  const TokenAlternative({
    required this.offset,
    required this.token,
    required this.p,
    required this.alts,
  });

  Map<String, dynamic> toJson() => {
    'o': offset,
    't': token,
    'p': _round(p),
    'a': [
      for (final a in alts) [a.token, _round(a.p)],
    ],
  };

  static TokenAlternative? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final o = raw['o'];
    final t = raw['t'];
    final p = raw['p'];
    final a = raw['a'];
    if (o is! int || t is! String || p is! num || a is! List) return null;
    final alts = <({String token, double p})>[];
    for (final e in a) {
      if (e is List && e.length == 2 && e[0] is String && e[1] is num) {
        alts.add((token: e[0] as String, p: (e[1] as num).toDouble()));
      }
    }
    if (alts.isEmpty) return null;
    return TokenAlternative(offset: o, token: t, p: p.toDouble(), alts: alts);
  }

  static double _round(double p) => (p * 1000).round() / 1000;
}

/// The visible body of [text] (thinking removed), which offsets index into.
String tokenAltsBody(String text) => splitMessageForEdit(text).body;

/// Aligns KoboldCpp `logprobs.content` entries to [body] and keeps the
/// uncertain ones. [from] skips text the model did not write this time (the
/// seed of a rewrite). Entries that cannot be placed exactly are dropped.
List<TokenAlternative> buildTokenAlternatives(
  List<Object?> logprobs,
  String body, {
  int from = 0,
}) {
  final starts = <int>[];
  final joined = StringBuffer();
  for (final e in logprobs) {
    starts.add(joined.length);
    final tok = e is Map ? e['token'] : null;
    joined.write(tok is String ? tok : '');
  }
  final all = joined.toString();

  // Where the body's own words begin in the generated text. Reasoning, when
  // the server includes it, comes first and ends with </think>.
  final rest = body.substring(math.min(from, body.length));
  final trimmed = rest.trimLeft();
  if (trimmed.isEmpty) return const [];
  final head = trimmed.substring(0, math.min(24, trimmed.length));
  final thinkEnd = all.lastIndexOf('</think>');
  final at = all.indexOf(head, thinkEnd < 0 ? 0 : thinkEnd);
  if (at < 0) return const [];
  final shift = at - (body.length - trimmed.length);

  final found = <TokenAlternative>[];
  for (var i = 0; i < logprobs.length; i++) {
    final e = logprobs[i];
    if (e is! Map) continue;
    final tok = e['token'];
    final lp = e['logprob'];
    final tops = e['top_logprobs'];
    if (tok is! String || tok.trim().isEmpty || lp is! num || tops is! List) {
      continue;
    }
    final offset = starts[i] - shift;
    if (offset < from || !_placedAt(body, offset, tok)) continue;
    final p = math.exp(lp.toDouble());
    if (p >= kTokenAltsMaxChosenP) continue;
    final alts = <({String token, double p})>[];
    for (final t in tops) {
      if (t is! Map) continue;
      final at = t['token'];
      final alp = t['logprob'];
      if (at is! String || alp is! num || at.trim().isEmpty) continue;
      if (at.trim() == tok.trim()) continue;
      final ap = math.exp(alp.toDouble());
      if (ap < kTokenAltsMinAltP) continue;
      alts.add((token: at, p: ap));
    }
    if (alts.isEmpty) continue;
    alts.sort((a, b) => b.p.compareTo(a.p));
    found.add(TokenAlternative(offset: offset, token: tok, p: p, alts: alts));
  }
  if (found.length > kTokenAltsCap) {
    found.sort((a, b) => a.p.compareTo(b.p));
    found.removeRange(kTokenAltsCap, found.length);
    found.sort((a, b) => a.offset.compareTo(b.offset));
  }
  return found;
}

bool _placedAt(String body, int offset, String token) =>
    offset >= 0 &&
    offset + token.length <= body.length &&
    body.startsWith(token, offset);

/// The places kept on the swipe [m] is showing that still match its text (an
/// edit moves words, so entries that no longer line up are left out).
List<TokenAlternative> tokenAlternativesOf(ChatMessage m) {
  final raw = m.activeMetadata?[kTokenAltsKey];
  if (raw is! List || raw.isEmpty) return const [];
  final body = tokenAltsBody(m.text);
  return [
    for (final e in raw)
      if (TokenAlternative.tryParse(e) case final a?)
        if (_placedAt(body, a.offset, a.token)) a,
  ];
}

/// The text a rewrite starts from: [body] up to [at], then [pick].
String tokenAltsSeed(String body, TokenAlternative at, String pick) =>
    body.substring(0, at.offset) + pick;

/// A few words before [at], for showing where in the reply it is.
String tokenAltsLeadIn(String body, TokenAlternative at, {int chars = 48}) {
  final start = math.max(0, at.offset - chars);
  var lead = body.substring(start, at.offset);
  if (start > 0) {
    final space = lead.indexOf(' ');
    if (space >= 0) lead = lead.substring(space + 1);
    lead = '…$lead';
  }
  return lead.replaceAll(RegExp(r'\s+'), ' ');
}
