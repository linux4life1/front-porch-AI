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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.core.dart';

/// The paused card as the wizard holds it now: the three boxes' text, the
/// creator notes and the facts card's values (the Realism state). Phase B
/// and every rewrite read this, so they follow the user's edits. A copy:
/// the paused run itself is never written to.
CharacterCard profileCardNow(CreatorState s) {
  final paused = s.profile.paused!;
  // copyCard reads the card the way a card file is read; it only fails on a
  // card that could not be saved either, and then the pause is the best
  // there is.
  final card = GenPausedRun.copyCard(paused.card.toJson()) ?? paused.card;
  card
    ..description = s.descController.text
    ..personality = s.personalityController.text
    ..scenario = s.scenarioController.text
    ..creatorNotes = s.generatedCard?.creatorNotes ?? card.creatorNotes;
  final ext = card.frontPorchExtensions ?? FrontPorchExtensions();
  card.frontPorchExtensions = ext.copyWith(
    birthday: s.realismBirthday,
    occupation: s.realismOccupation,
    occupationBrief: s.realismOccupationBrief,
    hours: s.realismHours,
    workDays: s.realismWorkDays,
    currentTask: s.realismCurrentTask,
    shortTermBond: s.realismShortTermBond,
    trustLevel: s.realismTrustLevel,
    ambitions: s.realismAmbitions,
    planLines: s.realismPlanLines,
    likes: s.realismLikes,
    dislikes: s.realismDislikes,
    intimateInto: s.realismIntimateInto,
    intimateNotInto: s.realismIntimateNotInto,
  );
  return card;
}

/// The Profile step's actions (#530): rewrite the profile from the same
/// interview with a line of direction, stop it, and re-read the facts card
/// from the profile as it is now. The twin of `CreatorGreetingWriter`: one
/// run at a time, each on its own service, an `identical` guard so a
/// stopped or replaced run lands nothing, and the boxes keep their text
/// until the new text is in, so Stop has nothing to undo.
class CreatorProfileWriter {
  final CreatorState state;

  CreatorProfileWriter(this.state);

  /// Rewrite Description and Personality, steered by the rewrite card's
  /// steer box; then the facts are re-read from the new profile. A
  /// scenario the user typed is kept (the engine's rule).
  Future<void> rewriteProfile({required LLMProvider llmProvider}) async {
    final p = state.profile;
    if (p.paused == null || p.busy || state.isGenerating) return;
    final llm = llmProvider.serviceForModel(state.selectedModelId);
    if (llm == null) {
      p.error = _noModel(llmProvider);
      state.notify();
      return;
    }
    final gen = state.newGenService(llm);
    final paused = p.paused!.copyWith(card: profileCardNow(state));
    p
      ..rewriting = true
      ..activeGen = gen
      ..stream = const ProfileStreamView()
      ..error = null
      ..factsError = null;
    state.notify();
    ProfileRewrite? result;
    // Why the rewrite gave nothing: a thrown error, or a call that gave up
    // after its retries (`lastFailure`). Only a clean answer with no change
    // is "the same as before"; a Stop says nothing.
    Object? failure;
    try {
      result = await gen.rewriteProfile(
        paused: paused,
        description: state.descController.text,
        personality: state.personalityController.text,
        scenario: state.scenarioController.text,
        direction: p.steer.text.trim(),
        onProgress: (s) {
          if (!identical(p.activeGen, gen)) return;
          p.stream = parseProfileStream(s);
          state.notify();
        },
      );
    } catch (e) {
      debugPrint('CharacterCreator: profile rewrite failed: $e');
      failure = e;
    }
    if (!identical(p.activeGen, gen)) return; // stopped, or the wizard reset
    p
      ..activeGen = null
      ..rewriting = false
      ..stream = const ProfileStreamView();
    final reason = failure ?? (result == null ? gen.lastFailure : null);
    if (reason != null) {
      p.error =
          'The rewrite failed: $reason. Nothing was changed. Check that '
          'your model is running, then try again.';
    } else if (result == null && gen.isAborted) {
      p.error = null; // stopped
    } else if (result == null) {
      p.error =
          'The rewrite came back the same as before, so nothing was '
          'changed. Try saying more plainly what is wrong.';
    } else {
      state.descController.text = result.description;
      state.personalityController.text = result.personality;
      state.scenarioController.text = result.scenario;
      _takeFacts(result.facts, paused.card);
    }
    state.notify();
  }

  /// Stop the rewrite. The boxes never changed, so the old text is simply
  /// still there, and so are the facts.
  void stopProfile() {
    final p = state.profile;
    final gen = p.activeGen;
    if (gen == null) return;
    gen.abort();
    p
      ..activeGen = null
      ..rewriting = false
      ..stream = const ProfileStreamView();
    state.notify();
  }

  /// "Re-read from the profile": the facts card again, from the three boxes
  /// as they are now. Nothing else is touched.
  Future<void> rereadFacts({required LLMProvider llmProvider}) async {
    final p = state.profile;
    if (p.paused == null || p.busy || state.isGenerating) return;
    final llm = llmProvider.serviceForModel(state.selectedModelId);
    if (llm == null) {
      p.factsError = _noModel(llmProvider);
      state.notify();
      return;
    }
    final gen = state.newGenService(llm);
    final paused = p.paused!.copyWith(card: profileCardNow(state));
    p
      ..rereadingFacts = true
      ..factsGen = gen
      ..factsError = null;
    state.notify();
    IdentityFacts? facts;
    Object? failure;
    try {
      facts = await gen.rereadIdentityFacts(
        paused: paused,
        description: state.descController.text,
        personality: state.personalityController.text,
        scenario: state.scenarioController.text,
      );
    } catch (e) {
      debugPrint('CharacterCreator: facts re-read failed: $e');
      failure = e;
    }
    if (!identical(p.factsGen, gen)) return;
    p
      ..factsGen = null
      ..rereadingFacts = false;
    final reason = failure ?? (facts == null ? gen.lastFailure : null);
    if (reason != null) {
      p.factsError =
          'The facts could not be read from the profile: $reason. Nothing '
          'was changed. Check that your model is running, then try again.';
    } else if (facts == null && gen.isAborted) {
      p.factsError = null; // stopped
    } else if (facts == null || facts.isEmpty) {
      p.factsError =
          'The facts could not be read from the profile. Nothing was '
          'changed. Try again, or edit them below.';
    } else {
      _takeFacts(facts, paused.card);
    }
    state.notify();
  }

  /// [facts] onto the paused card and the facts card. Null keeps what the
  /// card had (the engine's rule: a partial read never wipes a field).
  void _takeFacts(IdentityFacts? facts, CharacterCard card) {
    final p = state.profile;
    card
      ..description = state.descController.text
      ..personality = state.personalityController.text
      ..scenario = state.scenarioController.text;
    if (facts != null) {
      applyIdentityFacts(card, facts, nsfw: p.paused!.inputs.nsfwEnabled);
      p.facts = facts;
      state.generatedCard?.creatorNotes = card.creatorNotes;
      CreatorGenerationCore(state).applyIdentityRealism(card);
    }
    p.paused = p.paused!.copyWith(card: card, facts: facts);
  }

  String _noModel(LLMProvider llmProvider) => llmProvider.hasManagedProcess
      ? 'The backend is not running. Start it, then try again.'
      : 'No model is ready. Pick or connect one in Setup, then try again.';
}
