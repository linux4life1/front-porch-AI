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

/// Boons & Bogies card kit — `extensions.front_porch.realism_engine.traitKit`
/// (docs/design/boons-and-bogies.md §4).
///
/// One entry is a boon or bogey the author wants this character to start
/// with: `{kind, text, tier, pinned, linkedTo?}`. Identity, like ambitions:
/// it travels with the card, exports, imports, and goes through Stoop
/// review. Seeding is a COPY, not a link — the first Growth touch turns
/// each entry into a ring at the tier's strength, and each chat grows
/// apart from there.
///
/// Lives in its own leaf because [FrontPorchExtensions] sits at the 500-line
/// cap; the model layer must not depend on chat service leaves, so the
/// entry shape and its budget live here, and `BoonsBogies.kMaxKitEntries`
/// mirrors [TraitKitEntry.maxEntries] rather than the other way round.
library;

/// One boon or bogey on a card kit.
class TraitKitEntry {
  const TraitKitEntry({
    required this.kind,
    required this.text,
    this.tier = tierEmerging,
    this.pinned = false,
    this.linkedTo,
  });

  static const String kindBoon = 'boon';
  static const String kindBogey = 'bogey';
  static const String tierEmerging = 'emerging';
  static const String tierDeveloping = 'developing';
  static const String tierEstablished = 'established';

  /// Combined boons + bogies per card, on a budget separate from the 12
  /// story rings (ruling 11). Parsing truncates to this so a hand-edited
  /// or Stoop card can never smuggle a bigger kit past the editors.
  static const int maxEntries = 6;

  /// Longest accepted entry text; longer text is truncated at parse, not
  /// dropped — the story idea survives a copy-paste.
  static const int maxTextChars = 160;

  /// [kindBoon] or [kindBogey]; anything else is dropped at parse.
  final String kind;

  /// What the trait is, in the author's words. Non-blank by construction.
  final String text;

  /// [tierEmerging], [tierDeveloping] or [tierEstablished] — the strength
  /// the seeded ring starts at (0.30 / 0.60 / 0.80, §4).
  final String tier;

  /// Seeded rings from this entry start pinned, so the author's core flaw
  /// cannot fade in the first thirty turns. Pinned does not block the
  /// accepted overcome path. Defaults: bogey true, boon false.
  final bool pinned;

  /// Text of the boon this bogey pushes against (phase 7 link; carried
  /// through the card untouched until then).
  final String? linkedTo;

  bool get isBogey => kind == kindBogey;

  /// The kit tier's display name in the ladder vocabulary (ruling 2: the
  /// user sees Novice / Skilled / Master, never the physics names). A seed
  /// tier is not a rung you can hold — the established seed lands at
  /// strength 0.80 with the advance floor ONE pass short of the Master
  /// milestone (ruling 8: Master is always asked, never seeded) — hence
  /// "Master-bound", not "Master". Every user-facing surface (kit editor,
  /// Stoop tile) names the tier through here; the wire value stays
  /// emerging/developing/established (§4).
  String get seedTierName => switch (tier) {
    tierDeveloping => 'Skilled',
    tierEstablished => 'Master-bound',
    _ => 'Novice',
  };

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'text': text,
    'tier': tier,
    'pinned': pinned,
    if (linkedTo != null) 'linkedTo': linkedTo,
  };

  /// Written only when the card carries a kit, so pre-feature cards stay
  /// byte-identical through a re-save (the additive-key doctrine in
  /// `front_porch_extensions_codec.dart`).
  static Object? encode(List<TraitKitEntry> kit) =>
      kit.isEmpty ? null : [for (final e in kit) e.toJson()];

  /// Fail-soft like `_phrases`: a card can arrive from ANYWHERE, so a wrong
  /// type yields an empty kit, an entry with an unknown `kind` or a blank
  /// `text` is dropped, and a bad `tier` falls back to emerging (the
  /// weakest, safest start). The count is truncated, never thrown away.
  static List<TraitKitEntry> parse(Object? raw) {
    if (raw is! List) return const [];
    final kit = <TraitKitEntry>[];
    for (final v in raw) {
      if (kit.length >= maxEntries) break;
      if (v is! Map) continue;
      final kind = '${v['kind']}'.trim().toLowerCase();
      if (kind != kindBoon && kind != kindBogey) continue;
      var text = v['text'] is String ? (v['text'] as String).trim() : '';
      if (text.isEmpty) continue;
      if (text.length > maxTextChars) text = text.substring(0, maxTextChars);
      final rawTier = '${v['tier']}'.trim().toLowerCase();
      final tier = rawTier == tierDeveloping || rawTier == tierEstablished
          ? rawTier
          : tierEmerging;
      final linked = v['linkedTo'] is String
          ? (v['linkedTo'] as String).trim()
          : '';
      kit.add(
        TraitKitEntry(
          kind: kind,
          text: text,
          tier: tier,
          pinned: v['pinned'] is bool ? v['pinned'] as bool : kind == kindBogey,
          linkedTo: linked.isEmpty ? null : linked,
        ),
      );
    }
    return List.unmodifiable(kit);
  }

  /// Display label for the kind chip (editors and Stoop share it).
  String get kindLabel => isBogey ? 'Bogey' : 'Boon';
}
