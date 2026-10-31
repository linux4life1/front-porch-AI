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

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_context.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_scene.dart';

/// The chat tools sidebar snapshot (focus-scoped), read straight off the
/// live chat and storage the desktop sidebar reads.
class ChatToolsSnapshot {
  ChatToolsSnapshot(this._ctx, this._scene);

  final ChatToolsContext _ctx;
  final ChatToolsScene _scene;
  ChatService get _chat => _ctx.chat;
  StorageService get _storage => _ctx.storage;

  /// Full tools snapshot mirroring the desktop sidebar (focus-scoped).
  Map<String, dynamic> build({String? participantId}) {
    final chaos = _chat.chaosModeService;
    final nsfw = _chat.nsfwService;
    final time = _chat.timeService;
    final rs = _storage.realismSettings;
    final mem = _storage.memorySettings;
    final clockRunning = StoryClock.isRunning(
      passageOfTimeEnabled: rs.passageOfTimeDefault,
    );
    final weather = _chat.currentWeather;
    final focused = _ctx.focusedParticipant(participantId);
    // Unfocused, the panel speaks for the host or the first member, as the
    // phone's header does; a group has no active character.
    final owner = _ctx.growthOwner(participantId);
    final focusedCard = owner?.card ?? _chat.activeCharacter;
    final ownerIsLite = owner?.isLite ?? false;
    final focusedIsMember =
        focused != null && !focused.isHost && focused.realismEnabled;
    return {
      'wikiBaseUrl': _chat.wikiBaseUrl,
      'wikiSavedUrls': _storage.webSearchSettings.savedWikiUrls,
      'realismEnabled': _chat.realismEnabled,
      'needsEnabled': _chat.needsSimEnabled,
      'realismOneShotEval': rs.realismOneShotEval,
      'realismOneShotMode': rs.oneShotMode.name,
      'focusedId': focused?.id,
      'memory': {
        'ragEnabled': mem.ragEnabled,
        'ragRetrievalCount': mem.ragRetrievalCount,
        'ragWindowSize': mem.ragWindowSize,
        // The last reply's retrieval receipt (rag_injection.dart wire
        // shape) — the same anti-black-box surface the desktop sidebar
        // shows. Additive + nullable per the API compatibility rules.
        'lastRagReceipt': _chat.lastRagReceipt,
        // Embedding-engine status (desktop RagEngineCard parity). Model
        // download only runs on the host desktop; web surfaces progress
        // and tells the user to use desktop if setup is needed.
        'embedding': _chat.memoryService?.embeddingService.statusSnapshot,
        'journalEnabled': mem.journalEnabled,
        'journalInterval': mem.journalInterval,
        'journalReviewFirst': mem.journalReviewFirst,
        'importLlmertaPorchMemories': mem.importLlmertaPorchMemories,
        'growthEnabled': mem.characterEvolutionEnabled,
        'growthInterval': mem.growthInterval,
        'growthReviewFirst': mem.growthReviewFirst,
      },
      // Kept under the 'summary' key for the bundled web UI: this is the
      // Journal's per-chat recap ("Where we are") — same ChatService surface
      // as before (text/paused/isGenerating/lastIndex).
      'summary': {
        'text': _chat.summary,
        'paused': _chat.summaryPaused,
        'isGenerating': _chat.isSummaryGenerating,
        'lastIndex': _chat.summaryLastIndex,
      },
      'chaos': {
        'enabled': chaos.chaosModeEnabled,
        'nsfwEnabled': chaos.chaosNsfwEnabled,
        'pressure': chaos.chaosPressure,
        'hasPendingEvent': chaos.hasPendingChaosEvent,
        // Additive: the spicy row shows only with 18+ themes on, and the
        // hint reads the Porch Life frequency and any cooldown.
        'adultAllowed': chaos.adultAllowed,
        'base': chaos.frequency.base,
        'growth': chaos.frequency.growth,
        'cooldownTurns': chaos.cooldownTurns,
      },
      'nsfw': {
        // The live gate: Porch Life (with 18+) allows Afterglow AND this
        // chat's own switch is on. The phone shows the switch while Porch
        // Life allows it, and Lust and recovery while the gate is on.
        'cooldownEnabled': nsfw.nsfwCooldownEnabled,
        'afterglowAllowed': rs.afterglowEnabled,
        'afterglowSwitch': _chat.afterglowChatSwitch,
        // The desktop chip's own words, ready-made, so the phone cannot
        // drift from them (story minutes, or replies with the clock off).
        'refractoryMinutesRemaining': nsfw.refractoryMinutesRemaining,
        'refractoryClockRunning': nsfw.clockRunning,
        'refractoryLabel': nsfw.refractoryWords.chip,
        // Arousal is per-character: scope to the focused member in a group;
        // the host scalar otherwise. (Tier name is only derivable for the host
        // scalar, so members show the raw level.)
        'arousalLevel': focusedIsMember
            ? _chat.getArousalForGroupCharacter(focusedCard!)
            : nsfw.arousalLevel,
        'arousalTier': focusedIsMember ? '' : nsfw.arousalTierName,
      },
      // Ambitions (Living Time §6) for the focused participant — additive;
      // same ChatService.ambitionsFor merge the desktop sidebar reads.
      // Objectives off ⇒ empty, matching the desktop sidebar row: quest
      // completion is the only thing that moves progress, so the web would
      // otherwise show a stage word frozen for the life of the chat.
      'ambitions': focusedCard == null || ownerIsLite || !_chat.objectivesActive
          ? const []
          : () {
              // The quest climbing each ambition (v46) — the same
              // AmbitionService merge the desktop sidebar row uses, over the
              // same accessor, so web and desktop cannot disagree about which
              // step belongs to which mountain. Computed once per block
              // rather than per ambition.
              final steps = AmbitionService.activeStepsFrom(
                _chat.getObjectivesForGroupCharacter(focusedCard),
              );
              return [
                for (final a in _chat.ambitionsFor(focusedCard))
                  {
                    'text': a.text,
                    'progress': a.progress,
                    'stage': AmbitionService.stageWord(a.progress),
                    // Additive + nullable: older bundles ignore it.
                    'step': steps[a.text],
                  },
              ];
            }(),
      // Pockets & Wardrobe for the focused participant. Same record and same
      // per-character resolution the desktop sidebar reads, so the two
      // surfaces cannot disagree about what they are holding. Absent (null)
      // when the switch is off or nothing is focused, so the web panel
      // vanishes rather than going stale. Feature ON with no record sends an
      // EMPTY record instead of null (2026-08-13, add-by-hand parity): the
      // panel must render its add row so the FIRST item can be added — the
      // same off-absent / on-even-when-empty gate the desktop sidebar got.
      // toJsonOn, not toJson: set-aside clothing expired by the story day,
      // so the PWA never shows yesterday's outfit in the window before the
      // next pass rewrites the stored record.
      'pockets':
          focusedCard == null ||
              !_chat.pocketsEnabledFor(_chat.characterIdFor(focusedCard)) ||
              _ctx.isGuestFocus(focused)
          ? null
          : (_chat.pocketsFor(_chat.characterIdFor(focusedCard)) ?? Pockets())
                .toJsonOn(_chat.storyDayCount),
      'time': {
        'timeOfDay': time.timeOfDay,
        'dayCount': time.dayCount,
        'weekday': time.narrativeWeekday,
        'passageEnabled': rs.passageOfTimeDefault,
        'clockRunning': clockRunning,
        'weather': weather == null
            ? null
            : {
                'condition': weather.condition.name,
                'temp': weather.temp.name,
                'season': seasonDisplayName(
                  weather.season,
                  _chat.activeChatBiome.seasonLabels,
                ),
                'label': switch (_chat.currentSegmentWeather) {
                  final seg? => skinnedChipLabel(
                    seg,
                    _chat.activeChatBiome,
                    fahrenheit: rs.weatherFahrenheit,
                  ),
                  null => WeatherEngine.label(weather),
                },
                'emoji': switch (_chat.currentSegmentWeather) {
                  final seg? => skinnedEmoji(
                    _chat.activeChatBiome,
                    seg.condition,
                  ),
                  null => skinnedEmoji(
                    _chat.activeChatBiome,
                    weather.condition,
                  ),
                },
                'segment': _chat.currentSegmentWeather?.segment.name,
                'segmentCondition': _chat.currentSegmentWeather?.condition.name,
                'tempC': _chat.currentSegmentWeather?.tempC,
                'tempF': switch (_chat.currentSegmentWeather?.tempC) {
                  null => null,
                  final c => WeatherSegments.tempF(c),
                },
                'unit': rs.weatherFahrenheit ? 'f' : 'c',
                'dayLabel': WeatherEngine.label(weather),
                'tomorrow': switch (_chat.upcomingWeather) {
                  null => null,
                  final n => {
                    'condition': n.condition.name,
                    'temp': n.temp.name,
                    'season': seasonDisplayName(
                      n.season,
                      _chat.activeChatBiome.seasonLabels,
                    ),
                    'label': WeatherEngine.label(n),
                    'emoji': WeatherEngine.emoji(n.condition),
                  },
                },
              },
        // Story Calendar (story-calendar.md) — additive; older web bundles
        // simply ignore these.
        'clock': time.displayClock,
        'date': time.displayShortDate,
        'dateLong': time.displayDate,
        'storyClock': time.storyClockIso,
        'storyStartDate': time.storyStartDateIso,
        'presence': _scene.presenceWord(),
        'todaySentence': _chat.todaySentence,
      },
      // Objectives are per-character; scope to the focused participant (lite
      // guests have none). getObjectivesForGroupCharacter returns the global
      // list in 1:1, so this is correct in both modes.
      'objectives': _objectivesBlock(ownerIsLite ? null : focusedCard),
      // Group-only settings (turn order / director / prompts), gated below.
      'group': _groupBlock(),
    };
  }

  /// Objectives block for [card] (split primary/secondary). Empty when null.
  Map<String, dynamic> _objectivesBlock(CharacterCard? card) {
    if (card == null) {
      return {
        'primary': null,
        'secondary': const [],
        'isChecking': _chat.isCheckingCompletion,
        'enabled': _chat.objectivesActive,
      };
    }
    Objective? primary;
    final secondary = <Objective>[];
    for (final o in _chat.getObjectivesForGroupCharacter(card)) {
      if (o.isPrimary && primary == null) {
        primary = o;
      } else {
        secondary.add(o);
      }
    }
    // "3 landed · 1 let go" for the character whose goals are loaded; empty
    // for anyone else and before anything has ended. Additive.
    final tally = _chat.objectiveTally;
    return {
      'enabled': _chat.objectivesActive,
      'primary': _objJson(primary),
      'secondary': secondary.map(_objJson).whereType<Map>().toList(),
      'isChecking': _chat.isCheckingCompletion,
      'tally': tally.charId == _chat.characterIdFor(card) ? tally.label : '',
    };
  }

  /// Group-only settings for the sidebar's group section (null in 1:1). The web
  /// gates this block on `group != null`. Per-member prompt overrides are keyed
  /// by [groupMemberStoreId] (== ChatParticipant.id).
  Map<String, dynamic>? _groupBlock() {
    final g = _chat.activeGroup;
    if (g == null) return null;
    return {
      'name': g.name,
      'turnOrder': g.turnOrder.name,
      'directorMode': _chat.observerMode,
      'systemPrompt': g.systemPrompt,
      'scenario': g.scenario,
      'firstMessage': g.firstMessage,
      'alternateGreetings': g.alternateGreetings,
      'greetingSeeds': [for (final s in g.greetingSeeds) s?.toFields()],
      'members': _chat.cast
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'prompt': g.characterSystemPrompts[p.id] ?? '',
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic>? _objJson(Objective? o) {
    if (o == null) return null;
    final tasks = _chat.tasksForObjective(o);
    // Stale steps stay on the list so the UI can mark them skipped. They are
    // excluded from current-step / completion counts (never a 100% win).
    return {
      'id': o.id,
      'objective': o.objective,
      'isPrimary': o.isPrimary,
      'checkFrequency': o.checkFrequency,
      'tasks': tasks,
      'completedCount': completedQuestTaskCount(tasks),
      'countableCount': countableQuestTaskCount(tasks),
      // The ambition this quest is a step toward (schema v46). Additive and
      // nullable — older web bundles ignore the key, and every objective
      // created before v46 legitimately has none.
      'servedAmbition': o.servedAmbition,
      // v58 (objectives-that-keep-up.md): set aside by the goal sync, and
      // who the goal is from. Additive; older bundles ignore both.
      'dormant': objectiveIsDormant(o),
      'origin': objectiveOrigin(o),
    };
  }
}
