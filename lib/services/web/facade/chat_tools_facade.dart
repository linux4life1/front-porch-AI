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
import 'package:front_porch_ai/services/story/faithful_mode.dart';
import 'package:front_porch_ai/services/web/facade/journal_web_surface.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

part 'chat_tools_facade.memory.dart';
part 'chat_tools_facade.scene.dart';
part 'chat_tools_facade.switches.dart';
part 'chat_tools_facade.objectives.dart';
part 'chat_tools_facade.pockets.dart';

/// Thin adapter for the chat *tools* sidebar — the memory/summary/chaos/NSFW/
/// scene-time/objective sections the desktop shows beside a chat. Every read is
/// a pure getter and every mutation delegates to the existing [ChatService]/
/// [StorageService] methods the desktop sidebar calls, so 1:1↔group parity and
/// the simulation behavior are inherited (never reimplemented here).
class ChatToolsFacade {
  ChatToolsFacade(
    this._chat,
    this._storage,
    this._hub, {
    StoryRepository? storyRepo,
    UserPersonaService? personas,
  }) : _storyRepo = storyRepo,
       _personas = personas;

  final ChatService _chat;
  final StorageService _storage;
  final StreamHub? _hub;

  /// Living Time §4 story-from-chat deps. Optional; the endpoint 400s without.
  final StoryRepository? _storyRepo;
  final UserPersonaService? _personas;

  /// Full tools snapshot mirroring the desktop sidebar (focus-scoped).
  Map<String, dynamic> state({String? participantId}) {
    final chaos = _chat.chaosModeService;
    final nsfw = _chat.nsfwService;
    final time = _chat.timeService;
    final rs = _storage.realismSettings;
    final mem = _storage.memorySettings;
    final clockRunning = StoryClock.isRunning(
      passageOfTimeEnabled: time.passageOfTimeEnabled,
      realismEnabled: _chat.realismEnabled,
      standaloneClockEnabled: rs.standaloneClockEnabled,
    );
    final weather = _chat.currentWeather;
    final focused = _focusedParticipant(participantId);
    final focusedCard = focused?.card ?? _chat.activeCharacter;
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
      },
      'nsfw': {
        'cooldownEnabled': _chat.activeGroup != null
            ? _chat.isGroupNsfwEnabled
            : nsfw.nsfwCooldownEnabled,
        'cooldownTurnsRemaining': nsfw.cooldownTurnsRemaining,
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
      // Standing Mood — the same string the desktop sidebar puts under the
      // portrait, from the same getter, so the two can never disagree about
      // what they walked in carrying. '' when the feature is off or the day is
      // unremarkable.
      'standingMood': _chat.standingMoodSummary,
      'ambitions':
          focusedCard == null ||
              (focused?.isLite ?? false) ||
              !_chat.objectivesActive
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
              !_chat.pocketsFeatureEnabled ||
              _isGuestFocus(focused)
          ? null
          : (_chat.pocketsFor(_chat.characterIdFor(focusedCard)) ?? Pockets())
                .toJsonOn(_chat.storyDayCount),
      'time': {
        'timeOfDay': time.timeOfDay,
        'dayCount': time.dayCount,
        'weekday': time.narrativeWeekday,
        'passageEnabled': time.passageOfTimeEnabled,
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
        'presence': _presenceWord(),
        'todaySentence': _chat.todaySentence,
      },
      // Objectives are per-character; scope to the focused participant (lite
      // guests have none). getObjectivesForGroupCharacter returns the global
      // list in 1:1, so this is correct in both modes.
      'objectives': _objectivesBlock(
        (focused?.isLite ?? false) ? null : focusedCard,
      ),
      // Group-only settings (turn order / director / prompts), gated below.
      'group': _groupBlock(),
    };
  }

  /// The focused cast participant, or null when none/unknown.
  ChatParticipant? _focusedParticipant(String? id) {
    if (id == null) return null;
    for (final p in _chat.cast) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// A focused Scene Guest (1:1 non-host cast entry). Guests carry NO pockets
  /// record — but the 1:1 record accessors ignore the character id (there is
  /// only `_pockets`, the host's), so a guest-focused pocket surface would
  /// silently read AND WRITE the host's kit under the guest's name (hostile
  /// self-review, 2026-08-13; the ✕ had the same hole). In a group every
  /// participant is a real member, so this is 1:1-only by construction.
  bool _isGuestFocus(ChatParticipant? focused) =>
      focused != null && !focused.isHost && !_chat.isGroupMode;

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
    return {
      'enabled': _chat.objectivesActive,
      'primary': _objJson(primary),
      'secondary': secondary.map(_objJson).whereType<Map>().toList(),
      'isChecking': _chat.isCheckingCompletion,
    };
  }

  /// Group-only settings for the sidebar's group section (null in 1:1). The web
  /// gates this block on `group != null`. Per-member prompt overrides are keyed
  /// by stableGroupId (== ChatParticipant.id).
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
    return {
      'id': o.id,
      'objective': o.objective,
      'isPrimary': o.isPrimary,
      'checkFrequency': o.checkFrequency,
      'tasks': _chat.tasksForObjective(o),
      // The ambition this quest is a step toward (schema v46). Additive and
      // nullable — older web bundles ignore the key, and every objective
      // created before v46 legitimately has none.
      'servedAmbition': o.servedAmbition,
    };
  }

  /// Apply any subset of the global memory/summary numeric+text settings. Keys
  /// mirror the [state] `memory`/`summary` blocks; absent keys are unchanged.
  Future<void> applySettings(Map<String, dynamic> f) async {
    Future<void> ifBool(String k, Future<void> Function(bool) set) async {
      if (f[k] is bool) await set(f[k] as bool);
    }

    Future<void> ifInt(String k, Future<void> Function(int) set) async {
      final v = f[k];
      if (v is int) await set(v);
    }

    final mem = _storage.memorySettings;
    await ifBool('ragEnabled', mem.setRagEnabled);
    await ifInt('ragRetrievalCount', mem.setRagRetrievalCount);
    await ifInt('ragWindowSize', mem.setRagWindowSize);
    await ifBool('journalEnabled', mem.setJournalEnabled);
    await ifInt('journalInterval', mem.setJournalInterval);
    await ifInt('journalMaxCards', mem.setJournalMaxCards);
    await ifBool('journalReviewFirst', mem.setJournalReviewFirst);
    await ifBool(
      'importLlmertaPorchMemories',
      mem.setImportLlmertaPorchMemories,
    );
    await ifBool('growthEnabled', mem.setCharacterEvolutionEnabled);
    await ifInt('growthInterval', mem.setGrowthInterval);
    await ifBool('growthReviewFirst', mem.setGrowthReviewFirst);
    _notify();
  }

  /// Web Journal diary (audit P2.12) — Growth twin for cards + review-first.
  JournalWebSurface get journalWeb => JournalWebSurface(
    chat: _chat,
    storage: _storage,
    notify: _notify,
    resolveOwner: _growthOwner,
  );

  void _notify() => _hub?.broadcastChatUpdate();
}
