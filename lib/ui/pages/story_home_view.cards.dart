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

part of 'story_home_view.dart';

/// A book on the shelf: cover, title, genre line, progress, where you are.
class StoryShelfCard extends StatelessWidget {
  final StoryProject project;

  const StoryShelfCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final st = storyShelfStatus(p);
    return StoryCard(
      key: ValueKey('story-book-${p.dbId}'),
      padding: const EdgeInsets.all(12),
      onTap: () => openStory(context, p),
      alignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Container(
              height: 84,
              padding: const EdgeInsets.all(8),
              alignment: Alignment.bottomLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(
                  begin: Alignment(-0.6, -1),
                  end: Alignment(0.6, 1),
                  colors: [StudioColors.coverStart, StudioColors.coverEnd],
                ),
              ),
              child: Text(
                p.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: StudioType.prose(
                  context,
                  size: 14,
                  height: 1.2,
                  color: StudioColors.honeyOf(context),
                ),
              ),
            ),
            Positioned(top: 8, right: 8, child: _engineChip(p, st)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(
                  context,
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            StoryShelfMenu(project: p),
          ],
        ),
        Text(
          storyGenreLine(p),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: StudioType.ui(
            context,
            size: 12,
            color: StudioColors.mutedOf(context),
          ),
        ),
        StoryProgressBar(st.fraction, done: st.done),
        Row(
          children: [
            Expanded(
              child: Text(
                st.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(
                  context,
                  size: 12,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ),
            Text(
              formatRelativeTime(p.updatedAt),
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Widget _engineChip(
  StoryProject p,
  ({String status, double fraction, bool done, bool setup}) st,
) => st.setup
    ? const StoryChip('Setup', tone: 'honey')
    : p.engineMode == StoryEngineMode.studio
    ? const StoryChip('Studio', tone: 'amber')
    : const StoryChip('Quick');

/// The phone row: avatar, title, status, engine chip, progress.
class StoryShelfRow extends StatelessWidget {
  final StoryProject project;

  const StoryShelfRow({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final st = storyShelfStatus(p);
    return StoryCard(
      key: ValueKey('story-book-${p.dbId}'),
      onTap: () => openStory(context, p),
      alignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StoryAvatar(p.title),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioType.ui(
                      context,
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    st.status,
                    style: StudioType.ui(
                      context,
                      size: 12,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
            _engineChip(p, st),
            StoryShelfMenu(project: p),
          ],
        ),
        StoryProgressBar(st.fraction, done: st.done),
      ],
    );
  }
}

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
