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
