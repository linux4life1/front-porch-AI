// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/character_gen/gen_stages.dart';
import 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

/// Review-time rewrites of a generated card's example dialogue and
/// lorebook, each its own run from the card's text, steered by the author.
/// [card] is only read.
class GenReviewRewrites {
  GenReviewRewrites(this._s);

  final GenStages _s;
  GenRunState get _state => _s.state;

  /// New example dialogue for [card], written as creation wrote it (the
  /// same prompt and voice, [recipe]'s interview), steered by [direction].
  /// The name comes back as `{{char}}`. Null when stopped or when the model
  /// gave no usable exchanges.
  Future<String?> regenerateExampleDialogue({
    required CharacterCard card,
    GreetingRecipe recipe = const GreetingRecipe(),
    String direction = '',
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) async {
    final epoch = _s.beginCardRun(card, recipe, abortInFlight: abortInFlight);
    final name = card.name;
    final work = CharacterCard(
      name: name,
      personality: _expand(card.personality, name),
    );
    await _s.interview.generateExampleDialogue(
      card: work,
      name: name,
      interviewTranscript: recipe.interviewTranscript,
      direction: direction,
      onProgress: onProgress,
    );
    if (_state.isStale(epoch) || work.mesExample.trim().isEmpty) return null;
    return applyCharMacro(work.mesExample, name);
  }

  /// A new lorebook for [card] merged over its current one: entries the
  /// author edited by hand stay as written and in place, the generator's
  /// are replaced, and the book's settings are kept. Every entry the
  /// generator wrote now carries its fingerprint. Null when stopped or when
  /// the model wrote no entries.
  Future<Lorebook?> rewriteLorebook({
    required CharacterCard card,
    GreetingRecipe recipe = const GreetingRecipe(),
    required String concept,
    List<String> loreCategories = const [],
    String loreDepth = 'Standard',
    String direction = '',
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
  }) async {
    final epoch = _s.beginCardRun(card, recipe, abortInFlight: abortInFlight);
    final name = card.name;
    final work = CharacterCard(
      name: name,
      description: _expand(card.description, name),
      scenario: _expand(card.scenario, name),
    );
    await _s.lore.generateLorebookSeparately(
      card: work,
      name: name,
      concept: concept,
      loreCategories: loreCategories,
      loreDepth: loreDepth,
      interviewTranscript: recipe.interviewTranscript,
      worldLore: recipe.worldLore,
      direction: direction,
      onProgress: onProgress,
    );
    final generated = work.lorebook;
    if (_state.isStale(epoch) || generated == null) return null;
    stampLoreFingerprints(generated);
    final current = card.lorebook;
    return current == null
        ? generated
        : mergeRewrittenLorebook(current: current, generated: generated);
  }

  String _expand(String s, String name) => s.replaceAll('{{char}}', name);
}
