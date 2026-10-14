// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';

/// Everything one AI Create run is asked for, as one value: the form's
/// answers and switches, without the callbacks. A paused run keeps it so
/// the second phase, and every rewrite after it, writes the way the first
/// phase was asked to. Defaults are `generateCharacter`'s.
class GenRunInputs {
  const GenRunInputs({
    required this.name,
    required this.concept,
    this.personalityKeywords = '',
    this.artStyle = '',
    this.imageGenPromptParadigm = 'natural',
    this.greetingLength = 'Medium (2-4 paragraphs)',
    this.altGreetingCount = 2,
    this.greetingTones = const ['Neutral'],
    this.generateLorebook = true,
    this.loreCategories = const [],
    this.loreDepth = 'Standard',
    this.apiSystemPrompt = '',
    this.age = '',
    this.sex = '',
    this.relationship = '',
    this.descriptionDetail = '2-3 paragraphs',
    this.backstory = '',
    this.scenario = '',
    this.characterContext = '',
    this.userPersonaContext = '',
    this.worldLore,
    this.generateDescription = false,
    this.nsfwEnabled = false,
    this.reasoningEnabled = false,
    this.includeDynamicMacros = false,
    this.narrativePerspective = 'first',
    this.narrativeTense = 'present',
    this.descriptionOverride,
  });

  final String name;
  final String concept;
  final String personalityKeywords;
  final String artStyle;
  final String imageGenPromptParadigm;
  final String greetingLength;
  final int altGreetingCount;
  final List<String> greetingTones;
  final bool generateLorebook;
  final List<String> loreCategories;
  final String loreDepth;
  final String apiSystemPrompt;
  final String age;
  final String sex;
  final String relationship;
  final String descriptionDetail;
  final String backstory;
  final String scenario;
  final String characterContext;
  final String userPersonaContext;
  final String? worldLore;
  final bool generateDescription;
  final bool nsfwEnabled;
  final bool reasoningEnabled;
  final bool includeDynamicMacros;
  final String narrativePerspective;
  final String narrativeTense;

  /// The Automated mode's description, written verbatim over the model's
  /// once the profile is rewritten. Null keeps the model's.
  final String? descriptionOverride;

  /// The user typed a scenario: it is kept word for word, never rewritten.
  bool get userScenario => scenario.trim().isNotEmpty;

  /// How these inputs write greetings, from [transcript].
  GreetingRecipe recipe(String transcript) => GreetingRecipe(
    greetingLength: greetingLength,
    tones: greetingTones,
    characterContext: characterContext,
    userPersonaContext: userPersonaContext,
    interviewTranscript: transcript,
    worldLore: worldLore,
    includeDynamicMacros: includeDynamicMacros,
    reasoningEnabled: reasoningEnabled,
    nsfwEnabled: nsfwEnabled,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'concept': concept,
    'personalityKeywords': personalityKeywords,
    'artStyle': artStyle,
    'imageGenPromptParadigm': imageGenPromptParadigm,
    'greetingLength': greetingLength,
    'altGreetingCount': altGreetingCount,
    'greetingTones': greetingTones,
    'generateLorebook': generateLorebook,
    'loreCategories': loreCategories,
    'loreDepth': loreDepth,
    'apiSystemPrompt': apiSystemPrompt,
    'age': age,
    'sex': sex,
    'relationship': relationship,
    'descriptionDetail': descriptionDetail,
    'backstory': backstory,
    'scenario': scenario,
    'characterContext': characterContext,
    'userPersonaContext': userPersonaContext,
    'worldLore': worldLore,
    'generateDescription': generateDescription,
    'nsfwEnabled': nsfwEnabled,
    'reasoningEnabled': reasoningEnabled,
    'includeDynamicMacros': includeDynamicMacros,
    'narrativePerspective': narrativePerspective,
    'narrativeTense': narrativeTense,
    'descriptionOverride': descriptionOverride,
  };

  /// [toJson] read back; a missing or odd value takes the default.
  factory GenRunInputs.fromJson(Map<String, dynamic> j) {
    const d = GenRunInputs(name: '', concept: '');
    String s(String k, String or) => j[k] is String ? j[k] as String : or;
    bool b(String k, bool or) => j[k] is bool ? j[k] as bool : or;
    List<String> l(String k, List<String> or) =>
        j[k] is List ? [for (final v in j[k] as List) '$v'] : or;
    return GenRunInputs(
      name: s('name', ''),
      concept: s('concept', ''),
      personalityKeywords: s('personalityKeywords', d.personalityKeywords),
      artStyle: s('artStyle', d.artStyle),
      imageGenPromptParadigm: s(
        'imageGenPromptParadigm',
        d.imageGenPromptParadigm,
      ),
      greetingLength: s('greetingLength', d.greetingLength),
      altGreetingCount: j['altGreetingCount'] is num
          ? (j['altGreetingCount'] as num).toInt()
          : d.altGreetingCount,
      greetingTones: l('greetingTones', d.greetingTones),
      generateLorebook: b('generateLorebook', d.generateLorebook),
      loreCategories: l('loreCategories', d.loreCategories),
      loreDepth: s('loreDepth', d.loreDepth),
      apiSystemPrompt: s('apiSystemPrompt', d.apiSystemPrompt),
      age: s('age', d.age),
      sex: s('sex', d.sex),
      relationship: s('relationship', d.relationship),
      descriptionDetail: s('descriptionDetail', d.descriptionDetail),
      backstory: s('backstory', d.backstory),
      scenario: s('scenario', d.scenario),
      characterContext: s('characterContext', d.characterContext),
      userPersonaContext: s('userPersonaContext', d.userPersonaContext),
      worldLore: j['worldLore'] is String ? j['worldLore'] as String : null,
      generateDescription: b('generateDescription', d.generateDescription),
      nsfwEnabled: b('nsfwEnabled', d.nsfwEnabled),
      reasoningEnabled: b('reasoningEnabled', d.reasoningEnabled),
      includeDynamicMacros: b('includeDynamicMacros', d.includeDynamicMacros),
      narrativePerspective: s('narrativePerspective', d.narrativePerspective),
      narrativeTense: s('narrativeTense', d.narrativeTense),
      descriptionOverride: j['descriptionOverride'] is String
          ? j['descriptionOverride'] as String
          : null,
    );
  }
}
