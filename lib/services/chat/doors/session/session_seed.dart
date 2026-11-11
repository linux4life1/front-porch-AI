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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';

import 'session_store.dart';

/// An imported chat's live state: the phase-0 seed of a fresh import, and
/// the `.fpchat` session head an export writes and an import puts back.
class SessionSeed {
  SessionSeed(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  SessionShellHooks get _h => _d.hooks;
  RealismScope get _scope => _s.realism();
  GroupChat? get _activeGroup => _session.activeGroup;
  CastDoor get _cast => _s.cast();
  RelationshipService get _relationshipService => _scope.relationship();
  NsfwService get _nsfwService => _scope.nsfw();
  TimeService get _timeService => _scope.time();
  NeedsSimulation get _needsSimulation => _scope.needs();
  ChaosModeService get _chaosModeService => _s.chaos();
  GroupRealismStore get _groupStore => _scope.groups;

  /// The chat's own Realism switch: seeded from the card, written to and
  /// read back from a package head.
  bool get _realismChatSwitch => _s.controls().chatRealism;
  set _realismChatSwitch(bool on) => _s.controls().setChatRealism(on);

  /// The chat's stored Needs switch: seeded and restored here, never a gate.
  bool get _needsSimEnabled => _scope.needsSimEnabled();
  set _needsSimEnabled(bool on) => _s.controls().needsSimEnabled = on;

  /// Full import seed: clear session lineage/guests/summary and reseed live
  /// Realism/Needs from the card/group so the save does not persist the
  /// previous open chat's bond/trust/arousal into the new row.
  ///
  /// Does **not** mark the chat new (the importer does after messages land).
  /// Does **not** call `ObjectiveWriter.importAuthoredTask` (card currentTask
  /// is for fresh chats).
  Future<void> seedImported() async {
    _cast.idle.cancelIdleTimer();

    _cast.idle.hasCompletedExchange = false;
    _cast.away.state.reset();
    _cast.greetings.greetingIndex = 0;

    _store.summary = '';
    // Caught-up blank journal for transcript-only imports; full packages
    // overwrite summary/cursor after this when restoring the suitcase.
    _store.summaryLastIndex = 0;
    _store.parentSessionId = null;
    _store.forkIndex = null;
    _store.selectedLooks.clear();
    _store.genSettings = ChatGenerationSettings();
    _s.prompts().budget.clear();
    _store.summaryPaused = false;
    _store.isSummaryGenerating = false;
    _s.graph().growthPassRunning = false;
    _s.objectives().resetForChatSwitch();
    final guests = _cast.guests;
    guests.state.ids.clear();
    guests.state.cards.clear();
    guests.state.pendingDeparture = null;
    guests.state.pendingPickerFilter = null;
    guests.resetActivityState();
    guests.state.turnsSinceCastScan = 0;
    guests.state.pendingDetection = null;
    guests.state.offeredOrIgnoredNames.clear();
    _s.sceneMoves.reset(); // Slice 6: stale offers die with the session too.

    final settings = _s.storage.realismSettings;
    if (_session.activeCharacter != null && _activeGroup == null) {
      final extSeed =
          _session.activeCharacter!.frontPorchExtensions ??
          FrontPorchExtensions();
      _realismChatSwitch = extSeed.realismEnabled || settings.realismDefault;
      _relationshipService.resetForFreshChat();
      _relationshipService.seedFromCardV2OrExt(
        shortTermBond: extSeed.shortTermBond,
        longTermBond: extSeed.longTermBond,
        trustLevel: extSeed.trustLevel,
      );
      _s.expression().resetForFreshChat();
      _s.lorebook().resetLorebookTriggerState();
      _timeService.seedFromV2OrExt(
        dayCount: extSeed.dayCount.clamp(1, 9999),
        timeOfDay: extSeed.timeOfDay,
        storyStartDate: extSeed.storyStartDate,
        storyStartTime: extSeed.storyStartTime,
      );
      _s.graph().applySeededPassageOfTime();
      _scope.setEmotion(extSeed.characterEmotion);
      _scope.setIntensity(extSeed.emotionIntensity);
      // seedFromV2OrExt only sets the *enabled* flag — runtime arousal and
      // cooldown are zeroed explicitly on every other fresh path
      // (startNewChat). Without this, ST/.json import bleeds them.
      _nsfwService.seedFromV2OrExt(
        nsfwCooldownEnabled: extSeed.afterglowEnabled,
      );
      _nsfwService.resetRuntimeArousalAndCooldown();
      _chaosModeService.seedFromGroupOrExt(
        extSeed.chaosModeEnabled || settings.chaosModeDefault,
        false,
      );
      _needsSimEnabled = _s.needsPass().seedNeedsSim(extSeed.needsSimChoice);
      _s.controls().objectivesEnabled = settings.objectivesEnabled;
      _s.controls().chatEnjoysLowHygiene = extSeed.enjoysLowHygiene;
      if (_needsSimEnabled) {
        _needsSimulation.initializeFreshWithDefaults({
          'hunger': extSeed.needsBaselineHunger,
          'bladder': extSeed.needsBaselineBladder,
          'energy': extSeed.needsBaselineEnergy,
          'social': extSeed.needsBaselineSocial,
          'fun': extSeed.needsBaselineFun,
          'hygiene': extSeed.needsBaselineHygiene,
          'comfort': extSeed.needsBaselineComfort,
        });
      } else {
        _needsSimulation.clearVector();
      }
      _needsSimulation.resetBuffers();
      // Bleed guard for the prior open chat. Suitcase put-back is in
      // [applyHead] — it must write even when this card authored Pockets
      // off (HIDES≠erase). Do not skip the null when restore is gated:
      // transcript-only import would keep the previous hidden kit.
      _s.graph().hostPockets = null;
    } else {
      _relationshipService.resetForFreshChat();
      _s.expression().resetForFreshChat();
      _timeService.resetForFreshChat();
      if (_activeGroup != null) {
        _groupStore.afterglowOn = groupAfterglowIn(
          _activeGroup!.defaultMemberRealismState,
        );
        final timeSeed = parseGroupTimeSeedOf(_activeGroup!);
        if (timeSeed != null) {
          _timeService.seedFromV2OrExt(
            dayCount: timeSeed.dayCount,
            timeOfDay: timeSeed.timeOfDay,
            storyStartDate: timeSeed.storyStartDate,
            storyStartTime: timeSeed.storyStartTime,
          );
          _s.graph().applySeededPassageOfTime();
        }
        _groupStore.members = parseGroupRealismSeeds(
          _activeGroup!.defaultMemberRealismState,
        ).map((k, v) => MapEntry(k, GroupMemberRealism.fromJson(v)));
        await _h.rekeyGroupStores();
        _chaosModeService.seedFromGroupOrExt(
          _activeGroup!.chaosModeEnabled || settings.chaosModeDefault,
          _activeGroup!.chaosNsfwEnabled,
        );
      }
      _nsfwService.resetForFreshChat();
      _s.lorebook().resetLorebookTriggerState();
      _needsSimEnabled = false;
      _s.controls().chatEnjoysLowHygiene = false;
      _needsSimulation.clearVector();
      _needsSimulation.resetBuffers();
      _s.graph().hostPockets = null;
      if (_activeGroup != null) {
        // The zeroing above is the right starting point for the no-group path
        // but was the FINAL word for a group: an imported group transcript
        // landed with Needs hard-off and saved false onto its new session row,
        // so the rest of that conversation had blank needs grids and no decay.
        // Re-derive from the member seeds exactly as fresh group entry and the
        // startNewChat group branch do (presence-inference: the creator omits
        // the per-member 'needs' sub-map when Needs was off in the wizard),
        // AND-gated by the Porch Life global like every other seed site.
        _needsSimEnabled =
            settings.needsSimDefault &&
            _groupStore.members.values.any((state) {
              final n = state.needs;
              return n != null && n.isNotEmpty;
            });
        if (_needsSimEnabled) {
          // Placeholder vector only — the first per-speaker
          // RealismDance.loadIntoScalars replaces it with that member's own
          // needs. Same flat baseline both group twins use.
          _needsSimulation.initializeFreshWithDefaults(const {
            'hunger': 80,
            'bladder': 80,
            'energy': 80,
            'social': 80,
            'fun': 80,
            'hygiene': 80,
            'comfort': 80,
          });
        }
      }
    }
    // v64: the import's third group seed site (group_entry, startNewChat's
    // group branch, and here) — a package whose member bags predate the
    // switch derives each member's once from this group's defaults, then
    // the stored value is law (docs/design/pockets-wardrobe-chat-toggle.md).
    _s.graph().seedGroupPocketsSwitches();
    _s.graph().seedPocketsFromCards();
    _s.growthStore().invalidate();
  }

  // ── Phase 1: session snapshot ───────────────────────────────────────────

  /// The scalars an `.fpchat` export writes as its `session` head.
  Map<String, dynamic> captureHead() {
    final pockets = _s.graph().hostPockets;
    final head = <String, dynamic>{
      'realism_enabled': _realismChatSwitch,
      'needs_sim_enabled': _scope.needsSimEnabled(),
      'pockets_enabled': _s.controls().pocketsChatSwitch,
      'enjoys_low_hygiene': _s.controls().chatEnjoysLowHygiene,
      'objectives_enabled': _s.controls().objectivesEnabled,
      'afterglow_enabled': _s.controls().afterglowChatSwitch,
      'summary': _store.summary,
      'summary_last_index': _store.summaryLastIndex,
      'affection_score': _relationshipService.affectionScore,
      'long_term_score': _relationshipService.longTermScore,
      'trust_level': _relationshipService.trustLevel,
      'relationship_tier': _relationshipService.relationshipTier,
      'long_term_tier': _relationshipService.longTermTier,
      'turns_since_long_term_check':
          _relationshipService.turnsSinceLongTermCheck,
      'short_term_deltas_summary': _relationshipService.shortTermDeltasSummary,
      // 1:1 only — captureCadenceAndFeelings is TURN PATH; group speakers
      // already ride group_realism_state (Opus b32789fd finding 3).
      if (_activeGroup == null)
        ..._relationshipService.captureCadenceAndFeelings(),
      'character_emotion': _scope.emotion(),
      'emotion_intensity': _scope.intensity(),
      'emotion_cause': _scope.cause(),
      'emotion_held_turns': _scope.heldTurns(),
      'active_fixation': _relationshipService.activeFixation,
      'fixation_lifespan': _relationshipService.fixationLifespan,
      'spatial_stance': _relationshipService.spatialStance,
      'arousal_level': _nsfwService.arousalLevel,
      'refractory_minutes_remaining': _nsfwService.refractoryMinutesRemaining,
      'refractory_minutes_total': _nsfwService.refractoryMinutesTotal,
      'refractory_opened': _nsfwService.refractoryOpened,
      if (_nsfwService.refractory.soft) 'refractory_soft': true,
      if (_nsfwService.refractory.peaks.isNotEmpty)
        'refractory_peaks': _nsfwService.refractory.peaks,
      if (_nsfwService.refractory.tail case final tail?) ...{
        'refractory_tail_minutes': tail.minutes,
        'refractory_tail_total': tail.total,
      },
      'time_of_day': _timeService.timeOfDay,
      'day_count': _timeService.dayCount,
      'start_day_of_week': _timeService.startDayOfWeekAnchor,
      'story_clock': _timeService.storyClockIso,
      'story_start_date': _timeService.storyStartDateIso,
      'chaos_mode_enabled': _chaosModeService.chaosModeEnabled,
      'chaos_pressure': _chaosModeService.chaosPressure,
      'chaos_nsfw_enabled': _chaosModeService.chaosNsfwEnabled,
      'needs_vector': Map<String, int>.from(_needsSimulation.vector),
      if (pockets != null) 'pockets': pockets.toJson(),
      if (_activeGroup != null)
        'group_realism_state': {
          for (final e in _groupStore.members.entries) e.key: e.value.toJson(),
        },
    };
    return head;
  }

  /// Puts a package's `session` head back onto the live scalars.
  Future<void> applyHead(Map<String, dynamic> head) async {
    if (head['realism_enabled'] is bool) {
      _realismChatSwitch = head['realism_enabled'] as bool;
    }
    if (head['needs_sim_enabled'] is bool) {
      _needsSimEnabled = head['needs_sim_enabled'] as bool;
    }
    if (head['enjoys_low_hygiene'] is bool) {
      _s.controls().chatEnjoysLowHygiene = head['enjoys_low_hygiene'] as bool;
    }
    if (head['objectives_enabled'] is bool) {
      _s.controls().objectivesEnabled = head['objectives_enabled'] as bool;
    }
    // v64: the imported chat's own 1:1 Pockets switch. Group switches ride
    // the per-member bag restored with group_realism_state, so this only
    // writes in 1:1; a package saved before it keeps the card's seed.
    if (head['pockets_enabled'] case final bool on) {
      if (_activeGroup == null) _s.controls().setChatPockets(on);
    }
    // The chat's own Afterglow switch, before the Lust it restores below. A
    // package saved before it has none and keeps the card's or group's.
    if (head['afterglow_enabled'] case final bool on) {
      if (_activeGroup == null) {
        _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: on);
      } else {
        _groupStore.afterglowOn = on;
      }
    }
    _store.summary = head['summary'] as String? ?? _store.summary;
    _store.summaryLastIndex =
        (head['summary_last_index'] as num?)?.toInt() ??
        _store.summaryLastIndex;

    final state = _headRealismState(head);
    if (head['story_clock'] != null || head['story_start_date'] != null) {
      _timeService.loadTimeScalars(
        timeOfDay: head['time_of_day'] as String? ?? _timeService.timeOfDay,
        dayCount: (head['day_count'] as num?)?.toInt() ?? _timeService.dayCount,
        startDayOfWeek:
            (head['start_day_of_week'] as num?)?.toInt() ??
            _timeService.startDayOfWeekAnchor,
        storyClock: head['story_clock'] as String?,
        storyStartDate: head['story_start_date'] as String?,
      );
    }
    if (state.isNotEmpty) {
      // Synthetic message to reuse restore path. Clock is the head
      // scalars above, then backfill + tip.after — not applyTipClock
      // alone, which would ignore an unstamped import.
      final synth = ChatMessage(
        text: '',
        sender: _session.activeCharacter?.name ?? '',
        isUser: false,
        metadata: {'realism_state': state},
      );
      // A carry: a package from a chat switched off brings its kept Lust.
      _nsfwService.carry(
        () => _s.graph().restores.fromMessage(synth, restoreClock: false),
      );
    }
    _s.clockWriter().syncLoadedSlotClocks();

    // 1:1 suitcase kit is captured from the raw host record (HIDES≠erase).
    // Phase-0 nulled it so the prior open chat cannot bleed; the gated
    // realism_state restore then refuses put-back when this card authored
    // Pockets off. Write the captured record anyway — restore, not invent.
    if (_activeGroup == null && head['pockets'] is Map) {
      final id = _session.activeCharacter != null
          ? _h.characterIdFor(_session.activeCharacter!)
          : '';
      if (id.isNotEmpty) {
        _s.graph().setPocketsFor(id, Pockets.fromJson(head['pockets']));
      }
    }

    if (head['chaos_mode_enabled'] is bool) {
      _chaosModeService.seedFromGroupOrExt(
        head['chaos_mode_enabled'] as bool,
        head['chaos_nsfw_enabled'] == true,
      );
    }
    final pressure = (head['chaos_pressure'] as num?)?.toInt();
    if (pressure != null) {
      _chaosModeService.setPressure(pressure.clamp(0, 100));
    }
    if (head['group_realism_state'] is Map && _activeGroup != null) {
      final raw = Map<String, dynamic>.from(head['group_realism_state'] as Map);
      _groupStore.members = {
        for (final e in raw.entries)
          if (e.value is Map)
            e.key: GroupMemberRealism.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
      };
      await _h.rekeyGroupStores();
    }
  }
}

/// A package head's scalars in a reply's `realism_state` shape, so the
/// restore path every rewind takes puts them back.
Map<String, dynamic> _headRealismState(
  Map<String, dynamic> head,
) => <String, dynamic>{
  if (head['affection_score'] != null)
    'affectionScore': head['affection_score'],
  if (head['long_term_score'] != null) 'longTermScore': head['long_term_score'],
  if (head['trust_level'] != null) 'trustLevel': head['trust_level'],
  if (head['relationship_tier'] != null)
    'relationshipTier': head['relationship_tier'],
  if (head['long_term_tier'] != null) 'longTermTier': head['long_term_tier'],
  if (head['turns_since_long_term_check'] != null)
    'turnsSinceLongTermCheck': head['turns_since_long_term_check'],
  if (head['short_term_deltas_summary'] != null)
    'shortTermDeltasSummary': head['short_term_deltas_summary'],
  if (head['turnsSinceDecayCheck'] != null)
    'turnsSinceDecayCheck': head['turnsSinceDecayCheck'],
  if (head['interCharacterRelationships'] is Map)
    'interCharacterRelationships': head['interCharacterRelationships'],
  if (head['character_emotion'] != null)
    'characterEmotion': head['character_emotion'],
  if (head['emotion_intensity'] != null)
    'emotionIntensity': head['emotion_intensity'],
  if (head['emotion_cause'] != null) 'emotionCause': head['emotion_cause'],
  if (head['emotion_held_turns'] != null)
    'emotionHeldTurns': head['emotion_held_turns'],
  if (head['active_fixation'] != null)
    'activeFixation': head['active_fixation'],
  if (head['fixation_lifespan'] != null)
    'fixationLifespan': head['fixation_lifespan'],
  if (head['spatial_stance'] != null) 'spatialStance': head['spatial_stance'],
  if (head['arousal_level'] != null) 'arousalLevel': head['arousal_level'],
  if (head['refractory_minutes_remaining'] != null)
    RefractoryKeys.minutes: head['refractory_minutes_remaining'],
  if (head['refractory_minutes_total'] != null)
    RefractoryKeys.total: head['refractory_minutes_total'],
  if (head['refractory_opened'] != null)
    RefractoryKeys.opened: head['refractory_opened'],
  // PR 3 soft gate: absent reads hard lock / no peaks, so files saved
  // before it restore exactly as they did.
  if (head['refractory_soft'] != null)
    RefractoryKeys.soft: head['refractory_soft'],
  if (head['refractory_peaks'] != null)
    RefractoryKeys.peaks: head['refractory_peaks'],
  // PR 4 warmth tail: the two head keys rebuild the nested body;
  // absent means no tail, so pre-tail files restore exactly as before.
  if (head['refractory_tail_minutes'] != null)
    RefractoryKeys.tail: {
      RefractoryKeys.minutes: head['refractory_tail_minutes'],
      RefractoryKeys.total:
          head['refractory_tail_total'] ?? head['refractory_tail_minutes'],
    },
  // Files saved before minutes: turns, read once as turns × 15.
  if (head['cooldown_turns_remaining'] != null)
    RefractoryKeys.legacyTurns: head['cooldown_turns_remaining'],
  if (head['cooldown_turns_total'] != null)
    RefractoryKeys.legacyTotal: head['cooldown_turns_total'],
  if (head['time_of_day'] != null) 'timeOfDay': head['time_of_day'],
  if (head['day_count'] != null) 'dayCount': head['day_count'],
  if (head['start_day_of_week'] != null)
    'startDayOfWeek': head['start_day_of_week'],
  if (head['story_clock'] != null) 'storyClock': head['story_clock'],
  if (head['story_start_date'] != null)
    'storyStartDate': head['story_start_date'],
  if (head['pockets'] is Map) 'pockets': head['pockets'],
  if (head['needs_vector'] is Map)
    'needs': {
      'vector': Map<String, int>.from(
        (head['needs_vector'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
      ),
    },
};
