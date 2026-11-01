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
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/chat_lore.dart';
import 'package:front_porch_ai/services/chat/doors/realism/chat_places.dart';
import 'package:front_porch_ai/services/chat/doors/realism/chat_weather.dart';
import 'package:front_porch_ai/services/chat/doors/realism/core_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/realism/eval_transport.dart';
import 'package:front_porch_ai/services/chat/doors/realism/eval_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/realism/injection_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/realism/judge_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/realism/memory_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/realism/needs_seeds.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_deps.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_restores.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_state.dart';
import 'package:front_porch_ai/services/chat/doors/realism/regen_baseline.dart';
import 'package:front_porch_ai/services/chat/doors/realism/relationship_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/realism/scalar_carries.dart';
import 'package:front_porch_ai/services/chat/doors/realism/today_planner.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

export 'package:front_porch_ai/services/chat/doors/realism/chat_lore.dart';
export 'package:front_porch_ai/services/chat/doors/realism/core_wiring.dart';
export 'package:front_porch_ai/services/chat/doors/realism/eval_wiring.dart';
export 'package:front_porch_ai/services/chat/doors/realism/injection_wiring.dart';
export 'package:front_porch_ai/services/chat/doors/realism/judge_wiring.dart';
export 'package:front_porch_ai/services/chat/doors/realism/memory_wiring.dart';
export 'package:front_porch_ai/services/chat/doors/realism/relationship_wiring.dart';
export 'package:front_porch_ai/services/chat/doors/realism/chat_places.dart';
export 'package:front_porch_ai/services/chat/doors/realism/chat_weather.dart';
export 'package:front_porch_ai/services/chat/doors/realism/eval_transport.dart';
export 'package:front_porch_ai/services/chat/doors/realism/needs_seeds.dart';
export 'package:front_porch_ai/services/chat/doors/realism/realism_deps.dart';
export 'package:front_porch_ai/services/chat/doors/realism/realism_restores.dart';
export 'package:front_porch_ai/services/chat/doors/realism/realism_state.dart';
export 'package:front_porch_ai/services/chat/doors/realism/regen_baseline.dart';
export 'package:front_porch_ai/services/chat/doors/realism/scalar_carries.dart';
export 'package:front_porch_ai/services/chat/doors/realism/today_planner.dart';

/// The Realism Engine and everything that hangs off it, built once for the
/// open chat: the clock, Needs, feelings, mood, Afterglow, Pockets, the
/// judges and their tools transport, the prompt injections, the Journal and
/// Growth Rings, lore and places.
///
/// Every object is `late final`: it is built on first use, in the order the
/// leaves ask for each other, as it was when each had its own field. The
/// wiring lives beside this file, one library per family (core, feelings,
/// evals, judges, memory, injections); each object is listed here once.
class RealismGraph {
  RealismGraph(this.deps);

  /// The graph's inputs, read by the wiring libraries beside this file.
  final RealismDeps deps;

  ChatSessionState get session => deps.session;

  /// The chat's switches and the gates read from them.
  ControlsDoor get controls => deps.doors.controls();

  /// The mouth and worker lanes.
  LlmLanes get lanes => deps.services.lanes;

  // ── State the graph owns ──────────────────────────────────────────────

  /// The loaded speaker's emotion registers and the turn's pending metadata.
  final RealismRegisters registers = RealismRegisters();

  /// The overlay's eval flags, streamed judge text and verifier pass.
  late final RealismEvalStatus evalStatus = RealismEvalStatus(deps.notify);

  /// The 1:1 speaker's pockets. In a group each member's record lives in
  /// their group slot instead, which keeps it session-scoped and deleted
  /// with the chat; this is the same record for the host.
  Pockets? hostPockets;

  /// The Growth Rings pass is running (zeroed on every session boundary).
  bool growthPassRunning = false;

  // ── Clock, Needs, feelings and mood ───────────────────────────────────

  late final TimeService time = buildTime();
  late final StoryClockScope clockScope = buildClockScope();
  late final StoryClockReader clockReader = StoryClockReader(clockScope);
  late final StoryClockWriter clockWriter = buildClockWriter();
  late final EpisodeCrumbMinter episodeCrumbs = buildEpisodeCrumbs();
  late final BirthdaySync birthdays = buildBirthdays();
  late final GroupRealismStore groups = buildGroups();

  /// The open chat as Realism and Needs read and write it, live.
  late final RealismScope scope = buildScope();
  late final ChaosModeService chaos = buildChaos();
  late final NsfwService nsfw = buildNsfw();
  late final NeedsSimulation needs = buildNeeds();
  late final NeedsPass needsPass = buildNeedsPass();
  late final NeedsRewinds needsRewinds = buildNeedsRewinds();
  late final NeedsReprocess needsReprocess = buildNeedsReprocess();
  late final StandingMood standingMood = buildStandingMood();
  late final MoodRegisters mood = buildMood();
  late final RealismSnapshot snapshot = buildSnapshot();
  late final RelationshipService relationship = buildRelationship();
  late final ExpressionService expression = buildExpression();

  // ── Judges and their transport ────────────────────────────────────────

  /// Native tool call first, then the text floor; one probe per backend.
  late final EvalTransport transport = buildTransport();
  late final ToolSupportTester toolSupportTester = buildToolSupportTester();
  late final LlmEvalEngine llmEvalEngine = buildLlmEvalEngine();
  late final RealismVerification verifier = buildVerifier();
  late final NeedsImpactEvaluator needsImpact = buildNeedsImpact();
  late final RealismEvals evals = buildEvals();
  late final ObjectiveProposal objectiveProposal = buildObjectiveProposal();
  late final CastFeelingsJudge castFeelingsJudge = buildCastFeelingsJudge();
  late final RealismJudges judges = buildJudges();
  late final RealismDance dance = buildDance();

  // ── Afterglow, Pockets and the fused reply-facts transport ────────────

  late final PocketsLedger pocketsLedger = buildPocketsLedger();
  late final PocketsRewinds pocketsRewinds = buildPocketsRewinds();
  late final PocketsPass pocketsPass = buildPocketsPass();
  late final ItemCardJournal itemCards = buildItemCards();
  late final ReplyFacts replyFacts = buildReplyFacts();
  late final AfterglowPass afterglow = buildAfterglow();

  // ── The Journal, Growth Rings and the Living Time leaves ──────────────

  late final JournalStore journalStore = buildJournalStore();
  late final PorchMemoryImportService porchImport = buildPorchImport();
  late final JournalReview journalReview = buildJournalReview();
  late final JournalMaintenance journalMaintenance = buildJournalMaintenance();
  late final MilestoneFeed milestoneFeed = buildMilestoneFeed();
  late final GrowthStore growthStore = buildGrowthStore();
  late final GrowthReview growthReview = buildGrowthReview();
  late final GrowthService growthService = buildGrowthService();
  late final GrowthDesk growthDesk = buildGrowthDesk();
  late final TimelineInvalidator timeline = buildTimeline();
  late final AmbitionService ambitions = buildAmbitions();
  late final PromiseDebtService promiseDebt = buildPromiseDebt();
  late final DreamService dreams = buildDreams();

  // ── Prompt injections ─────────────────────────────────────────────────

  late final AuthorNoteBuilder authorNotes = buildAuthorNotes();
  late final RelationshipInjection relationshipInjection =
      buildRelationshipInjection();
  late final EmotionInjection emotionInjection = buildEmotionInjection();
  late final BehavioralInjection behavioralInjection =
      buildBehavioralInjection();
  late final TimeInjection timeInjection = TimeInjection(timeService: time);
  late final WeatherInjection weatherInjection = buildWeatherInjection();
  late final AmbitionInjection ambitionInjection = buildAmbitionInjection();
  late final PlanInjection planInjection = buildPlanInjection();

  /// Likes & Dislikes, NOT realism-gated (see PreferencesInjection).
  late final PreferencesInjection preferencesInjection =
      buildPreferencesInjection();

  /// Pockets & Wardrobe, the per-turn record fragment. Answers to its own
  /// switch only (see PocketsEval for why it depends on nothing else).
  late final InventoryInjection inventoryInjection = buildInventoryInjection();
  late final PromiseDebtInjection promiseDebtInjection =
      buildPromiseDebtInjection();
  late final NsfwInjection nsfwInjection = buildNsfwInjection();
  late final ChaosInjection chaosInjection = buildChaosInjection();
  late final NeedsInjection needsInjection = buildNeedsInjection();
  late final RealismStateInjection realismStateInjection =
      buildRealismStateInjection();
  late final JournalInjection journalInjection = buildJournalInjection();

  // ── Lore, places and the realism rewinds ──────────────────────────────

  /// The lorebook scanner and injector over one entry enumerator.
  late final ChatLore lore = ChatLore(this);

  /// The Setting and Lore slots, climate, weather, moves and mints.
  late final ChatPlaces places = ChatPlaces(this);

  /// The story weather the Setting's climate and the clock give.
  late final ChatWeather weather = ChatWeather(this);

  /// The realism restore from a message's snapshot, the post-gen Needs
  /// checks and mood decay.
  late final RealismRestores restores = RealismRestores(this);

  /// Regen's rewind to the pre-turn baseline.
  late final RegenBaseline regenBaseline = RegenBaseline(this);

  /// The scalars a cast changing shape carries.
  late final ScalarCarries carries = ScalarCarries(this);

  /// A greeting's opening bars.
  late final NeedsSeeds seeds = NeedsSeeds(this);

  /// The planner's today line as a held side quest.
  late final TodayPlanner planner = TodayPlanner(this);

  // ── Reads the doors and the service share ─────────────────────────────

  /// True when the user-facing Realism Engine (the judges that score the
  /// user's message: bond, trust, emotion) runs for the current chat mode.
  /// False in Director Mode, where the user is off stage; Needs, the clock
  /// and the cast's feelings for each other still run there.
  bool get realismActiveThisMode =>
      controls.realismEnabled &&
      !deps.doors.cast().idle.autoResponseInProgress &&
      (session.activeGroup == null ||
          !deps.doors.entry().director.observerMode);

  /// Porch Life alone. Card veto and leftover per-chat are not a gate.
  bool get _seededPassageOfTime => derivedPassageOfTimeEnabled(
    porchLifeDefault:
        deps.services.storage.realismSettings.passageOfTimeDefault,
  );

  /// Re-applies Porch Life's passage of time after a clock seed.
  void applySeededPassageOfTime() {
    time.setPassageOfTimeEnabled(_seededPassageOfTime);
    time.markClockGateSource('porch_life');
  }

  /// Combined Pockets gate: Porch Life global AND this character's card.
  bool pocketsEnabledFor(String characterId) =>
      deps.services.storage.realismSettings.pocketsEnabled &&
      pocketsLedger.pocketsEnabledFor(characterId);

  /// Persist [p] back to wherever that character's record lives.
  void setPocketsFor(String characterId, Pockets p) =>
      pocketsLedger.setPocketsFor(characterId, p);

  /// Seed every speaker's card kit unless the chat already has one. Every
  /// conversation entry path calls this.
  void seedPocketsFromCards() {
    if (!deps.services.storage.realismSettings.pocketsEnabled) return;
    pocketsLedger.seedPocketsFromCards();
  }

  /// Group members in a group, else the 1:1 character when one is set.
  Iterable<CharacterCard> clockCast() => session.activeGroup != null
      ? session.groupCharacters
      : [session.activeCharacter].whereType<CharacterCard>();
}
