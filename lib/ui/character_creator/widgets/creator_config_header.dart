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

import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/template_dialogs.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Configure step's header in every mode (docs/design/creator-ui-spec.md,
/// "Configure header"): the page title and intro, the `Started from` pill
/// and its caption when the form was loaded from a template, and at the
/// right the `Save as template` button, which is always there so a blank
/// form can become the first template.
class CreatorConfigHeader extends StatelessWidget {
  const CreatorConfigHeader({
    super.key,
    required this.state,
    required this.title,
    required this.intro,
  });

  final CreatorState state;
  final String title;
  final String intro;

  @override
  Widget build(BuildContext context) {
    final started = state.templates.startedFrom;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.inkOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                intro,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
              if (started != null) ...[
                const SizedBox(height: 10),
                _startedFrom(context, started.name),
              ],
            ],
          ),
        ),
        _SaveAsTemplateButton(state: state),
      ],
    );
  }

  Widget _startedFrom(BuildContext context, String name) {
    final amber = StudioColors.amberOf(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          key: const ValueKey('template-started-pill'),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(Icons.bookmark_border, size: 14, color: amber),
              Flexible(
                child: Text(
                  'Started from: $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: amber,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          'Changes stay on this form until you save them to the template.',
          key: const ValueKey('template-started-caption'),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 0,
            color: StudioColors.faintOf(context),
          ),
        ),
      ],
    );
  }
}

/// The spec's outlined action button with a bookmark: 44px, 16px padding,
/// radius 12, 1.5px amber, amber 14 / 700.
class _SaveAsTemplateButton extends StatelessWidget {
  const _SaveAsTemplateButton({required this.state});

  final CreatorState state;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        key: const ValueKey('template-save-button'),
        onPressed: () => showSaveTemplateDialog(context, state),
        icon: const Icon(Icons.bookmark_border, size: 18),
        // On the Text, so the label keeps the theme's font.
        label: const Text(
          'Save as template',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: amber,
          side: BorderSide(color: amber, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
