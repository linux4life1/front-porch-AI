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

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/template_name_dialog.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/template_tile.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// The templates' dialogs, all through the warm dialog, which takes the
// creator's Dialog shape inside the creator (docs/design/creator-ui-spec.md).

/// Fills the form from [t]. A persona the template names that this app
/// does not have is dropped.
void loadTemplate(BuildContext context, CreatorState state, CreatorTemplate t) {
  final personas = Provider.of<UserPersonaService?>(context, listen: false);
  state.templates.load(
    state,
    t,
    personaIds: [for (final p in personas?.personas ?? const []) p.id],
  );
}

/// `Save as a template`, prefilled with the name the form was started from.
Future<void> showSaveTemplateDialog(BuildContext context, CreatorState state) {
  final templates = state.templates;
  return showWarmDialogOf<bool>(
    context,
    builder: (_) => TemplateNameDialog(
      title: 'Save as a template',
      body:
          "Keeps every box on this form the way it is now: the mode, your vision and the interview boxes, output settings, lore, 18+ and the rest. Not the character's name.",
      confirmLabel: 'Save template',
      initialName: templates.startedFrom?.name ?? '',
      check: templates.checkName,
      submit: (name) => templates.saveAs(state, name),
      failure: "The template couldn't be saved. Try again.",
    ),
  );
}

/// Renames one of yours through the same name field.
Future<void> showRenameTemplateDialog(
  BuildContext context,
  CreatorState state,
  CreatorTemplate t,
) {
  final templates = state.templates;
  return showWarmDialogOf<bool>(
    context,
    builder: (_) => TemplateNameDialog(
      title: 'Rename template',
      confirmLabel: 'Rename',
      initialName: t.name,
      check: (name) => templates.checkName(name, renaming: t),
      submit: (name) => templates.rename(t, name),
      failure: "The template couldn't be renamed. Try again.",
    ),
  );
}

/// `Delete this template?`, the warm dialog's destructive form. A delete
/// that fails says so in a dialog of its own.
Future<void> confirmDeleteTemplate(
  BuildContext context,
  CreatorState state,
  CreatorTemplate t,
) async {
  final ok = await showWarmDialogOf<bool>(
    context,
    builder: (ctx) => WarmDialog(
      title: 'Delete this template?',
      icon: Icons.delete_outline,
      destructive: true,
      // The body is the template's name, as on the phone.
      content: WarmDialogText(t.name),
      actions: [
        warmDialogCancel(ctx, value: false),
        warmDialogConfirm(
          ctx,
          key: const ValueKey('template-delete-confirm'),
          label: 'Delete',
          destructive: true,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await state.templates.delete(t);
  } catch (e, st) {
    debugPrint('CharacterCreator: template delete failed: $e\n$st');
    if (!context.mounted) return;
    await showWarmDialogOf<void>(
      context,
      builder: (ctx) => WarmDialog(
        title: "That template wasn't deleted",
        icon: Icons.error_outline,
        content: WarmDialogText(
          e is TemplateRefused ? e.message : 'Something went wrong. Try again.',
        ),
        actions: [
          warmDialogConfirm(
            ctx,
            label: 'OK',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }
}

/// `Built-in templates`: the fifteen archetypes; a tap loads one.
Future<void> showBuiltInTemplatesDialog(
  BuildContext context,
  CreatorState state,
) {
  final start = state.templates.startedFrom;
  return showWarmDialogOf<void>(
    context,
    builder: (ctx) => WarmDialog(
      title: 'Built-in templates',
      icon: Icons.bookmark_border,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: SingleChildScrollView(
          // Two to a row in the 472 body, as tall as each other, in the
          // picker card's line height.
          child: DefaultTextStyle.merge(
            style: const TextStyle(height: 1.2),
            child: TemplateTileGrid(
              maxWidth: 230,
              minWidth: 200,
              tiles: [
                for (final t in kBuiltInTemplates)
                  TemplateTile(
                    key: ValueKey('template-tile-${t.slug}'),
                    template: t,
                    selected:
                        start != null && start.builtIn && start.slug == t.slug,
                    onLoad: () {
                      loadTemplate(context, state, t);
                      Navigator.of(ctx).pop();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [warmDialogCancel(ctx)],
    ),
  );
}
