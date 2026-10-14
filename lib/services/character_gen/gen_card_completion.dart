// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_parsing.dart';
import 'package:front_porch_ai/services/character_gen/gen_paused_run.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/character_gen/gen_stages.dart';
import 'package:front_porch_ai/services/character_gen/greeting_recipe.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

/// Phase B of AI Create: everything written after the profile is read
/// (example dialogue, lorebook, greetings, the opening scene, the image
/// prompt, and the stamps).
class GenCardCompletion {
  GenCardCompletion(this._s);

  final GenStages _s;
  GenRunState get _state => _s.state;

  /// Finish [paused] as its own run: its voice, a fresh epoch, and a copy
  /// of its card, so a Stop here leaves the pause as it was.
  Future<CharacterCard?> complete({
    required GenPausedRun paused,
    required bool abortInFlight,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) async {
    final inputs = paused.inputs;
    _state.narrativeVoice = NarrativeVoice.parse(
      perspective: inputs.narrativePerspective,
      tense: inputs.narrativeTense,
    );
    _state.narrativeSex = inputs.sex;
    // Read the card back first: an unreadable pause must not stop whatever
    // the backend is doing or open a run for nothing.
    final card = GenPausedRun.copyCard(paused.card.toJson());
    if (card == null) {
      onError?.call('The paused character could not be read back.');
      return null;
    }
    final epoch = _state.beginRun(
      abortInFlight: abortInFlight,
      reasoningEnabled: inputs.reasoningEnabled,
      includeDynamicMacros: inputs.includeDynamicMacros,
    );
    return finish(
      paused: paused,
      card: card,
      epoch: epoch,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }

  /// The Phase B steps on [card] within run [epoch]. Null when stopped.
  Future<CharacterCard?> finish({
    required GenPausedRun paused,
    required CharacterCard card,
    required int epoch,
    void Function(String accumulated)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final inputs = paused.inputs;
    final name = inputs.name;
    final transcript = paused.interviewTranscript;

    // ── Example dialogue (dedicated step) ────────────────────────
    // After enrichment so it reads the final personality. Raw text, not JSON.
    if (transcript.isNotEmpty) {
      onStatus?.call('Writing example dialogue...');
      onProgress?.call('');
      await _s.interview.generateExampleDialogue(
        card: card,
        name: name,
        interviewTranscript: transcript,
        onProgress: onProgress,
      );
    }
    if (_state.isStale(epoch)) return null;

    // ── Lorebook (after the interview, if not written inline) ─────
    if (inputs.generateLorebook &&
        (card.lorebook == null || card.lorebook!.entries.isEmpty)) {
      debugPrint('CharacterGen: Generating lorebook after interview...');
      onStatus?.call('Generating world lore...');
      onProgress?.call('');
      await _s.lore.generateLorebookSeparately(
        card: card,
        name: name,
        concept: inputs.concept,
        loreCategories: inputs.loreCategories,
        loreDepth: inputs.loreDepth,
        interviewTranscript: transcript,
        worldLore: inputs.worldLore,
        onProgress: onProgress,
      );
    }
    if (_state.isStale(epoch)) return null;

    // Kept so the creator's Greetings step can write one more greeting the
    // way these were written (regenerateGreeting).
    _state.greetingRecipe = inputs.recipe(transcript);

    // ── First message ─────────────────────────────────────────
    final tones = inputs.greetingTones;
    onStatus?.call('Writing first message...');
    onProgress?.call('');
    final firstOut = await _s.llm.call(
      _greeting(
        paused,
        card,
        scenario: card.scenario,
        tone: tones.isNotEmpty ? tones[0] : 'Neutral',
        previous: const [],
      ),
      maxLen: 4096,
      minLen: 512,
      onProgress: onProgress,
    );
    if (firstOut != null && firstOut.trim().isNotEmpty) {
      card.firstMessage = cleanGeneratedGreeting(firstOut);
    }
    if (_state.isStale(epoch)) return null;

    // ── Alternate greetings, each from its own meeting scenario ───
    final altCount = inputs.altGreetingCount;
    if (altCount > 0) {
      onStatus?.call('Planning alternate scenarios...');
      onProgress?.call('');
      final altScenarios = await _s.interview.generateAltScenarios(
        name: name,
        concept: inputs.concept,
        defaultScenario: card.scenario,
        personality: card.personality,
        count: altCount,
        worldLore: inputs.worldLore,
        onProgress: onProgress,
      );
      final alts = <String>[];
      for (int i = 0; i < altCount; i++) {
        onStatus?.call('Writing alternate greeting ${i + 1} of $altCount...');
        onProgress?.call('');
        final altScenario =
            (i < altScenarios.length && altScenarios[i].isNotEmpty)
            ? altScenarios[i]
            : card.scenario;
        final altOut = await _s.llm.call(
          _greeting(
            paused,
            card,
            scenario: altScenario,
            tone: tones.isNotEmpty ? tones[(i + 1) % tones.length] : 'Neutral',
            previous: [card.firstMessage, ...alts],
          ),
          maxLen: 4096,
          minLen: 512,
          onProgress: onProgress,
        );
        if (altOut != null && altOut.trim().isNotEmpty) {
          alts.add(cleanGeneratedGreeting(altOut));
        }
      }
      // Seeds are not authored with these rewritten alts — compact against
      // empty so leftover source furious cannot land on Get out.
      card.assignRewrittenAlternateGreetings(alts);
    }
    if (_state.isStale(epoch)) return null;

    // ── The opening scene: outfit, pockets, mood, time ────────────
    // After the greeting so they match the opening beat. The identity facts
    // pass already wrote the lists; this merges, never wipes them. When it
    // wrote nothing (skipped for a Scene Guest, or it answered nothing) this
    // asks for the lists itself.
    onStatus?.call('Seeding wardrobe and ambitions...');
    onProgress?.call('');
    await _s.porchLife.seedIdentity(
      card: card,
      name: name,
      interviewTranscript: transcript,
      nsfwEnabled: inputs.nsfwEnabled,
      identityDone: paused.facts != null,
      onProgress: onProgress,
    );
    if (_state.isStale(epoch)) return null;

    // ── Tailored image prompt ─────────────────────────────────
    onStatus?.call('Drafting illustration prompt...');
    onProgress?.call('');
    _state.generatedImagePrompt = await _s.lore.generateImagePrompt(
      name: name,
      description: card.description,
      scenario: card.scenario,
      artStyle: inputs.artStyle,
      imageGenPromptParadigm: inputs.imageGenPromptParadigm,
      onProgress: onProgress,
    );

    // Models don't reliably emit {{char}} even when told to, and a literal
    // name baked into the card can confuse models mid-chat.
    applyCharMacroToCard(card, name);
    stampNarrativeVoice(
      card,
      voice: _state.narrativeVoice,
      sex: _state.narrativeSex,
    );
    // Beside the voice: how the greetings were written, and from which
    // profile, so a rewrite after a reload or a restart matches them and a
    // later profile rewrite can say the greetings are out of date.
    final recipe = _state.greetingRecipe?.withProfileFingerprint(
      profileFingerprintOf(card.description, card.personality, name: name),
    );
    _state.greetingRecipe = recipe;
    if (recipe != null) stampGreetingRecipe(card, recipe);
    stampLoreFingerprints(card.lorebook);

    onStatus?.call('Character generated!');
    return card;
  }

  String _greeting(
    GenPausedRun paused,
    CharacterCard card, {
    required String scenario,
    required String tone,
    required List<String> previous,
  }) {
    final inputs = paused.inputs;
    return _s.greetingPrompt(
      name: inputs.name,
      description: card.description,
      personality: card.personality,
      scenario: scenario,
      length: inputs.greetingLength,
      tone: tone,
      previousGreetings: previous,
      characterContext: inputs.characterContext,
      userPersonaContext: inputs.userPersonaContext,
      interviewTranscript: paused.interviewTranscript,
      worldLore: inputs.worldLore,
    );
  }
}
