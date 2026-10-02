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

/// The banned-phrase list and the lens picker (built-in and the user's own)
/// for [StoryWriterPage].
extension _StoryWriterLenses on _StoryWriterPageState {
  /// "Banned this chapter" — the rolling list plus the user's own.
  Widget _buildBannedCard(StoryProject project) {
    final auto = project.autoBannedPhrases;
    final own = project.bannedPhrases;
    if (auto.isEmpty && own.isEmpty) return const SizedBox.shrink();
    return WarmCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: StoryKeyLabel(
                  'Banned this chapter (repeated too often lately)',
                ),
              ),
              TextButton(
                onPressed: () => _editBannedList(project),
                child: const Text('Edit list'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in [...own, ...auto].take(10)) StoryChip('“$p”'),
              if (own.length + auto.length > 10)
                StoryChip('+ ${own.length + auto.length - 10} more'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editBannedList(StoryProject project) async {
    final controller = TextEditingController(
      text: project.bannedPhrases.join('\n'),
    );
    final ok = await showWarmDialog<bool>(
      context,
      title: 'Phrases to avoid',
      icon: Icons.block_outlined,
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WarmDialogText(
            'One per line. The engine adds its own as it notices repeats; '
            'yours stay for the whole story.',
          ),
          const SizedBox(height: 10),
          StoryTextArea(controller: controller, minLines: 5),
          if (project.autoBannedPhrases.isNotEmpty) ...[
            const SizedBox(height: 10),
            WarmDialogText(
              'Noticed lately: ${project.autoBannedPhrases.join(', ')}',
            ),
          ],
        ],
      ),
      actions: [
        warmDialogCancel(context, value: false),
        warmDialogConfirm(
          context,
          label: 'Save',
          onPressed: () => Navigator.of(context).pop(true),
        ),
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
    final picked = await showWarmDialog<String>(
      context,
      title: 'Writing lens for this scene',
      icon: Icons.camera_outlined,
      width: 460,
      content: SizedBox(
        height: 360,
        child: ListView(
          children: [
            for (final lens in StoryLenses.forProject(project))
              ListTile(
                dense: true,
                leading: StoryLensMark(lens.id),
                title: Text(
                  lens.name,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  lens.context,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11.5,
                  ),
                ),
                selected: lens.id == StoryLenses.normalizeId(scene.lens),
                onTap: () => Navigator.of(context).pop(lens.id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('+'),
          child: const Text('Add your own lens'),
        ),
        warmDialogCancel(context),
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
    final ok = await showWarmDialog<bool>(
      context,
      title: 'Your own lens',
      icon: Icons.camera_outlined,
      width: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: when,
            decoration: const InputDecoration(
              labelText: 'When to use it (one line)',
            ),
          ),
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
      actions: [
        warmDialogCancel(context, value: false),
        warmDialogConfirm(
          context,
          label: 'Save lens',
          onPressed: () => Navigator.of(context).pop(true),
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
