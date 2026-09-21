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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'speaker_resolution.dart';

/// Pockets & Wardrobe fragment — what the speaker is wearing and carrying,
/// told to the model every turn.
///
/// This is the half that makes the record worth keeping. An inventory nobody
/// reads is a database; injected, it is the difference between a character who
/// is still holding the keys they picked up forty messages ago and one who is
/// mysteriously empty-handed the moment the prose scrolled away.
///
/// Gated by the caller on the Pockets switch alone — no Realism, no Needs, no
/// Journal, no Objectives. That independence is the settled ruling, not an
/// accident, and it is the reason this leaf takes no engine callbacks: there is
/// nothing here for a second switch to gate.
///
/// Per-speaker in groups via the shared [SpeakerCardResolver], the same
/// resolution every other identity fragment uses, so a group member is
/// described with THEIR pockets rather than whoever happens to be active.
class InventoryInjection with SpeakerCardResolver {
  @override
  final bool Function() getIsGroupNonObserverMode;
  @override
  final String Function() getCurrentSpeakerIdForRealism;
  @override
  final List<CharacterCard> Function() getGroupCharacters;
  @override
  final String Function(CharacterCard) getCharacterIdFromCard;
  @override
  final CharacterCard? Function() getActiveCharacter;

  /// The speaker's record for THIS chat, by the same character id the rest of
  /// the per-speaker state uses.
  final Pockets? Function(String characterId) getPockets;

  /// Current story day — filters set-aside clothing (expired overnight per
  /// the 2026-08-11 ruling) without mutating the record from a build path.
  final int Function() getCurrentDay;

  /// One-shot reactions to items the USER hand-added from the panel — a gift
  /// they accept knowingly, or a conjured thing they are surprised by (the
  /// Easter egg). GET-AND-MARK: the wiring flags returned intros as included
  /// so the turn after the reaction drops them; a regen rebuild returns the
  /// same list again (still queued), which is what makes the reaction
  /// reproducible. Section is where the item LANDED (gifts land in hands).
  final List<({String item, bool gift, PocketSection section})> Function(
    String characterId,
  )
  takePendingIntros;

  /// Who handed the gift over — named so the model attributes it correctly.
  final String Function() getUserName;

  /// No-op defaults so the many direct test constructions (and any caller
  /// that has no hand-add surface) stay source-compatible — additive change.
  static List<({String item, bool gift, PocketSection section})> _noIntros(
    String _,
  ) => const [];
  static String _defaultUserName() => 'The user';

  InventoryInjection({
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    required this.getActiveCharacter,
    required this.getPockets,
    required this.getCurrentDay,
    this.takePendingIntros = _noIntros,
    this.getUserName = _defaultUserName,
  });

  /// Hard ceiling on the fragment, so a scene that accumulated a lot of clutter
  /// cannot quietly eat the context budget. The per-list caps in pockets.dart
  /// already bound the count; this bounds the characters. (Raised from 320
  /// when the set-aside sentence joined — three lists, same principle.)
  static const maxChars = 440;

  String buildInventoryInjection() {
    final card = speakerCard();
    if (card == null) return '';
    final p = getPockets(getCharacterIdFromCard(card));
    if (p == null || p.isEmpty) return '';

    final parts = [
      if (p.worn.isNotEmpty)
        'wearing ${p.worn.map((i) => i.display).join(', ')}',
      if (p.carrying.isNotEmpty)
        'carrying ${p.carrying.map((i) => i.display).join(', ')}',
    ];
    // Fact, not instruction, and deliberately non-committal about what they
    // do next: "set aside nearby" lets the model have them pull the same
    // clothes back on after the shower OR reach for something else — never
    // "they should re-dress in X".
    final aside = p.setAsideOn(getCurrentDay());

    final sentences = [
      if (parts.isNotEmpty) '${card.name} is ${parts.join('; ')}.',
      if (aside.isNotEmpty)
        'Set aside nearby, still ${card.name}\'s: '
            '${aside.map((e) => e.item.display).join(', ')}.',
    ];
    if (sentences.isEmpty) return '';

    // Stated as fact rather than instruction. "Keep this consistent" invites a
    // model to narrate an inventory check; naming what they have lets it simply
    // be true, which is what the feature is for.
    final out = sentences.join(' ');
    return out.length <= maxChars ? out : '${out.substring(0, maxChars)}…';
  }

  /// One-shot directives for items the USER hand-added — its OWN plan
  /// section, injected at the TAIL of the prompt with the Chance Time class
  /// of one-shot events, NOT inside the record fragment above.
  ///
  /// It lived inside [buildInventoryInjection] first, and the maintainer's
  /// report was immediate (2026-08-13): "silently adding an item ... did not
  /// make them surprised." The record fragment rides the realism-state
  /// block — mid-prompt, one background fact among a dozen — and models
  /// read it as description, not as something to DO this reply. The blocks
  /// that reliably drive a reply (Chance Time, Porch Night) all sit after
  /// the suffix at maximum recency, phrased as bracketed directives; this
  /// follows them. Get-and-mark and the per-session filter are unchanged —
  /// only the address and the imperative phrasing moved.
  String buildItemIntroInjection() {
    final card = speakerCard();
    if (card == null) return '';
    final intros = takePendingIntros(getCharacterIdFromCard(card));
    if (intros.isEmpty) return '';
    return [
      for (final n in intros)
        n.gift
            ? '[This reply: ${getUserName()} has just handed ${card.name} '
                  '${n.item} — they accept it in-scene, knowing it came '
                  'from ${getUserName()}.]'
            : '[This reply: ${card.name} just now notices ${n.item} '
                  '${switch (n.section) {
                    PocketSection.worn => 'on their person',
                    PocketSection.carrying => 'among their things',
                    PocketSection.setAside => 'sitting nearby',
                  }} '
                  'and has NO memory of how it got there. Before anything '
                  'else, they react with genuine surprise ("how did I end '
                  'up with ${n.item}?").]',
    ].join('\n');
  }
}
