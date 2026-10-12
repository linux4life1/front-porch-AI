// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// The mutable state one [CharacterGenService] shares across its stages:
/// the abort epoch, the per-run LLM switches, the narrative voice, and the
/// outputs a caller reads back after a run.
class GenRunState {
  GenRunState(this.llm);

  final LLMService llm;

  /// The raw LLM output from the last base card generation, for image prompt extraction.
  String? lastRawOutput;
  String? generatedImagePrompt;

  /// How the last generate run wrote its greetings. Null until a run
  /// reaches them.
  GreetingRecipe? greetingRecipe;

  int generationEpoch = 0;
  bool aborted = false;
  bool reasoningEnabled = false;

  /// Whether this run may tear down other in-flight work on the shared LLM
  /// service (the client abort at start + the server-side abort each step
  /// takes on local KoboldCpp). True for the interactive wizard (clear stuck
  /// state from a previous run); false for background runs like the Scene
  /// Guest mint, which must WAIT for the backend instead of killing the
  /// journal/growth/realism evals that legitimately share it.
  bool abortInFlight = true;

  /// Opt-in: when true, the lorebook + greeting prompts invite the model to add
  /// dynamic `{{pick}}`/`{{roll}}` "living detail" macros. Off by default —
  /// capable models use them well, weaker ones place them awkwardly.
  bool includeDynamicMacros = false;

  /// Greeting + example-dialog voice. Default first-person present matches
  /// the historical baked-in prompts. Set at the start of each generate run.
  NarrativeVoice narrativeVoice = NarrativeVoice.defaults;
  String narrativeSex = '';

  /// True once an abort ran or a newer run replaced the one at [epoch].
  bool isStale(int epoch) => aborted || generationEpoch != epoch;

  /// Start a new run: a fresh epoch, the abort flag cleared, and (when
  /// [abortInFlight]) the shared backend's in-flight request closed.
  /// Returns the new epoch.
  int beginRun({
    required bool abortInFlight,
    required bool reasoningEnabled,
    required bool includeDynamicMacros,
  }) {
    generationEpoch++;
    aborted = false;
    this.abortInFlight = abortInFlight;
    if (abortInFlight) llm.abortGeneration();
    this.reasoningEnabled = reasoningEnabled;
    this.includeDynamicMacros = includeDynamicMacros;
    return generationEpoch;
  }
}
