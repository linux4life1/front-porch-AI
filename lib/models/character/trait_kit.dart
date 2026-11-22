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
  const TraitKitEntry._raw({
    required this.kind,
    required this.text,
    required this.tier,
    required this.pinned,
    this.linkedTo,
  });

  /// The one clamp for the seed cap (ruling 8, amended 2026-11-21): a kit
  /// seeds at Skilled at most, so an `established` tier — the over-strong
  /// seed a pre-cap card may carry — steps down to [tierDeveloping] HERE.
  /// Editors, Stoop tiles and the seed math then never see a tier that
  /// would "seed a Master", which the MD forbids: Master is where the
  /// story asks, never where a card asserts.
  factory TraitKitEntry({
    required String kind,
    required String text,
    String tier = tierEmerging,
    bool pinned = false,
    String? linkedTo,
  }) => TraitKitEntry._raw(
    kind: kind,
    text: text,
    tier: tier == tierEstablished ? tierDeveloping : tier,
    pinned: pinned,
    linkedTo: linkedTo,
  );

  static const String kindBoon = 'boon';
  static const String kindBogey = 'bogey';
  static const String tierEmerging = 'emerging';
  static const String tierDeveloping = 'developing';

  /// Read-off name, kept so unparsed or legacy card JSON that says
  /// "established" still round-trips through [parse]; constructing an entry
  /// with it clamps to [tierDeveloping] (seed cap, ruling 8).
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

  /// [tierEmerging] or [tierDeveloping] — the strength the seeded ring
  /// starts at (0.30 / 0.60). The third wire tier, `established`, is a
  /// pre-cap shape: the factory clamps it here to `developing` (seed cap,
  /// ruling 8 amended 2026-11-21).
  final String tier;

  /// Whether a seeded ring from this entry starts pinned. Tier-aware
  /// (ruling, 2026-11-21): a Skilled bogey defaults to pinned so the
  /// author's earned flaw cannot fade in the first thirty turns; a
  /// Novice bogey defaults unpinned, fragile as authored. An explicit
  /// choice — checkbox or card key — always wins. Pinned does not block
  /// the accepted overcome path. Boons default unpinned.
  final bool pinned;

  /// Text of the boon this bogey pushes against (phase 7 link; carried
  /// through the card untouched until then).
  final String? linkedTo;

  bool get isBogey => kind == kindBogey;

  /// The kit tier's display name in the ladder vocabulary (ruling 2), under
  /// the seed cap (ruling 8, amended 2026-11-21): a kit can only start at
  /// Novice or Skilled — Master is never seeded, it is where the story asks
  /// and the user answers. The `established` wire value predates the cap
  /// and reads as Skilled here, matching the factory's clamp; there is no
  /// display name for it anymore. Every user-facing surface (kit editor,
  /// Stoop tile, creator review) names the tier through here; the wire
  /// value stays on the §4 vocabulary. Mirrored in web by
  /// `SEED_TIER_NAMES` (realismTypes.ts).
  static String seedTierNameFor(String tier) => switch (tier) {
    tierDeveloping => 'Skilled',
    tierEstablished => 'Skilled',
    _ => 'Novice',
  };

  String get seedTierName => seedTierNameFor(tier);

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
  /// weakest, safest start). A pre-cap `established` tier arrives, survives
  /// this line, and is clamped to developing by the constructor — the seed
  /// cap lives in ONE place. The count is truncated, never thrown away.
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
          // Default pin is tier-aware (ruling, 2026-11-21): a Skilled
          // bogey arrives pinned — the author means it and it must not
          // evaporate in the first thirty turns; a Novice bogey arrives
          // as authored, fragile, unpinned. An explicit `pinned` in the
          // card is the author's veto and always wins. `tier` here is
          // pre-clamp, so `established` (Skilled's pre-cap spelling)
          // counts as Skilled.
          pinned: v['pinned'] is bool
              ? v['pinned'] as bool
              : kind == kindBogey && tier != tierEmerging,
          linkedTo: linked.isEmpty ? null : linked,
        ),
      );
    }
    return List.unmodifiable(kit);
  }

  /// Display label for the kind chip (editors and Stoop share it).
  String get kindLabel => isBogey ? 'Bogey' : 'Boon';
}
