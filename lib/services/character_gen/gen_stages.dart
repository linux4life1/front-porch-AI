// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/character_gen/gen_interview_steps.dart';
import 'package:front_porch_ai/services/character_gen/gen_llm_caller.dart';
import 'package:front_porch_ai/services/character_gen/gen_lore_steps.dart';
import 'package:front_porch_ai/services/character_gen/gen_porch_life.dart';
import 'package:front_porch_ai/services/character_gen/gen_prompts.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';

/// The stages one service run shares, all bound to the same [GenRunState].
/// The create, enhance, and single-greeting pipelines are built on these.
class GenStages {
  GenStages(this.state) : llm = GenLlmCaller(state) {
    interview = GenInterviewSteps(state, llm);
    lore = GenLoreSteps(state, llm);
    porchLife = GenPorchLife(state, llm);
  }

  final GenRunState state;
  final GenLlmCaller llm;
  late final GenInterviewSteps interview;
  late final GenLoreSteps lore;
  late final GenPorchLife porchLife;

  /// [buildGreetingPrompt] with this run's voice and macro switch.
  String greetingPrompt({
    required String name,
    required String description,
    required String personality,
    required String scenario,
    required String length,
    required String tone,
    required List<String> previousGreetings,
    String characterContext = '',
    String userPersonaContext = '',
    String interviewTranscript = '',
    String? worldLore,
    String direction = '',
  }) => buildGreetingPrompt(
    voice: state.narrativeVoice,
    narrativeSex: state.narrativeSex,
    includeDynamicMacros: state.includeDynamicMacros,
    name: name,
    description: description,
    personality: personality,
    scenario: scenario,
    length: length,
    tone: tone,
    previousGreetings: previousGreetings,
    characterContext: characterContext,
    userPersonaContext: userPersonaContext,
    interviewTranscript: interviewTranscript,
    worldLore: worldLore,
    direction: direction,
  );
}
