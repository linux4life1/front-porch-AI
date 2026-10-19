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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart' show ProfileField;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Step 4, in all three modes (#530): the profile Phase A wrote, read
/// before anything else is built. Edit any box, or steer a rewrite of
/// Description and Personality; the facts card follows the profile. Next
/// writes the rest (docs/design/creator-ui-spec.md, "Profile step").
class ProfileStep extends StatelessWidget {
  const ProfileStep({super.key, required this.state});

  final CreatorState state;

  @override
  Widget build(BuildContext context) {
    final p = state.profile;
    final paused = p.paused;
    if (state.generatedCard == null || paused == null) return _failed(context);
    LLMProvider llm() => Provider.of<LLMProvider>(context, listen: false);
    final s = p.stream;
    final rewriting = p.rewriting;
    final kept = paused.inputs.descriptionOverride != null;
    final descStarted = s.started(ProfileField.description);
    final persStarted = s.started(ProfileField.personality);
    final scenStarted = s.started(ProfileField.scenario);
    // The engine keeps a scenario the user typed; a generated one is
    // rewritten with the rest, third in the stream.
    final scenKept = paused.inputs.userScenario;

    return SingleChildScrollView(
      key: const ValueKey('profile'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              _intro(context, paused.interviewTranscript.trim().isNotEmpty),
              CreatorTextCard(
                title: 'Description',
                subtitle: 'Who they are, as the card will carry it',
                controller: state.descController,
                boxKey: const ValueKey('profile-box-description'),
                onChanged: (_) => state.scheduleSave(),
                writingText: rewriting && !kept
                    ? (descStarted ? s.description : state.descController.text)
                    : null,
                caret:
                    descStarted &&
                    !s.finished.contains(ProfileField.description),
                status: !rewriting
                    ? null
                    : kept
                    ? 'Kept as you built it'
                    : 'Writing…',
                statusAmber: !kept,
                locked: rewriting && kept,
              ),
              CreatorTextCard(
                title: 'Personality',
                subtitle: 'How they act and speak',
                controller: state.personalityController,
                boxKey: const ValueKey('profile-box-personality'),
                onChanged: (_) => state.scheduleSave(),
                writingText: rewriting
                    ? (persStarted
                          ? s.personality
                          : state.personalityController.text)
                    : null,
                caret:
                    persStarted &&
                    !s.finished.contains(ProfileField.personality),
                status: !rewriting
                    ? null
                    : persStarted
                    ? 'Writing…'
                    : kept
                    ? 'Waiting…'
                    : 'Waiting for the description…',
                statusAmber: persStarted,
              ),
              CreatorTextCard(
                title: 'Scenario',
                subtitle: 'Where the first chat starts',
                controller: state.scenarioController,
                boxKey: const ValueKey('profile-box-scenario'),
                onChanged: (_) => state.scheduleSave(),
                writingText: rewriting && !scenKept
                    ? (scenStarted ? s.scenario : state.scenarioController.text)
                    : null,
                caret:
                    scenStarted && !s.finished.contains(ProfileField.scenario),
                status: !rewriting
                    ? null
                    : scenKept
                    ? 'Kept as it is'
                    : scenStarted
                    ? 'Writing…'
                    : 'Waiting…',
                statusAmber: !scenKept && scenStarted,
                locked: rewriting && scenKept,
              ),
              _rewriteCard(context, llm),
              ProfileFactsCard(
                state: state,
                onReread: () => state.rereadFacts(llmProvider: llm()),
              ),
              // No questions, no interview: nothing to show.
              if (paused.interviewTranscript.trim().isNotEmpty)
                InterviewTranscriptRow(
                  transcript: paused.interviewTranscript,
                  open: p.transcriptOpen,
                  enabled: !rewriting,
                  onToggle: () {
                    p.transcriptOpen = !p.transcriptOpen;
                    state.notify();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rewriteCard(BuildContext context, LLMProvider Function() llm) {
    final p = state.profile;
    return Container(
      key: const ValueKey('profile-rewrite-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      child: ReviewRewriteRow(
        id: 'profile-rewrite',
        steer: p.steer,
        hint:
            'What is wrong or missing? e.g. Does not follow the Tsundere personality type',
        action: 'Rewrite the profile',
        writing: p.rewriting,
        locked: p.rereadingFacts || p.continuing,
        grows: true,
        onRun: () => state.rewriteProfile(llmProvider: llm()),
        onStop: state.stopProfile,
        caption: p.rewriting
            ? 'Writing a new Description, then a new Personality, then '
                  're-reading the facts below. Stop keeps the old text '
                  'everywhere.'
            : 'Rewrites Description and Personality from the interview and '
                  'your direction, then re-reads the facts below from the new '
                  'profile. The box grows as you type. A scenario you typed '
                  'yourself is kept.',
        error: p.rewriting ? null : p.error,
      ),
    );
  }

  Widget _intro(BuildContext context, bool hadInterview) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Text(
        'Profile',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: StudioColors.inkOf(context),
        ),
      ),
      Text(
        'This is who ${hadInterview ? 'the interview' : 'your settings'} '
        'wrote. Read it before anything else is built: the greetings, lore, '
        'outfit and picture prompt are written after you press Next. Edit any '
        'box by hand, or tell the rewrite what is wrong.',
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: StudioColors.mutedOf(context),
        ),
      ),
    ],
  );

  /// The generation produced nothing: the same retry the next steps offer.
  Widget _failed(BuildContext context) => Center(
    key: const ValueKey('profile-error'),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 16,
      children: [
        Icon(Icons.error_outline, size: 64, color: StudioColors.badOf(context)),
        Text(
          state.generationStatus.isEmpty
              ? 'Generation failed. The LLM did not produce valid output.'
              : state.generationStatus,
          textAlign: TextAlign.center,
          style: TextStyle(color: StudioColors.proseOf(context), fontSize: 16),
        ),
        ElevatedButton.icon(
          onPressed: () {
            state.generationPreview = '';
            // A retry must never see a stale pause or stream.
            state.profile.reset();
            state.currentStep = 2;
          },
          icon: const Icon(Icons.arrow_back),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioColors.amberOf(context),
            foregroundColor: StudioColors.amberInkOf(context),
          ),
        ),
      ],
    ),
  );
}
