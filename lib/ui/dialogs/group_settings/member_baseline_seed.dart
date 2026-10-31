// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/chat/chat.dart';

/// The two pure halves of the Group Settings → Realism per-member baseline
/// editor: what the Bond/Trust sliders RELOAD as, and what a slider edit WRITES
/// into the group's per-member seed blob.
///
/// They live outside the widget because the widget itself has no unit seam —
/// every ChatService door the tab uses (`getBaselineSeedForGroupCharacter`,
/// `persistGroupMemberExtensions`, `resetRealismForGroupCharacter`) is an *extension*
/// member, so it resolves on the static type and runs its real body (reaching
/// private ChatService fields) even against a test double. These functions are
/// where the two bugs actually lived, and here they are testable.

/// The Long-Term Bond value to show for a member, or null when nothing has ever
/// been authored for them.
///
/// [baselineSeed] is `ChatService.getBaselineSeedForGroupCharacter` — which
/// builds its result from a literal that has NO `longTermScore` key, so it can
/// only ever answer null here. [perCharSeed] is the member's entry in
/// `GroupChat.defaultMemberRealismState.perChar`, the blob the engine itself
/// seeds a fresh chat from; `longTermBond` is the card-ext name an earlier
/// build of this editor wrote there instead of the engine's name.
int? longTermBondFromSeeds({
  Map<String, dynamic>? baselineSeed,
  Map<String, dynamic>? perCharSeed,
}) =>
    _int(baselineSeed, GroupRealismKeys.longTermScore) ??
    _int(perCharSeed, GroupRealismKeys.longTermScore) ??
    _int(perCharSeed, 'longTermBond');

/// Defensive read, matching [GroupMemberRealism]: a hand-edited export or a
/// foreign writer can put any shape in these blobs, and a wrong type must read
/// as ABSENT rather than throw inside the dialog's initState.
int? _int(Map<String, dynamic>? map, String key) {
  final v = map?[key];
  return v is num ? v.toInt() : null;
}

/// The three relationship sliders' load values for one member, already clamped
/// to their slider ranges.
typedef MemberBondBaseline = ({int shortTerm, int longTerm, int trust});

/// What Short-Term Bond / Long-Term Bond / Trust Level should reload as.
///
/// The three keys the engine actually reads are affection / longTermScore /
/// trust. Long-Term Bond used to LOAD from 'trust' and, worse, SAVE into it —
/// so dragging a ±300 bond slider overwrote the ±100 trust baseline while Trust
/// Level never persisted at all. When nothing has ever been authored,
/// longTermScore falls back to affection, matching what RelationshipService
/// does when it seeds a member that predates the key.
///
/// REPAIR for groups edited under that old code: they have a ±300 bond number
/// sitting in the ±100 trust field, which reaches a Slider declared
/// min -100 / max 100 and asserts, taking the whole Group Settings dialog down.
/// |trust| > 100 is impossible for a real trust value, so when the baseline
/// blob also has no 'longTermScore' the number can only have come from that
/// slider: move it back where it belongs and give trust its default. The old
/// code never stored a real trust value, so there is none to recover, and
/// inventing one from a bond score would be worse. The repair deliberately
/// reads the BASELINE blob only — widening it to the perChar seed would change
/// which groups it fires on.
MemberBondBaseline bondBaselineFromSeeds({
  required Map<String, dynamic> baselineSeed,
  Map<String, dynamic>? perCharSeed,
}) {
  final rawTrust = _int(baselineSeed, GroupRealismKeys.trust);
  final rawLongTerm = _int(baselineSeed, GroupRealismKeys.longTermScore);
  final poisoned =
      rawLongTerm == null && rawTrust != null && rawTrust.abs() > 100;
  final affection = _int(baselineSeed, GroupRealismKeys.affection) ?? 50;
  final stored = longTermBondFromSeeds(
    baselineSeed: baselineSeed,
    perCharSeed: perCharSeed,
  );

  return (
    shortTerm: affection.clamp(-300, 300),
    longTerm: (poisoned ? rawTrust : stored ?? affection).clamp(-300, 300),
    trust: (poisoned ? 50 : rawTrust ?? 50).clamp(-100, 100),
  );
}

/// The card-ext field names an earlier build of this editor wrote into the
/// per-member seed. The engine reads none of them.
const legacyCardExtSeedKeys = [
  'shortTermBond',
  'longTermBond',
  'trustLevel',
  'characterEmotion',
];

/// Writes one member's authored baseline into [seed] (their `perChar` entry)
/// under the keys the engine actually reads, and drops the dead card-ext-named
/// copies so the blob cannot disagree with itself. Returns [seed] for chaining.
Map<String, dynamic> applyBaselineToMemberSeed(
  Map<String, dynamic> seed, {
  required int affection,
  required int longTermScore,
  required int trust,
  required String emotion,
  required String emotionIntensity,
}) {
  seed[GroupRealismKeys.affection] = affection;
  seed[GroupRealismKeys.longTermScore] = longTermScore;
  seed[GroupRealismKeys.trust] = trust;
  seed[GroupRealismKeys.emotion] = emotion;
  seed[GroupRealismKeys.emotionIntensity] = emotionIntensity;
  for (final dead in legacyCardExtSeedKeys) {
    seed.remove(dead);
  }
  return seed;
}

/// What the new-group wizard's and Edit group's Relationship sliders show for
/// one member's seed (`defaultMemberRealismState.perChar`, the blob a new
/// chat seeds from). Long-Term Bond reads the engine's `longTermScore` and,
/// unset, follows Short-Term Bond, which is what the engine reads on a
/// member's first entry. Both editors used to save Long-Term Bond into
/// `trust`; a seed left with a number past ±100 in that field and no
/// `longTermScore` shows the number as Long-Term Bond and trust 50, the
/// default Group Settings' own repair gives it (see [bondSliderEdit]). A
/// Long-Term Bond within ±100 saved that way cannot be told from a trust.
MemberBondBaseline bondSlidersFromMemberSeed(Map<String, dynamic> seed) {
  final affection = _int(seed, GroupRealismKeys.affection) ?? 35;
  final longTerm = _int(seed, GroupRealismKeys.longTermScore);
  final trust = _int(seed, GroupRealismKeys.trust);
  final mixedUp = _longTermInTrust(seed);
  return (
    shortTerm: affection.clamp(-300, 300),
    longTerm: (longTerm ?? (mixedUp ? trust! : affection)).clamp(-300, 300),
    trust: (mixedUp ? 50 : trust ?? 40).clamp(-100, 100),
  );
}

/// The seed keys one Relationship slider move writes: the moved slider's own
/// key, or, on a seed where Long-Term Bond went into `trust`, all three as
/// [bondSlidersFromMemberSeed] showed them, so the seed then says what the
/// sliders did.
Map<String, int> bondSliderEdit(
  Map<String, dynamic> seed, {
  int? shortTerm,
  int? longTerm,
  int? trust,
}) {
  if (!_longTermInTrust(seed)) {
    return {
      GroupRealismKeys.affection: ?shortTerm,
      GroupRealismKeys.longTermScore: ?longTerm,
      GroupRealismKeys.trust: ?trust,
    };
  }
  final shown = bondSlidersFromMemberSeed(seed);
  return {
    GroupRealismKeys.affection: shortTerm ?? shown.shortTerm,
    GroupRealismKeys.longTermScore: longTerm ?? shown.longTerm,
    GroupRealismKeys.trust: trust ?? shown.trust,
  };
}

/// No `longTermScore` and a trust no real trust can be: the old editors'
/// Long-Term Bond, saved in the wrong key.
bool _longTermInTrust(Map<String, dynamic> seed) {
  final trust = _int(seed, GroupRealismKeys.trust);
  return _int(seed, GroupRealismKeys.longTermScore) == null &&
      trust != null &&
      trust.abs() > 100;
}

/// The engine's mood strengths, the same three every other realism editor
/// offers.
const emotionIntensities = ['mild', 'moderate', 'strong'];

/// The strength the tab's dropdown shows for a stored [value]. An earlier
/// build of this tab offered `calm` / `intense` and saved them; those read
/// as their engine twins. Anything else outside the list reads as
/// `moderate`, as a missing value always has: a dropdown handed a value
/// that is not one of its items fails its assertion and the tab does not
/// draw.
String emotionIntensityFromSeed(Object? value) => switch (value) {
  'calm' => 'mild',
  'intense' => 'strong',
  final String s when emotionIntensities.contains(s) => s,
  _ => 'moderate',
};
