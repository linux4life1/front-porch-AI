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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

/// Setup still open → the wizard where it stopped; otherwise the studio.
void openStory(BuildContext context, StoryProject p) {
  final page = storyShelfStatus(p).setup
      ? StorySetupPage(projectId: p.dbId!)
      : StoryDashboardPage(projectId: p.dbId!);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// Open · Read · Rename · Delete story…
class StoryShelfMenu extends StatelessWidget {
  final StoryProject project;

  const StoryShelfMenu({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    return StoryMenuButton(
      entries: [
        StoryMenuEntry('Open', onSelect: () => openStory(context, p)),
        StoryMenuEntry(
          'Read',
          enabled: p.wordCount > 0,
          onSelect: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StoryDashboardPage(
                projectId: p.dbId!,
                openSection: StudioSection.read,
              ),
            ),
          ),
        ),
        StoryMenuEntry('Rename', onSelect: () => renameStory(context, p)),
        StoryMenuEntry(
          'Delete story…',
          danger: true,
          divider: true,
          onSelect: () => _delete(context, p),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, StoryProject p) async {
    final words = p.wordCount;
    final ok = await showStoryConfirm(
      context,
      title: 'Delete ${p.title}?',
      body: words > 0
          ? '${thousands(words)} words, its bible and its run log will be '
                'removed. This cannot be undone.'
          : 'Its setup and bible will be removed. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).deleteProject(p.dbId!);
  }
}

/// Rename in place; the same dialog the studio header uses.
Future<void> renameStory(BuildContext context, StoryProject p) async {
  final ctl = TextEditingController(text: p.title);
  final ok = await showStoryDialog<bool>(
    context,
    title: 'Rename',
    body: StoryField(controller: ctl, hint: 'Title'),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      StoryButton.primary('Rename', onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  if (ok != true || !context.mounted || ctl.text.trim().isEmpty) return;
  p.title = ctl.text.trim();
  await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
}
