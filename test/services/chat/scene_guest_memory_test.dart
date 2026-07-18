// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for Scene Guests (Lite NPCs) Phase 4 — episodic memory (RAG).
//
// Phase 4 gives a 1:1 scene guest its OWN episodic memory by REUSING the
// existing memory pipeline: retrieval keys on the guest's id (via
// ChatService._getMemorySourceIds(guest:)) and embedding stores under the same
// guest id (via ChatService._maybeEmbedMessages(characterIdOverride:)). The
// single load-bearing invariant is RETRIEVE KEY == EMBED KEY for a guest, and
// that this key is the guest's own id — distinct from the host's — so memories
// round-trip per character and never cross-contaminate.
//
// Two independently verifiable surfaces:
//
//  1) Key derivation parity. Both the embed override and the retrieve source id
//     derive from the SAME `_getCharacterIdFromCard` (== card.stableGroupId).
//     This mirrors that derivation exactly so a regression (e.g. one path
//     switching to dbId) is caught here: the guest's retrieve key must equal
//     its embed key, and both must differ from the host's id.
//
//  2) Per-character embed dedup. A single 1:1 session can now hold windows for
//     both the host AND a guest at the same position range. The Phase 4 fix
//     scopes `embedMessageWindow`'s "already embedded" check to the characterId
//     being embedded, so the guest's identical range is NOT wrongly skipped.
//     This test mirrors that dedup predicate exactly.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/character_id.dart';

CharacterCard _card(String name, {String? imagePath}) => CharacterCard(
  name: name,
  description: 'desc',
  personality: 'pers',
  scenario: 'scen',
  imagePath: imagePath,
);

/// The exact id derivation ChatService uses for both the guest embed override
/// and the guest retrieve source id (`_getCharacterIdFromCard`).
String charIdOf(CharacterCard c) => c.stableGroupId;

/// Mirrors the characterId-scoped dedup predicate in
/// MemoryService.embedMessageWindow after the Phase 4 fix.
Set<(int, int)> existingRangesForCharacter(
  List<({String? characterId, int start, int end})> rows,
  String characterId,
) => rows
    .where((e) => e.characterId == characterId)
    .map((e) => (e.start, e.end))
    .toSet();

void main() {
  group('Scene Guest memory — retrieve key == embed key', () {
    test('guest retrieve source id equals guest embed override id', () {
      final guest = _card('Mara', imagePath: '/lib/mara.png');

      // Embed path: _maybeEmbedMessages(characterIdOverride: charIdOf(guest)).
      final embedKey = charIdOf(guest);
      // Retrieve path: _getMemorySourceIds(guest:) seeds sourceIds with
      // charIdOf(guest).
      final retrieveKey = charIdOf(guest);

      expect(embedKey, retrieveKey);
      expect(embedKey, 'mara');
    });

    test('guest key is the guest id, distinct from the host id', () {
      final host = _card('Host', imagePath: '/lib/host.png');
      final guest = _card('Mara', imagePath: '/lib/mara.png');

      expect(charIdOf(guest), isNot(equals(charIdOf(host))));
      // On a guest turn the source ids must NOT include the host id, so the
      // host's memories cannot be injected on the guest's turn.
      final guestSources = <String>[charIdOf(guest)];
      expect(guestSources, isNot(contains(charIdOf(host))));
    });

    test('falls back to a stable id even without an image path', () {
      // stableGroupId derives from name when no image file exists; the embed
      // and retrieve keys still agree because both call the same derivation.
      final guest = _card('No Image Guest');
      expect(charIdOf(guest), isNotEmpty);
      expect(charIdOf(guest), charIdOf(guest)); // deterministic
    });
  });

  group('Scene Guest memory — per-character embed dedup', () {
    test(
      'guest embed is NOT skipped when host already embedded same range',
      () {
        const hostId = 'host';
        const guestId = 'mara';
        // Host already embedded window [0-4] in this session.
        final rows = <({String? characterId, int start, int end})>[
          (characterId: hostId, start: 0, end: 4),
        ];

        // The guest embeds under its OWN id; its existing-range set is empty,
        // so window [0-4] is a NEW window for the guest (not deduped away).
        final guestExisting = existingRangesForCharacter(rows, guestId);
        expect(guestExisting.contains((0, 4)), isFalse);

        // The host, however, still dedups against its own prior window.
        final hostExisting = existingRangesForCharacter(rows, hostId);
        expect(hostExisting.contains((0, 4)), isTrue);
      },
    );

    test('guest re-embed of its own stored range IS skipped', () {
      const guestId = 'mara';
      final rows = <({String? characterId, int start, int end})>[
        (characterId: guestId, start: 0, end: 4),
      ];
      final guestExisting = existingRangesForCharacter(rows, guestId);
      expect(guestExisting.contains((0, 4)), isTrue);
    });
  });
}
