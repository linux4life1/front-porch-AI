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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'lore_section.facts.dart';

/// Lore & continuity (sketch T): the facts the story must keep straight,
/// the lore (bible + dropped-in files), and the story so far.
class LoreSection extends StatefulWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;

  const LoreSection({super.key, required this.project, required this.pipeline});

  @override
  State<LoreSection> createState() => _LoreSectionState();
}

class _LoreSectionState extends State<LoreSection> {
  String _tab = 'continuity';

  StoryProject get p => widget.project;

  Future<void> _save() =>
      Provider.of<StoryRepository>(context, listen: false).saveProject(p);

  void rebuildState(VoidCallback fn) => setState(fn);

  int get _fileCount => {
    for (final l in p.lore)
      for (final r in l.relatedTo)
        if (r.startsWith('file:')) r,
  }.length;

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    final subtitle =
        '${p.continuity.length} fact${p.continuity.length == 1 ? '' : 's'} · '
        '${p.lore.length} lore entr${p.lore.length == 1 ? 'y' : 'ies'} · '
        '$_fileCount file${_fileCount == 1 ? '' : 's'}';
    return ListView(
      key: const ValueKey('studio-lore'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(subtitle, style: StudioType.ui(context, size: 12.5, color: muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StorySegmented(
              options: const {
                'continuity': 'Continuity',
                'lore': 'Lore',
                'sofar': 'Story so far',
              },
              selected: _tab,
              onSelect: (v) => setState(() => _tab = v),
            ),
            StoryButton(
              'Add fact',
              key: const ValueKey('lore-add-fact'),
              icon: Icons.add,
              onPressed: () => _editFact(null),
            ),
            StoryButton(
              'Add lore file',
              key: const ValueKey('lore-add-file'),
              onPressed: _addFile,
            ),
            StoryButton(
              'Test search',
              key: const ValueKey('lore-search'),
              onPressed: p.lore.isEmpty ? null : _testSearch,
            ),
          ],
        ),
        const SizedBox(height: 12),
        switch (_tab) {
          'lore' => _loreTab(),
          'sofar' => _soFarTab(),
          _ => _continuityTab(),
        },
      ],
    );
  }

  Widget _loreTab() {
    final muted = StudioColors.mutedOf(context);
    if (p.lore.isEmpty) {
      return const StoryEmptyState(
        title: 'No lore yet',
        detail: 'Add a file, or let the story bible create some.',
      );
    }
    return StoryCard(
      children: [
        for (final l in p.lore)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.topic,
                          style: StudioType.ui(
                            context,
                            size: 12.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                        for (final r in l.relatedTo)
                          if (r.startsWith('file:'))
                            StoryChip(
                              r.substring(5),
                              icon: Icons.description_outlined,
                            ),
                        if (l.validFromAct > 1 || l.validFromScene > 1)
                          Text(
                            'from act ${l.validFromAct}, scene ${l.validFromScene}',
                            style: StudioType.mono(context, size: 11),
                          ),
                      ],
                    ),
                    Text(
                      l.detail,
                      style: StudioType.ui(context, size: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
              StoryMenuButton(
                entries: [
                  StoryMenuEntry(
                    'Remove…',
                    danger: true,
                    onSelect: () async {
                      final ok = await showStoryConfirm(
                        context,
                        title: 'Remove “${l.topic}”?',
                        body: 'The writer stops seeing this entry.',
                        confirmLabel: 'Remove',
                        destructive: true,
                      );
                      if (!ok || !mounted) return;
                      p.lore.remove(l);
                      await _save();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _soFarTab() {
    final muted = StudioColors.mutedOf(context);
    final blocks = <Widget>[];
    for (final seq in p.sequences) {
      final scenes = p.sceneIndexesInSequence(seq.number);
      final act = seq.act - 1;
      final lines = [
        for (final i in scenes)
          if (p.scenes[act]?[i].summary.isNotEmpty ?? false)
            '${p.sceneLabel(act, i)} ${p.scenes[act]![i].title}: '
                '${p.scenes[act]![i].summary}',
      ];
      if (seq.summary.isEmpty && lines.isEmpty) continue;
      blocks.add(
        StoryCard(
          children: [
            Text(
              'Sequence ${seq.number}${seq.title.isEmpty ? '' : ' · ${seq.title}'}',
              style: StudioType.ui(
                context,
                weight: FontWeight.w600,
                color: StudioColors.honeyOf(context),
              ),
            ),
            if (seq.summary.isNotEmpty)
              Text(seq.summary, style: StudioType.prose(context, size: 13.5)),
            for (final l in lines)
              Text(l, style: StudioType.ui(context, size: 12.5, color: muted)),
          ],
        ),
      );
      blocks.add(const SizedBox(height: 10));
    }
    if (blocks.isEmpty) {
      return const StoryEmptyState(
        title: 'Nothing written yet',
        detail: 'Each sequence gets a summary once its scenes are written.',
      );
    }
    return Column(children: blocks);
  }

  Future<void> _addFile() async {
    final result = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
      allowMultiple: true,
    );
    if (!mounted || result == null) return;
    var added = 0;
    for (final f in result.files) {
      final filePath = f.path;
      if (filePath == null || filePath.isEmpty) continue;
      try {
        final text = await File(filePath).readAsString();
        added += await widget.pipeline.addLoreDocument(
          p,
          path.basename(filePath),
          text,
        );
      } catch (e) {
        if (mounted) showAiErrorSnackBar(context, e);
      }
    }
    if (!mounted) return;
    setState(() => _tab = 'lore');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $added lore entr${added == 1 ? 'y' : 'ies'}.'),
      ),
    );
  }

  Future<void> _testSearch() async {
    final controller = TextEditingController();
    List<LoreHit> hits = const [];
    await showStoryDialog<void>(
      context,
      title: 'What would the writer see?',
      width: 520,
      body: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StoryTextArea(
              controller: controller,
              hint: 'Describe a beat, e.g. "Mara haggles at the salt market"',
              minLines: 2,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                StoryButton.primary(
                  'Search',
                  onPressed: () async {
                    final found = await widget.pipeline.searchLore(
                      p,
                      controller.text,
                    );
                    setLocal(() => hits = found);
                  },
                ),
                const SizedBox(width: 10),
                Text(
                  widget.pipeline.loreSearchIsSemantic
                      ? 'by meaning (embeddings)'
                      : 'by word overlap (embedding model not set up)',
                  style: StudioType.ui(
                    ctx,
                    size: 11.5,
                    color: StudioColors.mutedOf(ctx),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final h in hits)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${(h.score * 100).round()}%',
                        style: StudioType.mono(ctx),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${h.entry.topic}: ${h.entry.detail}',
                        style: StudioType.ui(ctx, size: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: (ctx) => [
        StoryButton.ghost('Close', onPressed: () => Navigator.pop(ctx)),
      ],
    );
  }
}
