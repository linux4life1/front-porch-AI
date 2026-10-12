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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Scenario and first-message generation for the Create Group wizard. Returns
/// the cleaned text (possibly empty); the page owns the busy flags, snackbars
/// and the `mounted` checks.
class GroupOpeningGenerator {
  const GroupOpeningGenerator(this.service);

  final LLMService service;

  // ── AI GENERATION (adapted + improved from old dialog) ─────────────

  Future<String> scenario({
    required List<CharacterCard> members,
    String dynamicsContext = '',
  }) async {
    final briefs = members
        .map((c) {
          final trait = c.personality.isNotEmpty
              ? c.personality.split('.').first
              : c.name;
          return '${c.name} ($trait)';
        })
        .join(', ');

    final dynamicsCtx = dynamicsContext.isNotEmpty
        ? '\n\nHidden inter-character dynamics to reflect in the setting and atmosphere:\n$dynamicsContext\n\nIncorporate the emotional undercurrents between the characters into the description of the location and situation (without stating them directly).'
        : '';

    final prompt =
        '[Output ONLY the scenario text. No planning, reasoning, or explanation. '
        'Do NOT use <think> tags.]\n\n'
        'Write a brief scenario (1-2 sentences max) for a group roleplay with: $briefs.$dynamicsCtx\n'
        'The scenario should describe WHERE the characters are and WHAT is happening.\n'
        'Use {{user}} to refer to the player when appropriate. Keep it concise.\n\n'
        'SCENARIO: ';

    final buf = StringBuffer();
    final params = GenerationParams(
      prompt: prompt,
      maxLength: 420,
      temperature: 0.88,
      reasoningEnabled: false,
      reasoningMaxTokens: 0,
      mandatoryReasoningHeadroom: true,
      stopSequences: ['\n\n', 'END', '---', '<think>'],
    );
    await for (final tok in service.generateStream(params)) {
      buf.write(tok);
    }
    return _cleanThinkAndMarkers(buf.toString(), prefixMarkers: ['SCENARIO:']);
  }

  Future<String> firstMessage({
    required List<CharacterCard> members,
    required String scenario,
    required bool isDirector,
    String dynamicsContext = '',
  }) async {
    final descriptions = members
        .map((c) {
          final persona = c.personality.isNotEmpty
              ? c.personality
              : c.description;
          final scen = c.scenario.isNotEmpty ? ' Scenario: ${c.scenario}' : '';
          return '- ${c.name}: $persona$scen';
        })
        .join('\n');

    final scenarioCtx = scenario.trim().isNotEmpty
        ? '\nThe group scenario is: ${scenario.trim()}'
        : '';

    final dynamicsCtx = dynamicsContext.isNotEmpty
        ? '\n\n$dynamicsContext\n\nIMPORTANT INSTRUCTIONS FOR USING THE DYNAMICS:\n- These are the characters\' private, hidden feelings toward one another (the player does not know these feelings exist).\n- Use them to create natural tension, chemistry, coldness, protectiveness, jealousy, affection, etc. in the opening scene.\n- Show the dynamics through subtext, body language, tone of voice, who stands near whom, micro-expressions, and how characters speak to (or about) each other.\n- Never have a character explicitly state their numerical score or tier. Reveal it organically through behavior and dialogue.\n- Strong negative scores should create visible friction or wariness. Strong positive scores should create warmth, protectiveness, or instinctive closeness.'
        : '';

    final prompt = isDirector
        ? '[INSTRUCTIONS: Output ONLY the creative scene text. '
              'Do NOT plan, reason, analyze, or explain. Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
              'Write a vivid, immersive opening scene (3-5 paragraphs) for a DIRECTOR MODE group roleplay featuring:\n$descriptions$scenarioCtx$dynamicsCtx\n\n'
              'CRITICAL: There is NO user/player present. Characters interact ONLY with each other.\n'
              'Each character MUST have at least 2 lines of dialogue.\n'
              'Characters address and react to EACH OTHER.\n'
              'Use *asterisks* for actions.\n'
              'When done, write "END SCENE" on its own line.\n\n'
              'BEGIN SCENE:\n'
        : '[INSTRUCTIONS: Output ONLY the creative scene text. '
              'Do NOT plan, reason, analyze, or explain. Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
              'Write a vivid, immersive opening message (2-4 paragraphs) for a group roleplay featuring:\n$descriptions$scenarioCtx$dynamicsCtx\n\n'
              'The player ({{user}}) is present. Include natural dialogue from the characters and actions in *asterisks*.\n'
              'Keep it engaging and true to the characters.\n\n'
              'OPENING:\n';

    final buf = StringBuffer();
    final params = GenerationParams(
      prompt: prompt,
      maxLength: isDirector ? 1800 : 1200,
      temperature: 0.86,
      reasoningEnabled: false,
      reasoningMaxTokens: 0,
      mandatoryReasoningHeadroom: true,
      stopSequences: isDirector
          ? ['END SCENE', '---', '[END]', '<think>']
          : ['\n\n\n', '---', '<think>'],
    );
    await for (final tok in service.generateStream(params)) {
      buf.write(tok);
    }
    var result = _cleanThinkAndMarkers(
      buf.toString(),
      prefixMarkers: ['BEGIN SCENE:', 'OPENING:'],
    );
    if (isDirector) {
      result = result
          .split('\n')
          .where((line) {
            final t = line.trimLeft();
            return !t.startsWith('The user wants') &&
                !t.startsWith('I need to') &&
                !t.startsWith('I will') &&
                !RegExp(
                  r'^\d+\.\s+(Write|Use|Set|Make|Do|Keep|NOT|Create|End)',
                ).hasMatch(t);
          })
          .join('\n')
          .trim();
    }
    return result;
  }

  String _cleanThinkAndMarkers(
    String raw, {
    List<String> prefixMarkers = const [],
  }) {
    var s = stripThinkTags(raw).replaceAll('"', '').trim();
    for (final m in prefixMarkers) {
      s = s.replaceAll(RegExp('^$m\\s*', caseSensitive: false), '');
    }
    return s.trim();
  }
}
