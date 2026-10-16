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

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/template_dialogs.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/template_tile.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// `Start from a template` above the Mode step's mode cards
/// (docs/design/creator-ui-spec.md, "Template picker card"): yours newest
/// first, then Tsundere and Kuudere, then `All 15 built in`. Picking one
/// fills the form and sets the mode; the mode cards below start blank.
class TemplatePickerCard extends StatelessWidget {
  const TemplatePickerCard({super.key, required this.state, this.now});

  final CreatorState state;

  /// "Now" for the saved labels; a test pins it.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final templates = state.templates;
    final start = templates.startedFrom;
    bool picked(CreatorTemplate t) =>
        start != null && start.slug == t.slug && start.builtIn == t.builtIn;
    final tiles = <Widget>[
      for (final t in templates.mine)
        TemplateTile(
          key: ValueKey('template-tile-${t.slug}'),
          template: t,
          selected: picked(t),
          now: now,
          onLoad: () => loadTemplate(context, state, t),
          onRename: () => showRenameTemplateDialog(context, state, t),
          onDelete: () => confirmDeleteTemplate(context, state, t),
        ),
      for (final t in kBuiltInTemplates.take(2))
        TemplateTile(
          key: ValueKey('template-tile-${t.slug}'),
          template: t,
          selected: picked(t),
          onLoad: () => loadTemplate(context, state, t),
        ),
      AllBuiltInsTile(onTap: () => showBuiltInTemplatesDialog(context, state)),
    ];
    return Container(
      key: const ValueKey('template-picker'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      // The sketch's text: no tracking and the browser's normal line height,
      // where the app's text theme would add both.
      child: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            _header(context),
            // The sketch's flex row lets five 176px tiles give a few pixels
            // each to fit the 960 column; past that a tile wraps.
            TemplateTileGrid(tiles: tiles),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      spacing: 10,
      children: [
        Icon(
          Icons.bookmark_border,
          size: 20,
          color: StudioColors.amberOf(context),
        ),
        Text(
          'Start from a template',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: StudioColors.inkOf(context),
          ),
        ),
        Flexible(
          child: Text(
            'Every box filled the way you saved it. Pick one, or choose a mode below to start blank.',
            style: TextStyle(
              fontSize: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ),
      ],
    );
  }
}
