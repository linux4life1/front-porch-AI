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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

/// Wizard step: story title + the concept the whole pipeline grows from, with
/// one-tap archetype seeds for the blank-page moment.
class ConceptStep extends StatefulWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const ConceptStep({super.key, required this.draft, required this.onChanged});

  @override
  State<ConceptStep> createState() => _ConceptStepState();
}

class _ConceptStepState extends State<ConceptStep> {
  List<Map<String, String>> _archetypes = [];

  @override
  void initState() {
    super.initState();
    _archetypes = StoryPipelineService.generateArchetypes(count: 6);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader('Story Identity', Icons.edit_note),
        const SizedBox(height: 12),
        _textField(context, draft.titleController, 'Story title...'),
        const SizedBox(height: 12),
        _textField(
          context,
          draft.conceptController,
          'What is the story about? Be as detailed as you want...\n\n'
          'Examples:\n'
          '• A cyberpunk heist gone wrong in neon-drenched Tokyo\n'
          '• A slow-burn romance between rival guild leaders\n'
          '• An ancient war told from both sides',
          maxLines: 7,
        ),
        const SizedBox(height: 10),
        Text(
          'Quick concepts:',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._archetypes.map(
              (a) => SetupChip(
                a['label']!,
                selected: false,
                onTap: () {
                  draft.conceptController.text = a['value']!;
                  widget.onChanged();
                },
              ),
            ),
            ActionChip(
              avatar: Icon(
                Icons.refresh,
                size: 14,
                color: AppColors.iconSecondary(context),
              ),
              label: Text(
                'Refresh',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
              backgroundColor: Colors.transparent,
              side: BorderSide.none,
              onPressed: () => setState(
                () => _archetypes = StoryPipelineService.generateArchetypes(
                  count: 6,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _textField(
    BuildContext context,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
  }) {
    return AppTextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: AppColors.textPrimary(context)),
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        filled: true,
        fillColor: AppColors.cardOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}
