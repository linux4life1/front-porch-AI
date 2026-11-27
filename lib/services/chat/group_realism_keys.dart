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

// Split out of group_member_realism.dart (which re-exports it, so every
// importer keeps working) when Heat's key would have taken that file over
// the 500-line cap. Moved verbatim apart from [GroupRealismKeys.heat].

import 'package:front_porch_ai/services/chat/refractory.dart';

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

  /// The user marked this member Away by hand. The model cannot bring them
  /// back; only the user's Back clears it.
  static const awayHeld = 'awayHeld';
  static const relationshipTier = 'relationshipTier';
  static const longTermTier = 'longTermTier';
  static const turnsSinceLongTermCheck = 'turnsSinceLongTermCheck';
  static const shortTermDeltasSummary = 'shortTermDeltasSummary';
  static const turnsSinceDecayCheck = 'turnsSinceDecayCheck';
  static const trustRepairPending = 'trustRepairPending';
  static const arousal = 'arousal'; // historical: snapshots say arousalLevel

  /// Heat, closeness to release (docs/design/heat-meter.md). Snapshots say
  /// `heatLevel`; the member bag says `heat`, beside `arousal`. Absent on a
  /// member saved before Heat, which reads 0.
  static const heat = 'heat';
  static const nsfwCooldownEnabled = 'nsfwCooldownEnabled';
  static const refractoryMinutesRemaining = RefractoryKeys.minutes;
  static const refractoryMinutesTotal = RefractoryKeys.total;
  static const refractoryOpened = RefractoryKeys.opened;

  /// PR 3 soft gate — the window kind and this hour's peak stamps.
  static const refractorySoft = RefractoryKeys.soft;
  static const refractoryPeaks = RefractoryKeys.peaks;

  /// PR 4 warmth tail — the nested body, frozen until the outer one ends.
  static const refractoryTail = RefractoryKeys.tail;

  /// Saved before the refractory counted minutes; read once as turns × 15.
  static const legacyCooldownTurnsRemaining = RefractoryKeys.legacyTurns;
  static const legacyCooldownTurnsTotal = RefractoryKeys.legacyTotal;
  static const emotion = 'emotion';
  static const emotionIntensity = 'emotionIntensity';

  /// Why the mood is what it is, and how many judge passes have kept it
  /// (docs/design/mood-with-bite.md). Absent on a member saved before them.
  static const emotionCause = 'emotionCause';
  static const emotionHeldTurns = 'emotionHeldTurns';
  static const needs = 'needs';

  /// Fractions of a point the clock has charged this member but not yet
  /// taken (see needsWearForSpan). Not a key the needs-enabled inference reads.
  static const needsWearCarry = 'needsWearCarry';

  /// Pockets & Wardrobe (docs/design/pockets-and-preferences.md Part 1). Rides
  /// this per-member bag rather than earning a schema migration: the record is
  /// strictly session-scoped, so living in the session's own state blob means
  /// it is deleted with the chat by construction rather than by a cleanup job.
  static const pockets = 'pockets';

  /// This member's own Pockets switch in THIS chat
  /// (docs/design/pockets-wardrobe-chat-toggle.md). Absent means the chat
  /// predates the per-chat switch or was never seeded: readers fall back to
  /// the card default, and the entry seed writes the derived value once.
  /// Like [pockets], deliberately absent from [runtime] — only the typed
  /// accessor may touch it.
  static const pocketsSwitch = 'pockets_switch';

  /// This member's own Realism, Needs, Afterglow and Objectives switches in
  /// THIS chat (docs/design/one-chat-ux.md PR 3), the Pockets shape: absent
  /// means never set, and the reader falls back to the chat's older switch
  /// (Afterglow: the group's switch AND the member copy's flag), so a chat
  /// saved before them behaves exactly as it did. Outside [runtime] for the
  /// same reason as [pocketsSwitch]: only the typed accessors touch them.
  static const realismSwitch = 'realism_switch';
  static const needsSwitch = 'needs_switch';
  static const afterglowSwitch = 'afterglow_switch';
  static const objectivesSwitch = 'objectives_switch';

  /// This member's own Boons & Bogies participation in THIS chat (spec
  /// ruling 18): the sidebar's mid-chat opt-out. Same shape as
  /// [realismSwitch] — absent means never seeded, and the seed writes it
  /// once from the member card's own default (or the chat's switch), so an
  /// existing group enters with every member exactly as the global had
  /// them. Off hides and holds: rings stay visible and injectable, but no
  /// fade, advance, roll or proposal runs for this member, and off never
  /// deletes.
  static const bbSwitch = 'bb_switch';

  /// This member's own Chaos Mode in THIS chat (docs/design/
  /// chaos-per-character.md, PR 5b). Same shape as [realismSwitch]: absent
  /// means never seeded, and the entry seed writes it once from the card
  /// OR the group's old switch, so an existing group enters with every
  /// member as the group switch had them. The pressure, cooldown, pending
  /// event and delivered flag ride here too — the bag is the member's
  /// whole chaos state, persisted with the chat by the paths that already
  /// save this blob. Deliberately outside [runtime]: only the typed
  /// accessors below touch them.
  static const chaosSwitch = 'chaos_switch';
  static const chaosNsfwSwitch = 'chaos_nsfw';
  static const chaosPressure = 'chaos_pressure';
  static const chaosCooldown = 'chaos_cooldown';
  static const chaosPendingEvent = 'chaos_pending_event';
  static const chaosEventDelivered = 'chaos_delivered';
  static const relationships = 'relationships';

  /// Everything the generic bridges (`GroupMemberRealism.valueFor` /
  /// `GroupMemberRealism.setValue`) are allowed to touch. The leaf services'
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
    heat,
    nsfwCooldownEnabled,
    refractoryMinutesRemaining,
    refractoryMinutesTotal,
    refractoryOpened,
    refractorySoft,
    refractoryPeaks,
    refractoryTail,
    legacyCooldownTurnsRemaining,
    legacyCooldownTurnsTotal,
    emotion,
    emotionIntensity,
    emotionCause,
    emotionHeldTurns,
    needs,
    relationships,
  };
}
