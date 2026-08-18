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

part of 'realism_evals.dart';

/// The fused one-shot realism eval call (Cluster E) for [RealismEvals].
/// PUBLIC (not `_private`) — invoked from the chat_service library's god
/// thins and from test/services/chat/one_shot_parity_test.dart; a private
/// extension would not resolve outside this library. Split out of
/// realism_evals.dart verbatim as part of the god-file elimination
/// campaign; see docs/design/god-file-elimination.md.
extension RealismEvalOneShot on RealismEvals {
  /// ── One-Shot Eval (Experimental) ─────────────────────────────────────────
  /// Fused replacement for _evaluateRelationshipCall + _evaluateSceneStateCall.
  /// Issues a SINGLE LLM inference that evaluates all realism state fields at
  /// once, cutting pre-generation blocking overhead from 2 calls to 1.
  ///
  /// Enable via Settings → Realism → "One-Shot Eval (Experimental)".
  /// Not default because some models struggle with the combined prompt length.
  Future<void> evaluateOneShotCall({
    void Function(String)? onChunk,
    bool skipClockAdvance = false,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;

    // The group speaker path sets _activeCharacter before calling this for parity.

    // Keep the eval prompt lean for local models — use fewer messages and a
    // shorter personality snippet to reduce prefill time on large models.
    // Bond/emotion/narrative score the USER (through last user). Scene-time
    // apply is skipped on follow-up speakers via skipClockAdvance (Next
    // Character only), so this window cannot diverge live minutes from the
    // four-call path (that path still builds a full recentExchange for the
    // unused follow-up time call).
    final recent = recentExchangeThroughLastUser(getMessages(), take: 6);

    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final char = getActiveCharacter()!;
    final charName = char.name;
    final userName = getUserName();

    final dossier = getCharacterDossier(char);
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: relationshipService.shortTermTierName,
      longTermTier: relationshipService.longTermTierName,
      trustTier: relationshipService.trustTierName,
      trustLevel: relationshipService.trustLevel,
      emotion: getCharacterEmotion(),
      emotionIntensity: getEmotionIntensity(),
      posture: relationshipService.spatialStance,
    );
    final arousalEnabled = nsfwService.nsfwCooldownEnabled;
    final labels = getExpressionEnabled()
        ? EmotionLabels.all
        : const <String>[];
    final primary = getPrimaryObjective();

    // Same shared fragments as the multi-call path (strict one-shot vs normal
    // parity by construction — the rubric text cannot drift between paths).
    final plannerToday = getPlannerEnabled?.call() ?? false;
    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.oneShotEvalPrompt(
          preferences: getPreferences?.call() ?? '',
          charName: charName,
          userName: userName,
          dossier: dossier,
          standing: standing,
          recent: recent,
          arousalEnabled: arousalEnabled,
          arousalLevel: nsfwService.arousalLevel,
          refractoryTurnsLeft: nsfwService.cooldownTurnsRemaining,
          allowedEmotionLabels: labels,
          primaryObjective: primary?.objective,
          ambitions: getAmbitions?.call() ?? const [],
          toolsMode: toolsMode,
          plannerToday: plannerToday,
        );
    final prompt = buildPrompt(toolsMode: false);

    try {
      debugPrint('[Realism:OneShot] Evaluating (fused call)...');
      final raw = await _fireEval(
        toolName: kOneShotTool,
        tools: plannerToday ? kOneShotEvalToolsWithToday : kOneShotEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) {
        // PARITY. The four-call path reaches TimeService unconditionally, and
        // when its own scene-time eval returns nothing it drifts the clock by
        // StoryClock.failureDriftMinutes — "deterministic drift so time never
        // freezes", as that path's own comment puts it. One-shot returned here,
        // more than a hundred lines before its clock call, so ONE failed
        // evaluation (backend down, empty reply, timeout) froze the story clock
        // for the whole turn. The project's strictest written rule is that
        // one-shot must be 1:1 equivalent to the four-call path; this is the
        // failure case of that rule.
        //
        // An empty oneShotText takes the same branch the four-call path takes:
        // oneShotMode makes no LLM call, minutes parse as null so the drift
        // applies, and an OOC time skip that already moved the clock this turn
        // still suppresses it.
        await timeService.evaluateTimeProgressAndPostureIfNeeded(
          charName: charName,
          recent: recent,
          shortTermTierName: relationshipService.shortTermTierName,
          onChunk: onChunk,
          fireLLMEval: fireLLMEval,
          stripThinkBlocks: stripThinkBlocks,
          extractJsonBool: extractJsonBool,
          setSpatialStance: relationshipService.setSpatialStance,
          getCurrentSpatialStance: () => relationshipService.spatialStance,
          getCharacterEmotion: getCharacterEmotion,
          getEmotionIntensity: getEmotionIntensity,
          oneShotMode: true,
          oneShotText: '',
          skipClockAdvance: skipClockAdvance,
        );
        return;
      }

      final searchText = stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      if (_batchCollectActive) {
        _pendingBatchEvals.add({
          'kind': 'oneShot',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {
            'personality': dossier,
            'standing': standing,
            if (labels.isNotEmpty)
              'emotion_constraint': RealismPromptBuilder.emotionLabelConstraint(
                labels,
              ),
          },
        });
        return;
      }

      final effectiveText = await _verifyAndApply(
        evalKind: 'oneShot',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {
          'personality': dossier,
          'standing': standing,
          if (labels.isNotEmpty)
            'emotion_constraint': RealismPromptBuilder.emotionLabelConstraint(
              labels,
            ),
        },
      );
      final textForOneShot = effectiveText; // rebind

      // ── Relationship / trust / arousal (unified with multi-call path) ──
      // applyArousal:true — the fused one-shot prompt is the requester of
      // arousal_delta, and this is its single application (the inline emotion
      // parse below deliberately does not touch arousal).
      _parseAndApplyRelationshipDeltas(textForOneShot, applyArousal: true);

      // ── Autonomous Objective ──
      // (All parses below use textForOneShot — the Director-corrected text.
      // Parsing the raw pre-verification text silently discarded corrections
      // for everything except the relationship deltas.)
      final objectiveMatch = RegExp(
        r'"proposed_objective"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      // Objectives off ⇒ the character does not get to start new quests. Same
      // gate, same source of truth as the four-call twin in
      // realism_evals.support.dart — without it, one-shot (the DEFAULT fused
      // mode on a tool-capable remote backend) kept growing quests behind the
      // switch's back and fired an unrequested task-generation call.
      final objectivesOn = getObjectivesEnabled?.call() ?? true;
      if (objectivesOn && objectiveMatch != null) {
        final newObj = objectiveMatch.group(1)!.trim();
        if (newObj.toLowerCase() != 'none' && newObj.isNotEmpty) {
          // Avoid setting the exact same goal if it's already active
          final active = getActiveObjectives();
          final isDuplicate = active.any(
            (o) => o.objective.toLowerCase() == newObj.toLowerCase(),
          );
          if (!isDuplicate &&
              !TodayLineTag.proposedCollidesWithToday(
                newObj,
                textForOneShot,
              )) {
            // Same decision as the narrative path (strict oneShot vs normal parity):
            // claim the main-quest slot when it's free, stay a side quest when a
            // primary already exists — never displace an existing main quest.
            final becomesPrimary = getPrimaryObjective() == null;
            debugPrint(
              '[Realism:OneShot] Autonomous objective proposed: $newObj '
              '(${becomesPrimary ? "primary — main-quest slot free" : "secondary — primary exists"})',
            );
            // Pass autoGenerateTasks:true so the character's self-initiated goal gets
            // concrete subtasks (making autonomous objectives feel like real pursuits
            // with steps the character can accomplish).
            // (thin delegation to god setObjective per plan for step9)
            await setObjective(
              newObj,
              isPrimary: becomesPrimary,
              autoGenerateTasks: true,
              // Same field, same resolver, same roster as the narrative path —
              // one-shot must produce a 1:1 equivalent objective or the two
              // modes disagree about which mountain the quest is on.
              servedAmbition: RealismPromptBuilder.resolveServedAmbition(
                RegExp(
                  r'"serves_ambition"\s*:\s*"?([^",}]*)"?',
                ).firstMatch(textForOneShot)?.group(1),
                getAmbitions?.call() ?? const [],
              ),
            );
          }
        }
      }

      // ── Scene fields ──
      final emotionMatch = RegExp(
        r'"emotion"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      if (emotionMatch != null) {
        setCharacterEmotion(emotionMatch.group(1)!.toLowerCase().trim());
      }

      final intensityMatch = RegExp(
        r'"emotion_intensity"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      if (intensityMatch != null) {
        setEmotionIntensity(intensityMatch.group(1)!.toLowerCase().trim());
      }

      // NO POSTURE HERE. One-shot is a PRE-generation optimisation and
      // posture stopped being a pre-generation question on 2026-08-08 — it is
      // now its own post-generation pass, which reads the reply the character
      // actually wrote (see TimeService.evaluateTimeProgressAndPostureIfNeeded).
      // Parsing it here would have made one-shot the ONLY mode that still
      // asserts a stale position into the very reply it precedes, which is a
      // strict-parity violation on Spatial Stance — the four-call path no
      // longer sets it here either. test/services/chat/one_shot_parity_test
      // compares 'stance' across the two paths and would catch a relapse.

      relationshipService.updateFixationFromEvalResult(
        (RegExp(
              r'"fixation_topic"\s*:\s*"([^"]+)"',
            ).firstMatch(textForOneShot)?.group(1) ??
            ''),
        isOneShot: true,
      );

      // ── Story clock (parity with the multi-call path) ──
      // The fused JSON above already carries minutes_elapsed/new_day; this
      // applies the same clamp/floor/backstop clock math the dedicated
      // per-turn scene-time eval uses — no extra LLM call.
      await timeService.evaluateTimeProgressAndPostureIfNeeded(
        charName: charName,
        recent: recent,
        shortTermTierName: relationshipService.shortTermTierName,
        onChunk: onChunk,
        fireLLMEval: fireLLMEval,
        stripThinkBlocks: stripThinkBlocks,
        extractJsonBool: extractJsonBool,
        setSpatialStance: relationshipService.setSpatialStance,
        getCurrentSpatialStance: () => relationshipService.spatialStance,
        getCharacterEmotion: getCharacterEmotion,
        getEmotionIntensity: getEmotionIntensity,
        oneShotMode: true,
        oneShotText: textForOneShot,
        skipClockAdvance: skipClockAdvance,
      );

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(textForOneShot);
      debugPrint(
        '[Realism:OneShot] Done — Emotion: ${getCharacterEmotion()} (${getEmotionIntensity()}), '
        'Time: ${timeService.timeOfDay}, Reason: ${reasonMatch?.group(1) ?? 'unknown'}',
      );

      // Bundle full state snapshot for time-travel forking (god will persist via
      // post-eval _saveChat + synthesize in the calling pre-gen / baseline paths;
      // removing the cb calls here eliminates double save/notify for oneShot vs
      // multi-call paths and the save-race window).
      var pending = getPendingRealismMetadata() ?? {};
      pending['emotion_label'] = getCharacterEmotion();
      pending['realism_state'] = captureRealismState();
      setPendingRealismMetadata(pending);
    } catch (e) {
      debugPrint(
        '[Realism:OneShot] Failed: $e — falling back to dual-call on next turn',
      );
    }
  }
}
