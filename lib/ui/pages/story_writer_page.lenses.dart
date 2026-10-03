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

part of 'story_writer_page.dart';

/// The "Phrases to avoid" card (always shown, so a first phrase can be
/// added) and the writing-lens picker with "Add your own lens".
extension _StoryWriterLenses on _StoryWriterPageState {
  Widget _buildBannedCard(StoryProject project) {
    final auto = project.autoBannedPhrases;
    final own = project.bannedPhrases;
    final all = [...own, ...auto];
    return StoryCard(
      key: const ValueKey('story-banned'),
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Phrases to avoid')),
            StoryButton.ghost(
              'Edit list',
              onPressed: () => _editBannedList(project),
            ),
          ],
        ),
        if (all.isEmpty)
          Text(
            'None yet. The engine adds phrases it notices itself repeating; '
            'add your own with Edit list.',
            style: StudioType.ui(
              context,
              size: 12,
              color: StudioColors.mutedOf(context),
            ),
          )
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in all.take(10)) StoryChip('“$p”'),
              if (all.length > 10) StoryChip('+ ${all.length - 10} more'),
            ],
          ),
          Text(
            [
              if (auto.isNotEmpty)
                '${auto.length} of these ${auto.length == 1 ? 'was' : 'were'} '
                    'noticed by the engine in the last chapter',
              if (own.isNotEmpty)
                '${auto.isNotEmpty ? 'the rest are' : 'these are'} yours and '
                    'stay for the whole story',
            ].join('; '),
            style: StudioType.ui(
              context,
              size: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _editBannedList(StoryProject project) async {
    final controller = TextEditingController(
      text: project.bannedPhrases.join('\n'),
    );
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Phrases to avoid',
      width: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'One per line. The engine adds its own as it notices repeats; '
            'yours stay for the whole story.',
            style: StudioType.ui(
              context,
              size: 12.5,
              color: StudioColors.mutedOf(context),
            ),
          ),
          const SizedBox(height: 10),
          StoryTextArea(controller: controller, minLines: 5),
          if (project.autoBannedPhrases.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Noticed lately: ${project.autoBannedPhrases.join(', ')}',
              style: StudioType.ui(
                context,
                size: 12.5,
                color: StudioColors.mutedOf(context),
              ),
            ),
          ],
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || !mounted) return;
    project.bannedPhrases = controller.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    rebuildState(() {});
  }

  Future<void> _changeLens(StoryProject project) async {
    final scene = project.scenes[widget.actIndex]![widget.sceneIndex];
    final current = StoryLenses.normalizeId(scene.lens);
    final picked = await showStoryDialog<String>(
      context,
      title: 'Writing lens for this scene',
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final lens in StoryLenses.forProject(project))
            InkWell(
              key: ValueKey('story-lens-${lens.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.pop(context, lens.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: lens.id == current
                    ? BoxDecoration(
                        color: StudioColors.raiseOf(context),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Row(
                  children: [
                    StoryLensMark(lens.id),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: lens.name,
                              style: StudioType.ui(
                                context,
                                weight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '  ${lens.context}',
                              style: StudioType.ui(
                                context,
                                size: 12,
                                color: StudioColors.mutedOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost(
          'Add your own lens',
          onPressed: () => Navigator.pop(ctx, '+'),
        ),
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == '+') return _addCustomLens(project, scene);
    scene.lens = picked;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    rebuildState(() {});
  }

  /// A lens of the user's own: a name, when to use it, how to write in it.
  Future<void> _addCustomLens(StoryProject project, StoryScene scene) async {
    final name = TextEditingController();
    final when = TextEditingController();
    final how = TextEditingController();
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Your own lens',
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoryField(controller: name, hint: 'Name'),
          const SizedBox(height: 8),
          StoryField(controller: when, hint: 'When to use it (one line)'),
          const SizedBox(height: 8),
          StoryTextArea(
            controller: how,
            hint:
                'How to write in it: sentence rhythm, what the narration '
                'notices, how people talk…',
            minLines: 4,
          ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          'Save lens',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || !mounted || name.text.trim().isEmpty) return;
    final id = StoryLenses.normalizeId(name.text);
    project.customLenses
      ..removeWhere((l) => l.id == id)
      ..add(
        StoryLens(
          id: id,
          name: name.text.trim(),
          context: when.text.trim(),
          prompt: how.text.trim(),
        ),
      );
    scene.lens = id;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    rebuildState(() {});
  }
}
