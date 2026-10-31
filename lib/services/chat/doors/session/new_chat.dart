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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

import 'session_store.dart';

/// A fresh chat for the open cast: the departing chat flushed, the live
/// scalars re-seeded from the card (1:1) or the group's member baselines,
/// Chaos seeded from the card or group OR-ed with the Porch Life default,
/// the opening greeting placed, and the new row saved.
class NewChatOpener {
  NewChatOpener(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  SessionShellHooks get _h => _d.hooks;
  RealismScope get _scope => _s.realism();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  CastDoor get _cast => _s.cast();
  RelationshipService get _relationshipService => _scope.relationship();
  NsfwService get _nsfwService => _scope.nsfw();
  TimeService get _timeService => _scope.time();
  NeedsSimulation get _needsSimulation => _scope.needs();
  ChaosModeService get _chaosModeService => _s.chaos();
  LorebookScanner get _lorebookScanner => _s.lorebook();
  ExpressionService get _expressionService => _s.expression();
  MacroResolver get _macroResolver => _s.macros;
  AppDatabase get _db => _s.db();

  /// The chat's own Realism switch, seeded from the card.
  set _realismChatSwitch(bool on) => _h.setChatRealism(on);

  /// The chat's stored Needs switch: seeded here, never a gate.
  bool get _needsSimEnabled => _scope.needsSimEnabled();
  set _needsSimEnabled(bool on) => _h.setNeedsSimEnabled(on);

  String _debugScalars() =>
      'arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}';

  /// [personaId] is the explicitly-picked persona ("Start New Chat"). Omitted —
  /// the ordinary "tap a character" path — the chat starts as the DEFAULT
  /// persona, never as whoever the previously-open chat happened to be. That
  /// inheritance is exactly what showPersonaPickerDialog exists to prevent, and
  /// it used to leak in through here whenever the picker was skipped.
  Future<void> open({String? personaId}) async {
    if (_session.activeCharacter == null && _activeGroup == null) return;
    _store.today.clearTodayPointer();

    // Persist the departing chat as whoever we still are. Switching to
    // the default first let the flush stamp Nightowl onto the open row
    // (persona_default_test / history last-session reopen).
    await _store.save();
    await _s.personas.setActivePersona(
      personaId ?? _s.personas.defaultPersonaId,
    );

    // Reset AFK idle state when starting a new chat
    _cast.idle.cancelIdleTimer();
    _cast.idle.hasCompletedExchange = false;
    _cast.away.state.reset();

    debugPrint('[startNewChat] START: ${_debugScalars()}');

    await _store.prep.refreshCharacterForNewChat();

    debugPrint(
      '[Chat] 🟡 startNewChat: clearing messages (had ${_session.messages.length})',
    );
    // Departing row was flushed above, before the default persona switch.
    await _cast.greetings.invalidateGreetingEval();
    await _store.prep.resetNewChatTranscript();

    // Seed Realism Engine state from V2.5 card extensions for 1:1 mode only,
    // ensuring realism settings persist across chat sessions (group mode
    // handled elsewhere).
    if (_session.activeCharacter != null && _activeGroup == null) {
      final extSeed =
          _session.activeCharacter!.frontPorchExtensions ??
          FrontPorchExtensions();

      // Global "Enable Realism Mode" default is an OR override so imported
      // cards (no realism setup) get realism + baseline generation without the
      // user editing each card. Defaults false → no change until opted in.
      // Mirrors the setActiveCharacter fresh-seed path (chat_entry).
      _realismChatSwitch =
          extSeed.realismEnabled || _s.storage.realismSettings.realismDefault;
      // Card-seed bypass: seedFromCardV2OrExt (plain .clamp only, no
      // migration) because V2.5 cards and creators author on the current
      // ±300 scale; the old "Migration + seed" call doubled bond on a fresh
      // 1:1 New Chat. Migration stays on legacy persisted session paths only.
      // Clear ALL per-chat relationship registers first, THEN re-seed
      // bond/trust from the card: seedFromCardV2OrExt deliberately does NOT
      // touch the active fixation, spatial stance, the pending trust-repair
      // flag or the long-term/decay counters, and without the reset those
      // survived into the fresh chat and were persisted into its row (the
      // "Background Thought" leak across chats with the SAME character).
      // Mirrors setActiveCharacter's reset-before-load ordering and the group
      // baseline reset in the else branch (1:1 ↔ group fresh-chat parity).
      _relationshipService.resetForFreshChat();
      _relationshipService.seedFromCardV2OrExt(
        shortTermBond: extSeed.shortTermBond,
        longTermBond: extSeed.longTermBond,
        trustLevel: extSeed.trustLevel,
      );
      _expressionService.resetForFreshChat();
      // Lorebook trigger reset keeps a prior isTriggered/remainingDepth from
      // bleeding into the fresh chat's greeting scan (constants skipped).
      _lorebookScanner.resetLorebookTriggerState();
      // Time seed (keeps startNewChat / setActive / ext-seed blocks in sync).
      _timeService.seedFromV2OrExt(
        dayCount: extSeed.dayCount.clamp(1, 9999),
        timeOfDay: extSeed.timeOfDay,
        storyStartDate: extSeed.storyStartDate,
        storyStartTime: extSeed.storyStartTime,
      );
      _h.applySeededPassageOfTime();
      _s.mood().seed(extSeed.characterEmotion, extSeed.emotionIntensity);
      // The card says how a new chat starts its Afterglow.
      _nsfwService.seedFromV2OrExt(
        nsfwCooldownEnabled: extSeed.afterglowEnabled,
      );
      // Seeded from the CARD or-ed with the Porch Life global, exactly as the
      // chat_entry twin does. Deliberately NOT hoisted below the if/else next
      // to the Pockets re-seed: down there `extSeed` is out of scope and the
      // only readable value is the service's own, which still holds the
      // PREVIOUS chat's chaos state — hoisting it would trade a missing
      // re-seed for a bleed, which is worse.
      _chaosModeService.seedFromGroupOrExt(
        extSeed.chaosModeEnabled || _s.storage.realismSettings.chaosModeDefault,
        false,
      );
      // A silent card follows the Porch Life Needs switch (chat_entry twin).
      _needsSimEnabled = _s.needsPass().seedNeedsSim(extSeed.needsSimChoice);
      _h.setEnjoysLowHygiene(extSeed.enjoysLowHygiene);
      if (_needsSimEnabled) {
        // Fresh chat / new session: seed from card baselines (falls back to
        // needDefaults when the card has no baselines).
        _needsSimulation.initializeFreshWithDefaults(
          NeedsSimulation.baselinesFromExtensions(extSeed),
        );
      } else {
        _needsSimulation.clearVector();
      }
      _needsSimulation.resetBuffers();
      // v47: the 1:1 Pockets record is per-chat and re-seeds from the card on
      // the first pass, so a fresh chat must start empty. See the chat_entry
      // twin — now that the record persists, a bleed here would be saved.
      _h.setHostPockets(null);

      // Always reset per-chat runtime realism fields (arousal/fixation/
      // cooldowns) for a fresh session started via explicit New Chat. The
      // declarative initial bond/trust/emotion/day are already seeded above
      // from the card's FrontPorchExtensions (or defaults); the old
      // hasFrontPorchExtensions preserve here was the source of fixation
      // bleed on "New Chat" for cards that had any FP ext object.
      debugPrint(
        '[startNewChat] Resetting runtime arousal/fixation + transients for fresh chat (was: ${_debugScalars()})',
      );
      _nsfwService.resetRuntimeArousalAndCooldown();
      debugPrint('[startNewChat] After reset: ${_debugScalars()}');

      // Tiers are maintained inside RelationshipService after the seed, so
      // there is nothing to recalculate here.

      _s.objectives().writer.importAuthoredTask(extSeed);
    } else {
      // Group mode or no active character: reset to defaults but preserve
      // existing extensions-based values.

      if (_activeGroup == null && _session.messages.isNotEmpty) {
        // Will be populated later with greeting in non-group modes
        // Preserve realism state for proper post-greeting eval (don't reset here)
      } else {
        // Relationship + Expression + Time + Nsfw reset via service helpers
        // (keep reset blocks in sync with setActiveCharacter, the 0-session
        // load, setActiveGroup and the 1:1 ext-seed branch above).
        _relationshipService.resetForFreshChat();
        _expressionService.resetForFreshChat();
        _timeService.resetForFreshChat();
        // Fresh GROUP chat: apply the group's authored scene-time seed on top
        // of the reset (story-calendar "As built" gap fix). Keep in sync with
        // the loadLastSession 0-session branch.
        if (_activeGroup != null) {
          _scope.groups.afterglowOn = groupAfterglowIn(
            _activeGroup!.defaultMemberRealismState,
          );
          final timeSeed = parseGroupTimeSeed(
            _activeGroup!.defaultMemberRealismState,
            _activeGroup!.baselineRealismState,
          );
          if (timeSeed != null) {
            _timeService.seedFromV2OrExt(
              dayCount: timeSeed.dayCount,
              timeOfDay: timeSeed.timeOfDay,
              storyStartDate: timeSeed.storyStartDate,
              storyStartTime: timeSeed.storyStartTime,
            );
            _h.applySeededPassageOfTime();
          }
        }
        _nsfwService.resetForFreshChat();
        _lorebookScanner.resetLorebookTriggerState();
        // Don't touch dayCount/time etc directly — seeded from extensions or
        // loaded session (or reset above for fresh no-ext path).

        // Explicit zero for the secondary config flags in the group / non-ext
        // / 0-session new-chat path (matches the 1:1 ext-seed branch,
        // setActiveCharacter and setActiveGroup).
        _needsSimEnabled = false;
        _h.setEnjoysLowHygiene(false);
        _needsSimulation.clearVector();
        _needsSimulation.resetBuffers();
        // v47: same as the ext-seed branch above — a fresh chat starts with
        // empty hands and re-seeds from the card on the first pass.
        _h.setHostPockets(null);
        // Fresh group chat: reset each member's per-character realism (bond/
        // trust/emotion/needs/FIXATION) back to the group's default member
        // baselines so the previous session's evolved state — most visibly an
        // active fixation "Background Thought" — does not bleed into the new
        // chat. The scalar resetForFreshChat() above only clears the 1:1
        // registers; per-speaker group state lives in the group map, which
        // startNewChat never reset (the leak). This mirrors the 1:1 branch's
        // resetForFreshChat + card re-seed (parity). Only the map is reset —
        // group config (per-char system prompts, RAG priorities, author notes)
        // is intentionally preserved, which is why we do NOT route through
        // loadGroupRealismState(null): defaultMemberRealismState is
        // perChar-only, so that path would wipe those config maps.
        // parseGroupRealismSeeds pulls just the perChar baselines.
        if (_activeGroup != null) {
          _h.resetDirectorModeToDefault();
          _scope.groups.members = parseGroupRealismSeeds(
            _activeGroup!.defaultMemberRealismState,
          ).map((k, v) => MapEntry(k, GroupMemberRealism.fromJson(v)));
          await _h.rekeyGroupStores();
          // Re-derive Needs from those seeds, exactly as FRESH GROUP ENTRY
          // does (chat_service_group_entry.dart — presence-inference: the
          // creator omits the per-member 'needs' sub-map when Needs was off
          // in the wizard). The zeroing above is the right starting point for
          // the no-group path, but for a group it was the FINAL word: "New
          // Chat" inside a group hard-disabled Needs, saved false onto the new
          // session row, and every reload read it back — blank needs grids and
          // no decay for the rest of that conversation, while first entry into
          // the same group worked. The 1:1 branch re-seeds from the card for
          // the same reason. AND-gated by the Porch Life Needs switch, as
          // group entry and the group import are.
          _needsSimEnabled =
              _s.storage.realismSettings.needsSimDefault &&
              _scope.groups.members.values.any((state) {
                final n = state.needs;
                return n != null && n.isNotEmpty;
              });
          if (_needsSimEnabled) {
            // Placeholder vector only — the first per-speaker
            // RealismDance.loadIntoScalars replaces it with that member's own
            // needs. Same flat baseline the group-entry twin uses.
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
          // The group's twin of the 1:1 chaos seed above, which this branch
          // never had. A fresh chat inside a group simply inherited whatever
          // setActiveGroup had left in the service — usually the right answer,
          // which is why nobody noticed, but wrong the moment the Porch Life
          // global changes while a group is open. "New Chat" is exactly when a
          // user expects their defaults re-applied. Source is the GROUP's own
          // flags rather than a card's, matching setActiveGroup.
          _chaosModeService.seedFromGroupOrExt(
            _activeGroup!.chaosModeEnabled ||
                _s.storage.realismSettings.chaosModeDefault,
            _activeGroup!.chaosNsfwEnabled,
          );
        }
        _s.objectives().resetForChatSwitch();
        // Secondary zeros in the non-ext/group/0-session new-chat path.
        _store.summaryPaused = false;
        _store.isSummaryGenerating = false;
        _h.setGrowthPassRunning(false);
      }
    }

    // Both branches above cleared the record; put back what the CARDS say they
    // start with, so the fresh chat's greeting is drawn with their wardrobe
    // already in the sidebar rather than empty until the first message.
    //
    // Placed HERE, after the if/else closes, and that placement is the whole
    // trick: the group branch nulls the host record and then rebuilds the
    // group map from the group's member baselines a dozen lines later, so
    // seeding beside the null would have been wiped for every group and
    // silently worked for every 1:1 — the shape of bug that looks fixed until
    // somebody opens a group. One call after both branches cannot go half-right.
    _h.seedPocketsFromCards();

    // Drop the previous session's growth cache so the new chat starts with
    // the original (ungrown) personality. A fresh session has no rings and
    // no legacy blob, so an empty cache IS the correct state — the next
    // growth-desk refresh (session load / first growth pass) re-scopes it.
    _h.setGrowthPassRunning(false);
    _s.growthStore().invalidate();

    await _placeOpeningGreeting();

    _session.currentSessionId = DateTime.now().millisecondsSinceEpoch
        .toString();
    _store.computeAbsenceGap(
      const [],
    ); // fresh session — no real-world gap (Living Time §2)
    // Seed chat worlds for the fresh session (group template or the
    // character's attached worlds — Living Worlds).
    await _store.forker.seedChatWorldsForNewSession();
    await _s.media().seedWikiForNewSession();

    // Inherit theme from the most recent prior session with this character/group.
    _store.themeOverrides = ChatThemeOverrides();
    try {
      final lastThemeJson = await _db.getLastSessionThemeOverrides(
        characterId: _session.activeCharacter?.dbId,
        groupId: _activeGroup?.id,
      );
      if (lastThemeJson != null) {
        _store.themeOverrides = ChatThemeOverrides.fromJsonString(
          lastThemeJson,
        );
      }
    } catch (_) {
      _store.themeOverrides = ChatThemeOverrides();
    }
    debugPrint('[startNewChat] BEFORE SAVE: ${_debugScalars()}');
    await _store.save();
    debugPrint('[startNewChat] AFTER SAVE: ${_debugScalars()}');
    _d.notify();

    // ── Post-Greeting Realism Baseline ──────────────────────────────────
    // Always mark that a greeting was placed — even if Realism is currently off.
    // If Realism is already on, fire immediately. Otherwise the flag will be
    // consumed the moment the user enables Realism.
    // Skip if character already has pre-seeded V2.5 extensions — those baseline
    // values are intentional and should not be overwritten by auto-eval.
    //
    // THE OPENING POSITION DOES NOT RIDE THIS GATE, and must never be wired to
    // it. Both conditions below are about AUTHORED baselines — bond, trust,
    // emotion, the numbers a creator set on the card — which is why an
    // extensions-bearing card is excluded and why a group (whose baselines live
    // in defaultMemberRealismState, not on a card) is too. Spatial stance is
    // not authored anywhere: no card, group or Stoop download carries one, so
    // there is nothing here to protect and these gates only ever hid the seed
    // from the majority of real chats. It lives in the pre-turn dance instead
    // (seedOpeningPosture), which reaches every card shape, every group
    // member, all four ways a conversation can start, and a reload — the seed
    // this baseline fires is a head start for the sidebar, not the mechanism.
    if (_activeGroup == null &&
        _session.messages.isNotEmpty &&
        _session.activeCharacter!.frontPorchExtensions == null) {
      _cast.baseline.greetingEvalPending = true;
      if (_h.realismEnabled()) {
        _cast.baseline.runPostGreetingEval();
      }
    }
  }

  /// The fresh chat's opening line, with its Realism and Needs seed.
  Future<void> _placeOpeningGreeting() async {
    final greetings = _cast.greetings;
    if (_activeGroup != null && _groupCharacters.isNotEmpty) {
      // Group mode: respect explicit group.firstMessage (custom group greeting
      // set by creator or Group Card) when present. Only fall back to the
      // first participating character's allGreetings when the group has no
      // custom opening.
      String greetingText;
      String greetingSender;
      String? greetingCharId;

      if (!greetingFirstMesEmpty(_activeGroup!.firstMessage)) {
        greetingText = _macroResolver.resolve(
          _activeGroup!.firstMessage,
          MacroContext(userName: _s.personas.persona.name),
          section: 'greeting',
        );
        greetingSender = _activeGroup!.name;
        greetingCharId = null;
      } else {
        final first = _groupCharacters.first;
        greetingText = greetings.memberOpeningGreetingText(first);
        greetingSender = first.name;
        greetingCharId = _h.characterIdFor(first);
      }

      if (greetingText.isNotEmpty) {
        _session.messages.add(
          ChatMessage(
            text: greetingText,
            sender: greetingSender,
            isUser: false,
            characterId: greetingCharId,
          ),
        );
        _lorebookScanner.scanLatest();
        _s.clockWriter().writeSlotClock(
          _session.messages.isEmpty ? null : _session.messages.first,
          kind: SlotClockWrite.seed,
        );
        // Overlay 0 / inherit baseline into live emotion and slots.
        // Previously only the empty-empty path applied seed, so leftover
        // swipe fury survived New Chat on a custom opener or member-greet.
        if (!greetingFirstMesEmpty(_activeGroup!.firstMessage)) {
          await greetings.applyGroupCustomGreetingSeed(0);
        } else {
          await greetings.applyGreetingOpeningSeed(
            card: _groupCharacters.first,
            index: 0,
          );
        }
      }
      _session.groupManager?.resetTurnState();
    } else if (_session.activeCharacter != null) {
      // 1:1 mode
      final opening = _session.activeCharacter!.allGreetings;
      if (opening.isNotEmpty) {
        _session.messages.add(
          ChatMessage(
            text: greetings.buildFirstMessage(
              _session.activeCharacter!,
              greetingText: opening.first,
            ),
            sender: _session.activeCharacter!.name,
            isUser: false,
          ),
        );
        _lorebookScanner.scanLatest();
        _s.clockWriter().writeSlotClock(
          _session.messages.isEmpty ? null : _session.messages.first,
          kind: SlotClockWrite.seed,
        );
        if (_session.activeCharacter!.firstMessage.trim().isEmpty) {
          await greetings.applyGreetingOpeningSeed(
            card: _session.activeCharacter!,
            index: 0,
          );
        }
      }
    }
  }
}
