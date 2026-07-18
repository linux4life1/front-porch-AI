// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for RealismPromptBuilder — the single source of truth for the Realism
// Engine judge prompts (character dossier + standing context + the shared
// bond/trust/emotion/arousal/objective/fixation fragments composed into the
// relationship / emotional / narrative / one-shot prompts).
//
// Focus: dossier budgeting and priority (personality > growth tail >
// description, sentence-boundary trims, empty fallback), the personality-true
// rubric (subjective valence, no objective-morality gates, no trust floor),
// interpolated ranges matching the clamp constants, and one-shot vs
// multi-call textual parity by construction.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';

void main() {
  group('RealismPromptBuilder.characterDossier', () {
    test('returns empty string when there is nothing to say', () {
      expect(
        RealismPromptBuilder.characterDossier(
          name: 'X',
          personality: '  ',
          description: '',
        ),
        '',
      );
    });

    test('personality-only card is included whole with the judge framing', () {
      final d = RealismPromptBuilder.characterDossier(
        name: 'Vera',
        personality: 'Prickly, proud, allergic to pity.',
        description: '',
      );
      expect(d, contains('Who Vera is'));
      expect(d, contains('Prickly, proud, allergic to pity.'));
    });

    test('falls back to description when the personality field is empty', () {
      final d = RealismPromptBuilder.characterDossier(
        name: 'Vera',
        personality: '',
        description: 'A dominant duelist who despises coddling.',
      );
      expect(d, contains('despises coddling'));
    });

    test('growth is labeled and keeps its most recent tail when long', () {
      final oldGrowth = List.filled(40, 'Old growth sentence.').join(' ');
      final d = RealismPromptBuilder.characterDossier(
        name: 'Vera',
        personality: 'Proud.',
        description: '',
        growth: '$oldGrowth Learned to accept LATEST_MARKER help.',
      );
      expect(d, contains('genuinely changed'));
      expect(d, contains('LATEST_MARKER'));
    });

    test(
      'pathological card stays within budget and trims at a sentence boundary',
      () {
        final hugePersonality = List.filled(200, 'Sharp sentence here.').join(' ');
        final hugeDescription = List.filled(400, 'Endless lore text.').join(' ');
        final d = RealismPromptBuilder.characterDossier(
          name: 'Vera',
          personality: hugePersonality,
          description: hugeDescription,
        );
        // Budget plus framing/label overhead — must not ship 10k-char prompts.
        expect(d.length, lessThan(RealismPromptBuilder.kDossierBudget + 400));
        // Sentence-boundary trim: the cut ends on a completed sentence + ellipsis.
        expect(d, contains('. …'));
        expect(d.contains('Sharp sentence here.'), true);
        expect(d.contains('Endless lore text.'), true);
      },
    );

    test('a long description cannot squeeze out the growth slice', () {
      final d = RealismPromptBuilder.characterDossier(
        name: 'Vera',
        personality: 'Proud.',
        description: List.filled(400, 'Endless lore text.').join(' '),
        growth: 'Recently softened toward GROWTH_MARKER honesty.',
      );
      expect(d, contains('GROWTH_MARKER'));
    });
  });

  group('standingContext', () {
    test('formats tiers, trust, and optional mood/posture', () {
      final s = RealismPromptBuilder.standingContext(
        charName: 'Vera',
        userName: 'User',
        shortTermTier: 'Cool',
        longTermTier: 'Reserved',
        trustTier: 'Guarded',
        trustLevel: -12,
        emotion: 'prickly',
        emotionIntensity: 'moderate',
        posture: 'arms crossed by the door',
      );
      expect(s, contains('"Cool"'));
      expect(s, contains('"Reserved"'));
      expect(s, contains('"Guarded" (-12/100)'));
      expect(s, contains('prickly (moderate)'));
      expect(s, contains('arms crossed by the door'));
      expect(s, contains('thaws in inches'));
    });

    test('omits mood and posture cleanly when absent', () {
      final s = RealismPromptBuilder.standingContext(
        charName: 'Vera',
        userName: 'User',
        shortTermTier: 'Neutral',
        longTermTier: 'Neutral',
        trustTier: 'Neutral',
        trustLevel: 0,
      );
      expect(s.contains('current mood'), false);
      expect(s.contains('Position:'), false);
    });
  });

  group('judge prompts (personality-true rubric)', () {
    String rel() => RealismPromptBuilder.relationshipEvalPrompt(
      charName: 'Vera',
      userName: 'User',
      dossier: 'DOSSIER\n',
      standing: 'STANDING\n',
      recent: 'User: hey',
    );

    String oneShot({bool arousal = false}) =>
        RealismPromptBuilder.oneShotEvalPrompt(
          charName: 'Vera',
          userName: 'User',
          dossier: 'DOSSIER\n',
          standing: 'STANDING\n',
          recent: 'User: hey',
          arousalEnabled: arousal,
          arousalLevel: 10,
        );

    test('ranges interpolate from the clamp constants (no drift possible)', () {
      final p = rel();
      expect(
        p,
        contains('($kMinRelationshipDelta to +$kMaxRelationshipDelta)'),
      );
      expect(p, contains('($kMinTrustDelta to +$kMaxTrustDelta)'));
    });

    test(
      'subjective valence: negatives allowed for boundary-trampling kindness; no objective gates; no trust floor',
      () {
        final p = rel();
        expect(p, contains('trample their boundaries'));
        expect(p, contains('an angle being worked'));
        expect(p, contains('unearned familiarity or smothering'));
        expect(p.contains('Only go negative if'), false);
        expect(p.contains('Reserve negative scores ONLY'), false);
        expect(p.contains('Trust that never moves is a bug'), false);
        expect(p.contains('give it at least +1'), false);
        // The self-action guard survives (good rule, not a coercive one).
        expect(p, contains('If Vera is the one who lied'));
      },
    );

    test(
      'one-shot embeds the exact bond+trust rubric of the relationship prompt',
      () {
        final p = rel();
        final o = oneShot();
        final start = p.indexOf('- "relationship_delta"');
        final end = p.indexOf('\nRecent conversation:');
        final rubric = p.substring(start, end);
        expect(o.contains(rubric), true);
      },
    );

    test('arousal section appears only when enabled and is desire-gated', () {
      expect(oneShot().contains('arousal_delta'), false);
      final withArousal = oneShot(arousal: true);
      expect(withArousal, contains('"arousal_delta"'));
      expect(withArousal, contains('10/100'));
      expect(withArousal, contains('feels intruded on'));
    });

    test('emotional prompt: label constraint only when labels are given', () {
      final free = RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Vera',
        userName: 'User',
        dossier: '',
        standing: '',
        recent: 'User: hey',
        arousalEnabled: false,
        arousalLevel: 0,
      );
      expect(free.contains('EXACTLY ONE of these labels'), false);
      final constrained = RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Vera',
        userName: 'User',
        dossier: '',
        standing: '',
        recent: 'User: hey',
        arousalEnabled: false,
        arousalLevel: 0,
        allowedEmotionLabels: const ['happy', 'prickly'],
      );
      expect(
        constrained,
        contains('EXACTLY ONE of these labels: happy, prickly'),
      );
    });

    test('narrative prompt varies by primary objective and stays in character', () {
      final noPrimary = RealismPromptBuilder.narrativeEvalPrompt(
        charName: 'Vera',
        userName: 'User',
        dossier: 'DOSSIER\n',
        recent: 'User: hey',
      );
      expect(noPrimary, contains('OVERARCHING goal'));
      expect(noPrimary, contains('not generic story beats'));
      final withPrimary = RealismPromptBuilder.narrativeEvalPrompt(
        charName: 'Vera',
        userName: 'User',
        dossier: 'DOSSIER\n',
        recent: 'User: hey',
        primaryObjective: 'win the duel',
      );
      expect(withPrimary, contains('DISTINCT from their current main quest ("win the duel")'));
    });

    test('JSON instruction lists the exact keys per prompt', () {
      expect(
        rel(),
        contains(
          'containing "relationship_delta", "bond_reason", "trust_delta", "trust_reason"',
        ),
      );
      final o = oneShot(arousal: true);
      expect(o, contains('"posture"'));
      expect(o, contains('"proposed_objective"'));
      expect(o, contains('"fixation_topic"'));
      expect(o, contains('"reason"'));
    });
  });
}
