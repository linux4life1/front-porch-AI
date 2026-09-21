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

/// One group member's realism state — U7 of the realism audit.
///
/// `_groupRealism` was `Map<String, Map<String, dynamic>>`: ~19 runtime keys
/// as bare strings, read through scattered `as num?`/`as String?` casts in a
/// dozen files, persisted in three places (the sessions column's `perChar`,
/// the group's `defaultMemberRealismState`, and Group Card exports). Every
/// map-resident bug this audit fixed — the unrewound inter-character
/// feelings, the unrewound decay cadence, the decorative `_moodDecayCounter`
/// — lived in the gap between those strings and the code that meant to read
/// them.
///
/// THE DESIGN IS A WRAPPER, DELIBERATELY. This class owns the raw map and
/// exposes typed accessors; it does not explode the map into fields. That is
/// what makes it safe to ship without a data migration:
///
///  * **The wire format is unchanged by construction.** [toJson] returns the
///    live backing map — same keys, same shapes, same three persistence
///    paths. Old builds read new data and vice versa.
///  * **Absence stays absent.** Keys exist only once written, so every
///    presence-based inference keeps working — most critically "a member
///    slot carrying a `needs` map is what flags Needs enabled for the
///    group". A field-per-key class with defaults would have silently
///    switched that on for every needs-off group. All typed getters are
///    therefore NULLABLE (absent → null) and every call site keeps its own
///    default, exactly as the old `?? defaultValue` casts did.
///  * **Unknown keys ride through verbatim.** A live slot carries ~22
///    config/seed keys (needsBaseline*/needsDecay*/verification*/…) beside
///    the runtime state, and imports may carry keys this build has never
///    heard of. They are simply left in the map.
///
/// The wiring E2E (`integration_test/group_realism_wiring_test.dart`) pins
/// all three properties against a live app, and the wire-format unit test
/// pins fromJson→toJson identity on a full 41-key slot.
library;

import 'package:front_porch_ai/services/chat/pockets.dart';

/// The runtime keys the engine reads and writes each turn. Every name that
/// used to be scattered as a string literal across chat_service parts lives
/// here and only here.
abstract final class GroupRealismKeys {
  static const affection = 'affection';
  static const longTermScore = 'longTermScore';
  static const trust = 'trust';
  static const fixation = 'fixation';
  static const fixationLifespan = 'fixationLifespan';
  static const spatialStance = 'spatialStance';
  static const withUser = 'withUser';
  static const relationshipTier = 'relationshipTier';
  static const longTermTier = 'longTermTier';
  static const turnsSinceLongTermCheck = 'turnsSinceLongTermCheck';
  static const shortTermDeltasSummary = 'shortTermDeltasSummary';
  static const turnsSinceDecayCheck = 'turnsSinceDecayCheck';
  static const trustRepairPending = 'trustRepairPending';
  static const arousal = 'arousal'; // historical: snapshots say arousalLevel
  static const nsfwCooldownEnabled = 'nsfwCooldownEnabled';
  static const cooldownTurnsRemaining = 'cooldownTurnsRemaining';
  static const cooldownTurnsTotal = 'cooldownTurnsTotal';
  static const emotion = 'emotion';
  static const emotionIntensity = 'emotionIntensity';
  static const needs = 'needs';

  /// Pockets & Wardrobe (docs/design/pockets-and-preferences.md Part 1). Rides
  /// this per-member bag rather than earning a schema migration: the record is
  /// strictly session-scoped, so living in the session's own state blob means
  /// it is deleted with the chat by construction rather than by a cleanup job.
  static const pockets = 'pockets';
  static const relationships = 'relationships';

  /// Everything the generic bridges ([GroupMemberRealism.valueFor] /
  /// [GroupMemberRealism.setValue]) are allowed to touch. The leaf services'
  /// callback signatures predate the typed wrapper and pass key strings; the
  /// debug assert keeps any NEW stringly access from creeping back in.
  static const runtime = {
    affection,
    longTermScore,
    trust,
    fixation,
    fixationLifespan,
    spatialStance,
    withUser,
    relationshipTier,
    longTermTier,
    turnsSinceLongTermCheck,
    shortTermDeltasSummary,
    turnsSinceDecayCheck,
    trustRepairPending,
    arousal,
    nsfwCooldownEnabled,
    cooldownTurnsRemaining,
    cooldownTurnsTotal,
    emotion,
    emotionIntensity,
    needs,
    relationships,
  };
}

class GroupMemberRealism {
  GroupMemberRealism() : _data = <String, dynamic>{};

  /// Wraps a JSON-decoded slot. Deep-copies recursively so later writes never
  /// alias the decoder's internal structures at ANY depth — the known member
  /// shape nests one level (needs/relationships), but unknown pass-through
  /// keys from imports may nest deeper (Grok review finding, 2026-08-03).
  GroupMemberRealism.fromJson(Map<dynamic, dynamic> raw)
    : _data = _deepCopy(raw);

  static Map<String, dynamic> _deepCopy(
    Map<dynamic, dynamic> src,
  ) => <String, dynamic>{
    for (final e in src.entries)
      e.key.toString(): e.value is Map
          ? _deepCopy(e.value as Map)
          : (e.value is List ? List<dynamic>.from(e.value as List) : e.value),
  };

  final Map<String, dynamic> _data;

  /// The live backing map — the exact bytes every persistence path stores.
  /// Deliberately NOT a copy: the sessions save serializes the live state at
  /// encode time, exactly as it did when `_groupRealism` held raw maps.
  Map<String, dynamic> toJson() => _data;

  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;

  // Defensive reads: a hand-edited export or a foreign writer can put any
  // shape here. Wrong types read as ABSENT, never as a crash mid-turn.
  int? _int(String k) {
    final v = _data[k];
    return v is num ? v.toInt() : null;
  }

  String? _string(String k) {
    final v = _data[k];
    return v is String ? v : null;
  }

  bool? _bool(String k) {
    final v = _data[k];
    return v is bool ? v : null;
  }

  // ── Relationship scalars ──────────────────────────────────────────────
  int? get affection => _int(GroupRealismKeys.affection);
  set affection(int? v) => _data[GroupRealismKeys.affection] = v;
  int? get longTermScore => _int(GroupRealismKeys.longTermScore);
  set longTermScore(int? v) => _data[GroupRealismKeys.longTermScore] = v;
  int? get trust => _int(GroupRealismKeys.trust);
  set trust(int? v) => _data[GroupRealismKeys.trust] = v;
  String? get fixation => _string(GroupRealismKeys.fixation);
  set fixation(String? v) => _data[GroupRealismKeys.fixation] = v;
  int? get fixationLifespan => _int(GroupRealismKeys.fixationLifespan);
  set fixationLifespan(int? v) => _data[GroupRealismKeys.fixationLifespan] = v;
  String? get spatialStance => _string(GroupRealismKeys.spatialStance);
  set spatialStance(String? v) => _data[GroupRealismKeys.spatialStance] = v;
  bool? get withUser => _bool(GroupRealismKeys.withUser);
  set withUser(bool? v) {
    if (v == null) {
      _data.remove(GroupRealismKeys.withUser);
    } else {
      _data[GroupRealismKeys.withUser] = v;
    }
  }

  int? get relationshipTier => _int(GroupRealismKeys.relationshipTier);
  set relationshipTier(int? v) => _data[GroupRealismKeys.relationshipTier] = v;
  int? get longTermTier => _int(GroupRealismKeys.longTermTier);
  set longTermTier(int? v) => _data[GroupRealismKeys.longTermTier] = v;
  bool? get trustRepairPending => _bool(GroupRealismKeys.trustRepairPending);
  set trustRepairPending(bool? v) =>
      _data[GroupRealismKeys.trustRepairPending] = v;

  // ── NSFW scalars (see the historical 'arousal' key note above) ───────
  int? get arousal => _int(GroupRealismKeys.arousal);
  set arousal(int? v) => _data[GroupRealismKeys.arousal] = v;
  bool? get nsfwCooldownEnabled => _bool(GroupRealismKeys.nsfwCooldownEnabled);
  set nsfwCooldownEnabled(bool? v) =>
      _data[GroupRealismKeys.nsfwCooldownEnabled] = v;
  int? get cooldownTurnsRemaining =>
      _int(GroupRealismKeys.cooldownTurnsRemaining);
  set cooldownTurnsRemaining(int? v) =>
      _data[GroupRealismKeys.cooldownTurnsRemaining] = v;
  int? get cooldownTurnsTotal => _int(GroupRealismKeys.cooldownTurnsTotal);
  set cooldownTurnsTotal(int? v) =>
      _data[GroupRealismKeys.cooldownTurnsTotal] = v;

  // ── Emotion ───────────────────────────────────────────────────────────
  String? get emotion => _string(GroupRealismKeys.emotion);
  set emotion(String? v) => _data[GroupRealismKeys.emotion] = v;
  String? get emotionIntensity => _string(GroupRealismKeys.emotionIntensity);
  set emotionIntensity(String? v) =>
      _data[GroupRealismKeys.emotionIntensity] = v;

  // ── Structured members ────────────────────────────────────────────────
  /// Raw needs vector, coerced, or null when the slot has never carried one —
  /// and that null is load-bearing (needs-enabled inference; see class doc).
  /// Parsed-record cache. The getter used to run [Pockets.fromJson] on EVERY
  /// read — and the sidebar and member cards read it from `build`, which
  /// reruns per streamed token per visible card: JSON deserialization as
  /// per-frame work, the coverImageFileFor lesson in miniature (hostile
  /// review 2026-08-11). Coherent by construction: the typed setter below is
  /// the ONLY writer of this key ('pockets' is deliberately absent from
  /// [GroupRealismKeys.runtime], so the generic setValue bridge cannot touch
  /// it), and fromJson builds a fresh instance whose cache starts cold.
  /// The cached object is the LIVE record — every mutation path already ends
  /// with the setter (the "no second write path" invariant).
  Pockets? _pocketsCache;

  /// What this member is wearing and carrying. Absent (not empty) when the
  /// feature has never run for them, so an untouched member serialises exactly
  /// as they did before Pockets existed.
  Pockets? get pockets {
    final cached = _pocketsCache;
    if (cached != null) return cached;
    final v = _data[GroupRealismKeys.pockets];
    return v is Map ? _pocketsCache = Pockets.fromJson(v) : null;
  }

  set pockets(Pockets? v) {
    // An EMPTY record is stored, not removed. Removing it made absence and
    // emptiness the same thing, and the seed path reads absence as "never
    // promoted from the card" — so a character who dropped everything had their
    // whole starting wardrobe reappear next turn, permanently. They could never
    // end a scene empty-handed. (Grok, 2026-08-07.) Only an explicit null —
    // meaning "this member has no record at all" — clears the slot, which is
    // what keeps an untouched member serialising exactly as before.
    _pocketsCache = v;
    if (v == null) {
      _data.remove(GroupRealismKeys.pockets);
    } else {
      _data[GroupRealismKeys.pockets] = v.toJson();
    }
  }

  Map<String, int>? get needs => _intMap(GroupRealismKeys.needs);
  set needs(Map<String, int>? v) => _data[GroupRealismKeys.needs] = v;

  Map<String, int>? get relationships =>
      _intMap(GroupRealismKeys.relationships);
  set relationships(Map<String, int>? v) =>
      _data[GroupRealismKeys.relationships] = v;

  Map<String, int>? _intMap(String key) {
    final raw = _data[key];
    if (raw is! Map) return null;
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (v is num) out[k.toString()] = v.toInt();
    });
    return out;
  }

  // ── Generic bridges for the pre-wrapper leaf-service callbacks ───────
  // (NsfwService's get/setGroupValue and RelationshipService's counter pair
  // pass key strings; their constructor signatures are pinned by tests.)
  dynamic valueFor(String key) {
    assert(
      GroupRealismKeys.runtime.contains(key),
      'unknown group-realism key "$key" — add it to GroupRealismKeys '
      'instead of reviving stringly access',
    );
    return _data[key];
  }

  void setValue(String key, dynamic v) {
    assert(
      GroupRealismKeys.runtime.contains(key),
      'unknown group-realism key "$key" — add it to GroupRealismKeys '
      'instead of reviving stringly access',
    );
    _data[key] = v;
  }
}
