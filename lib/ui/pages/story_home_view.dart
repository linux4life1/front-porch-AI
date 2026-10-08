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
import 'package:front_porch_ai/ui/story_setup/story_setup.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'story_home_view.cards.dart';

/// The stories shelf (sketch H): every story as a book, "New story" and
/// "From a chat" as the only ways in. The web twin is StoriesPage.tsx.
class StoryHomeView extends StatelessWidget {
  const StoryHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StoryRepository>();
    final narrow = MediaQuery.of(context).size.width < 760;
    final projects = [...repo.projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return StudioTheme(
      child: Container(
        color: StudioColors.bgOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: StudioColors.sideOf(context),
                border: Border(
                  bottom: BorderSide(color: StudioColors.lineOf(context)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Porch Stories',
                    style: StudioType.ui(
                      context,
                      size: 15,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    projects.isEmpty
                        ? 'no stories yet'
                        : '${projects.length} ${projects.length == 1 ? 'story' : 'stories'}',
                    style: StudioType.ui(
                      context,
                      size: 12.5,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
                  const Spacer(),
                  if (!narrow) ...[
                    StoryButton(
                      'From a chat',
                      key: const ValueKey('story-from-chat'),
                      onPressed: () => _fromChat(context),
                    ),
                    const SizedBox(width: 10),
                  ],
                  StoryButton.primary(
                    narrow ? 'New' : 'New story',
                    key: const ValueKey('story-new'),
                    icon: Icons.add,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StorySetupPage()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: repo.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : projects.isEmpty
                  ? _empty(context)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          narrow
                              ? Column(
                                  children: [
                                    for (final p in projects) ...[
                                      StoryShelfRow(project: p),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                )
                              : _grid(context, projects),
                          if (narrow) ...[
                            const SizedBox(height: 4),
                            StoryButton.ghost(
                              'From a chat…',
                              onPressed: () => _fromChat(context),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<StoryProject> projects) =>
      LayoutBuilder(
        builder: (context, c) {
          final cols = (c.maxWidth / 222).floor().clamp(1, 6);
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in projects)
                SizedBox(
                  width: (c.maxWidth - 12 * (cols - 1)) / cols,
                  child: StoryShelfCard(project: p),
                ),
            ],
          );
        },
      );

  Widget _empty(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: StoryEmptyState(
        title: 'No stories yet',
        detail:
            'Start with an idea, or turn a chat you\'ve had into a book. '
            'The bible, the structure and the prose follow.',
        action: 'New story',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StorySetupPage())),
      ),
    ),
  );

  Future<void> _fromChat(BuildContext context) async {
    final source = await showChatSourcePicker(context);
    if (source == null || !context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StorySetupPage(fromChat: source)));
  }
}
