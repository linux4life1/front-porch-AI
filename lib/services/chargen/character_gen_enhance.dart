// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../character_gen_service.dart';

/// AI Enhance: re-run the creator pipeline for an EXISTING character, grounded
/// in a real chat, producing a detached result card the caller merges onto a
/// duplicate. This extension deliberately reuses the wizard's stages — the
/// interview, enrichment, dialogue, greeting, and lorebook steps are the SAME
/// methods the wizard calls, with the chat transcript riding their existing
/// context seams. The base-card JSON, truncation-recovery, and image-prompt
/// stages are skipped: the card already exists.
extension GenEnhance on CharacterGenService {
  /// Rewrite the [selection]-chosen text fields of [source] using
  /// [chatGrounding] (built by `buildChatExcerptBlock`) as the source of truth
  /// for voice and history.
  ///
  /// [source] is never mutated. The returned card carries the enhanced text
  /// fields (unselected ones keep [source]'s values verbatim); `lorebook` is
  /// non-null only when the selection asked for one. Returns null on abort or
  /// when nothing was selected.
  Future<CharacterCard?> enhanceCharacter({
    required CharacterCard source,
    required EnhanceSelection selection,
    required String chatGrounding,
    String userPersonaContext = '',
    String greetingLength = 'Medium (2-4 paragraphs)',
    bool nsfwEnabled = false,
    bool reasoningEnabled = false,
    bool abortInFlight = false,
    String? narrativePerspective,
    String? narrativeTense,
    String? sex,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) async {
    if (!selection.anySelected) return null;
    final name = source.name;

    // The stored card carries {{char}} macros (applyCharMacroToCard writes
    // them on save); expand them for prompting so the interview seed and
    // rewrite prompts read naturally, then re-normalize at the end.
    String expand(String s) => s.replaceAll('{{char}}', name);
    final card = CharacterCard(
      name: name,
      description: expand(source.description),
      personality: expand(source.personality),
      scenario: expand(source.scenario),
      firstMessage: source.firstMessage,
      mesExample: source.mesExample,
      alternateGreetings: List.from(source.alternateGreetings),
    );

    debugPrint(
      'CharacterGen: Enhancing "$name" (${selection.toJson()}, '
      'grounding ${chatGrounding.length} chars)',
    );
    _generationEpoch++;
    final int currentEpoch = _generationEpoch;
    _aborted = false;
    // Same reasoning as the Scene Guest mint: an enhance launched from the
    // home screen must not kill journal/growth/realism evals a background
    // chat may legitimately have in flight on the shared backend.
    _abortInFlight = abortInFlight;
    if (abortInFlight) _llmService.abortGeneration();
    _reasoningEnabled = reasoningEnabled;
    _includeDynamicMacros = false;
    // Keep the card's Create voice. Params override the stamp; omitted
    // (and unstamped cards) stay first-person present.
    final resolved = resolveEnhanceVoice(
      narrativePerspective: narrativePerspective,
      narrativeTense: narrativeTense,
      sex: sex,
      source: source,
    );
    _narrativeVoice = resolved.voice;
    _narrativeSex = resolved.sex;

    // ── Interview, grounded in the real chat (always runs) ─────────
    onStatus?.call('Interviewing $name about the chat...');
    onProgress?.call('');
    final interviewTranscript = await _runCharacterInterview(
      card: card,
      name: name,
      nsfwEnabled: nsfwEnabled,
      onStatus: onStatus,
      onProgress: onProgress,
      chatGrounding: chatGrounding,
    );
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Enrichment: one call rewrites description + personality + scenario ──
    if (selection.needsEnrichment && interviewTranscript.isNotEmpty) {
      onStatus?.call('Rewriting profile from the chat...');
      onProgress?.call('');
      final origDescription = card.description;
      final origPersonality = card.personality;
      await _enrichCardFromInterview(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        // Reuses the wizard's verbatim-scenario gate: an unselected scenario
        // is "user-authored" and must never drift.
        preserveUserScenario: !selection.scenario,
        chatGrounding: chatGrounding,
        onProgress: onProgress,
      );
      // The enrichment call rewrites all three fields at once (cheaper than
      // three calls); revert the ones the user did not ask to change.
      if (!selection.description) card.description = origDescription;
      if (!selection.personality) card.personality = origPersonality;
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Example dialogue, mined from real chat lines ─────────────
    if (selection.exampleDialogue && interviewTranscript.isNotEmpty) {
      onStatus?.call('Writing example dialogue from real lines...');
      onProgress?.call('');
      await _generateExampleDialogue(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        chatGrounding: chatGrounding,
        onProgress: onProgress,
      );
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Lorebook, grounded in the chat via the existing worldLore seam ──
    if (selection.lorebook) {
      onStatus?.call('Generating lorebook from the story so far...');
      onProgress?.call('');
      await _generateLorebookSeparately(
        card: card,
        name: name,
        concept: card.description,
        loreCategories: const [],
        loreDepth: 'Standard',
        interviewTranscript: interviewTranscript,
        worldLore: chatGrounding,
        onProgress: onProgress,
      );
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // ── Greetings: first message + as many alts as the source had ──
    if (selection.greetings) {
      onStatus?.call('Writing first message...');
      onProgress?.call('');
      final firstMsgPrompt = _buildGreetingPrompt(
        name: name,
        description: card.description,
        personality: card.personality,
        scenario: card.scenario,
        length: greetingLength,
        tone: 'Neutral',
        previousGreetings: [],
        // The chat grounding rides the existing characterContext seam — its
        // documented purpose ("weave these details naturally into the scene").
        characterContext: chatGrounding,
        userPersonaContext: userPersonaContext,
        interviewTranscript: interviewTranscript,
      );
      final firstMsgOutput = await _callLLM(
        firstMsgPrompt,
        maxLen: 4096,
        minLen: 512,
        onProgress: onProgress,
      );
      if (firstMsgOutput != null && firstMsgOutput.trim().isNotEmpty) {
        card.firstMessage = _cleanGreeting(firstMsgOutput);
      }
      if (_aborted || _generationEpoch != currentEpoch) return null;

      final altCount = source.alternateGreetings.length.clamp(0, 4);
      if (altCount > 0) {
        onStatus?.call('Planning alternate scenarios...');
        onProgress?.call('');
        final altScenarios = await _generateAltScenarios(
          name: name,
          concept: card.description,
          defaultScenario: card.scenario,
          personality: card.personality,
          count: altCount,
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
          final altPrompt = _buildGreetingPrompt(
            name: name,
            description: card.description,
            personality: card.personality,
            scenario: altScenario,
            length: greetingLength,
            tone: 'Neutral',
            previousGreetings: [card.firstMessage, ...alts],
            characterContext: chatGrounding,
            userPersonaContext: userPersonaContext,
            interviewTranscript: interviewTranscript,
          );
          final altOutput = await _callLLM(
            altPrompt,
            maxLen: 4096,
            minLen: 512,
            onProgress: onProgress,
          );
          if (altOutput != null && altOutput.trim().isNotEmpty) {
            alts.add(_cleanGreeting(altOutput));
          }
        }
        card.alternateGreetings = alts;
      }
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    // Same seed as AI Create, proposed not applied — Review's "Use this"
    // is what writes it onto the (Enhanced) duplicate.
    if (selection.porchLife) {
      onStatus?.call('Proposing wardrobe and ambitions...');
      onProgress?.call('');
      card.frontPorchExtensions =
          (source.frontPorchExtensions ??
                  FrontPorchExtensions(needsSimEnabled: true))
              .copyWith();
      await _seedPorchLifeIdentity(
        card: card,
        name: name,
        interviewTranscript: interviewTranscript,
        nsfwEnabled: nsfwEnabled,
        onProgress: onProgress,
      );
    }
    if (_aborted || _generationEpoch != currentEpoch) return null;

    applyCharMacroToCard(card, name);
    // Unselected fields must carry over BYTE-VERBATIM. The clone expanded
    // {{char}} and the macro pass above re-collapsed the name everywhere —
    // a round-trip that can rewrite text the user never asked to change
    // (hand-written names become {{char}}). The mid-run reverts above exist
    // so later prompts read the original persona; this restore exists so the
    // returned card carries the original bytes.
    if (!selection.description) card.description = source.description;
    if (!selection.personality) card.personality = source.personality;
    if (!selection.scenario) card.scenario = source.scenario;
    onStatus?.call('Character enhanced!');
    return card;
  }
}
