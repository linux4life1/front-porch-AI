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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Step 4, in all three modes: the first message and the alternates, one
/// card each (#370). Edit in place, rewrite one (steered by a line of
/// direction), add one, delete an alternate. One greeting is written at a
/// time; the rest wait. Each greeting's starting state stays on Review.
class GreetingsStep extends StatelessWidget {
  const GreetingsStep({super.key, required this.state});

  final CreatorState state;

  @override
  Widget build(BuildContext context) {
    if (state.generatedCard == null) return _failed(context);
    final g = state.greetings;
    final alts = state.altGreetingControllers;
    final adding = g.writingIndex == alts.length + 1;
    final atCap = alts.length >= CreatorGreetings.maxAlternates;
    LLMProvider llm() => Provider.of<LLMProvider>(context, listen: false);

    GreetingCard card(int index, TextEditingController? box) {
      final writing = g.writingIndex == index;
      return GreetingCard(
        key: box == null ? const ValueKey('greeting-adding') : ObjectKey(box),
        index: index,
        title: index == 0 ? 'First message' : 'Alternate $index',
        subtitle: index == 0 ? 'Opens every new chat' : null,
        box: box,
        steer: box == null ? null : g.steerFor(box),
        writing: writing,
        writingText: writing ? g.writingText : '',
        locked: g.busy && !writing,
        error: g.errorIndex == index ? g.errorText : null,
        onRegenerate: () =>
            state.regenerateGreeting(llmProvider: llm(), index: index),
        onStop: state.stopGreeting,
        onDelete: index == 0 ? null : () => state.deleteAlternate(index),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('greetings'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              _intro(context),
              card(0, state.firstMessageController),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _altHeader(context, alts.length),
              ),
              for (var i = 0; i < alts.length; i++) card(i + 1, alts[i]),
              if (adding) card(alts.length + 1, null),
              if (g.errorIndex == alts.length + 1 && !adding)
                GreetingErrorLine(text: g.errorText!),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GreetingAddButton(
                    key: const ValueKey('greeting-add'),
                    onPressed: g.busy || atCap
                        ? null
                        : () => state.addGreeting(llmProvider: llm()),
                  ),
                  Text(
                    'Writes a new one right away',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          'Greetings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        Text(
          'The first message opens every new chat. Alternates are other '
          'openings you can swipe to. Edit any of them, rewrite one, or '
          'steer a rewrite with a line of direction.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _altHeader(BuildContext context, int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: 10,
      children: [
        Text(
          'Alternate greetings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        Text(
          '$count of ${CreatorGreetings.maxAlternates}',
          key: const ValueKey('greeting-count'),
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  /// The generation produced nothing: the same retry the next steps offer.
  Widget _failed(BuildContext context) {
    return Center(
      key: const ValueKey('greetings-error'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.negativeAccentOf(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Generation failed. The LLM did not produce valid output.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              state.generationPreview = '';
              state.currentStep = 2;
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
            ),
          ),
        ],
      ),
    );
  }
}
