// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Token alternatives: KoboldCpp's per-token odds lined up against the reply
// the user sees. Entries are shaped exactly as koboldcpp.py's
// parse_last_logprobs builds them (token, logprob, top_logprobs[token,
// logprob]).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/token_alternatives.dart';

Map<String, Object> tok(
  String t,
  double p, [
  Map<String, double> alts = const {},
]) => {
  'token': t,
  'logprob': math.log(p),
  'top_logprobs': [
    {'token': t, 'logprob': math.log(p)},
    for (final e in alts.entries)
      {'token': e.key, 'logprob': math.log(e.value)},
  ],
};

void main() {
  test('unsure words are kept at their place in the visible body', () {
    const body = 'She sat on the porch swing.';
    final probs = [
      tok('She', 0.9),
      tok(' sat', 0.4, {' stood': 0.3, ' leaned': 0.2}),
      tok(' on', 0.95),
      tok(' the', 0.97),
      tok(' porch', 0.3, {' steps': 0.25, ' old': 0.01}),
      tok(' swing', 0.8, {' rail': 0.15}),
      tok('.', 0.99),
    ];

    final found = buildTokenAlternatives(probs, body);

    expect(found.map((a) => a.token), [' sat', ' porch']);
    expect(found[0].offset, body.indexOf(' sat'));
    expect(found[0].alts.map((a) => a.token), [' stood', ' leaned']);
    expect(found[1].alts.map((a) => a.token), [
      ' steps',
    ], reason: 'alternatives under 2% are not offered');
  });

  test('reasoning tokens before the answer do not shift the places', () {
    const text = '<think>sat on it</think>\nShe sat down.';
    final body = tokenAltsBody(text);
    final probs = [
      tok('<think>', 0.99),
      tok('sat', 0.2, {'stood': 0.3}),
      tok(' on it', 0.9),
      tok('</think>', 0.99),
      tok('\n', 0.9),
      tok('She', 0.9),
      tok(' sat', 0.4, {' knelt': 0.3}),
      tok(' down.', 0.9),
    ];

    final found = buildTokenAlternatives(probs, body);

    expect(found, hasLength(1), reason: 'the thought is not the reply');
    expect(found.single.token, ' sat');
    expect(body.substring(found.single.offset), startsWith(' sat down.'));
  });

  test('a rewrite only lists the words written after its seed', () {
    const body = 'She knelt by the gate.';
    const seed = 'She knelt';
    final probs = [
      tok(' by', 0.3, {' at': 0.4}),
      tok(' the', 0.9),
      tok(' gate', 0.45, {' door': 0.3}),
      tok('.', 0.99),
    ];

    final found = buildTokenAlternatives(probs, body, from: seed.length);

    expect(found.map((a) => a.token), [' by', ' gate']);
    expect(found.first.offset, seed.length);
  });

  test('stored places survive a round trip and an edit hides stale ones', () {
    const body = 'She sat on the porch.';
    final found = buildTokenAlternatives([
      tok('She', 0.9),
      tok(' sat', 0.4, {' stood': 0.3}),
      tok(' on the', 0.9),
      tok(' porch', 0.3, {' steps': 0.3}),
      tok('.', 0.9),
    ], body);
    final meta = <String, dynamic>{
      kTokenAltsKey: [for (final a in found) a.toJson()],
    };
    final m = ChatMessage(
      text: body,
      sender: 'Nia',
      isUser: false,
      metadata: meta,
      swipeMetadata: [meta],
    );
    expect(tokenAlternativesOf(m).map((a) => a.token), [' sat', ' porch']);

    m.text = 'She sat on the old porch.';
    expect(tokenAlternativesOf(m).map((a) => a.token), [
      ' sat',
    ], reason: 'the edit moved "porch"; its place no longer lines up');
  });

  test('the seed is the body up to the place, then the picked word', () {
    const body = 'She sat on the porch swing.';
    final at = buildTokenAlternatives([
      tok('She sat on the', 0.9),
      tok(' porch', 0.3, {' steps': 0.3}),
      tok(' swing.', 0.9),
    ], body).single;

    expect(tokenAltsSeed(body, at, ' steps'), 'She sat on the steps');
    expect(tokenAltsLeadIn(body, at), 'She sat on the');
  });

  test('a long reply keeps only its least certain places', () {
    final words = [for (var i = 0; i < 60; i++) ' w$i'];
    final body = words.join();
    final probs = [
      for (var i = 0; i < 60; i++) tok(words[i], 0.1 + i * 0.006, {' x': 0.05}),
    ];

    final found = buildTokenAlternatives(probs, body);

    expect(found, hasLength(kTokenAltsCap));
    expect(found.first.token, ' w0', reason: 'kept in reading order');
    expect(found.map((a) => a.token), isNot(contains(' w59')));
  });
}
