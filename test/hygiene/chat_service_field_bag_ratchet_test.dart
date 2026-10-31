// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The ChatService god object only ever shrinks. Every part of the shell is an
// extension that reads and writes one shared pool of state: the instance
// fields of the `ChatServiceFieldBag` mixin
// (lib/services/chat/chat_service_fields.dart) and of the `ChatService` class
// body (lib/services/chat_service.dart), `late final` ones included. The
// decomposition (docs/design/chat-service-decomposition.md) moves that state
// into doors that own it; this ratchet is how each package proves it did.
//
// It counts those fields (getters, setters and methods are not fields; one
// declaration of `String? a, b;` is two) and compares the total with
// test/baselines/chat_service_fields.json:
//   1. More fields than the baseline fails: new state goes in the door that
//      owns its domain, or a leaf class under lib/services/chat/, never in
//      the shared bag.
//   2. Fewer fields than the baseline also fails until the baseline is
//      lowered in the same change, so a freed slot cannot be refilled.
//
// With FPAI_TIGHTEN_BASELINES=1 the baseline is lowered to the tree (never
// raised). Any baseline edit needs the maintainer's approved-test-change
// label. WP11 deletes the bag, and this ratchet with it.
//
// The member scanner is shared with chat_service_api_manifest_test.dart,
// which holds its fixture tests.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';
import 'chat_service_api_manifest_test.dart'
    show
        DartDeclaration,
        MemberKind,
        chatServiceClass,
        chatServiceLibrary,
        kChatServiceShell;

const _baselinePath = 'test/baselines/chat_service_fields.json';
const _bag = 'ChatServiceFieldBag';

/// Every instance field of the bag and of the class body, as ratchet hits.
Map<String, List<RatchetHit>> _fields() {
  final shell = chatServiceLibrary();
  final bag =
      shell.find('mixin', _bag) ??
      (throw StateError(
        'mixin $_bag is not declared in the $kChatServiceShell library. If '
        'the bag is gone (WP11), delete this ratchet and its baseline too.',
      ));
  List<RatchetHit> instanceFields(DartDeclaration d) => [
    for (final m in d.members)
      if (m.kind == MemberKind.field && !m.isStatic)
        RatchetHit(d.source.path, m.line, m.line, 0, m.name, m.name),
  ];
  return {
    '$_bag (${bag.source.path})': instanceFields(bag),
    'ChatService class body ($kChatServiceShell)': instanceFields(
      chatServiceClass(shell),
    ),
  };
}

void main() {
  test('ChatService fields only ever shrink', () {
    final baseline = readBaseline(_baselinePath);
    expect(baseline.keys, [
      kChatServiceShell,
    ], reason: '$_baselinePath holds one count, keyed by the shell library');
    final byDeclaration = _fields();
    final fields = [for (final hits in byDeclaration.values) ...hits];
    tightenBaselineIfAsked(_baselinePath, baseline, {
      kChatServiceShell: fields,
    });
    // Re-read: a tightening run leaves the baseline at the tree and passes.
    final allowed = readBaseline(_baselinePath)[kChatServiceShell] ?? 0;
    final now = fields.length;
    final breakdown = [
      for (final MapEntry(:key, :value) in byDeclaration.entries)
        '  $key: ${value.length}',
    ].join('\n');
    if (now > allowed) {
      fail(
        'ChatService has $now instance fields; $_baselinePath allows '
        '$allowed.\n$breakdown\n'
        'New state does not go in the shared bag or the shell: put it in the '
        'door that owns its domain, or a leaf class under lib/services/chat/ '
        'with explicit inputs (docs/design/chat-service-decomposition.md).',
      );
    }
    if (now < allowed) {
      fail(
        'ChatService shrank: $allowed -> $now instance fields. Good. Now '
        'lower $_baselinePath to $now in this same change (or run with '
        'FPAI_TIGHTEN_BASELINES=1), so the freed slot cannot be refilled.\n'
        '$breakdown',
      );
    }
  });
}
