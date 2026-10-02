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
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The facts the story must keep straight, the lore behind it, and the
/// story so far — with lore file uploads and a search tester.
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

  int get _fileCount => {
    for (final l in p.lore)
      for (final r in l.relatedTo)
        if (r.startsWith('file:')) r,
  }.length;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${p.continuity.length} fact${p.continuity.length == 1 ? '' : 's'} · '
        '${p.lore.length} lore entr${p.lore.length == 1 ? 'y' : 'ies'} · '
        '$_fileCount file${_fileCount == 1 ? '' : 's'}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          subtitle,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12.5,
          ),
        ),
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
            StoryQuietButton(
              'Add lore file',
              icon: Icons.upload_file_outlined,
              onPressed: _addFile,
            ),
            StoryQuietButton(
              'Test search',
              icon: Icons.search,
              onPressed: p.lore.isEmpty ? null : _testSearch,
            ),
          ],
        ),
        const SizedBox(height: 12),
        WarmCard(
          padding: const EdgeInsets.all(12),
          child: switch (_tab) {
            'lore' => _loreTab(),
            'sofar' => _soFarTab(),
            _ => _continuityTab(),
          },
        ),
      ],
    );
  }

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      style: TextStyle(color: AppColors.textTertiary(context), fontSize: 13),
    ),
  );

  Widget _continuityTab() {
    if (p.continuity.isEmpty) {
      return _empty(
        p.engineMode == StoryEngineMode.studio
            ? 'Facts are added automatically after each scene is written.'
            : 'The Quick engine does not keep a continuity ledger. Switch '
                  'the story to Studio to get one.',
      );
    }
    final active = p.continuity.where((f) => !f.isRetired).toList();
    final retired = p.continuity.where((f) => f.isRetired).toList();
    return Column(
      children: [
        for (final f in active) _factRow(f),
        for (final f in retired) _factRow(f),
      ],
    );
  }

  Widget _factRow(ContinuityFact f) {
    final muted = AppColors.textTertiary(context);
    final from = f.sceneId.isEmpty ? '' : p.sceneLabelById(f.sceneId);
    final until = f.isRetired ? p.sceneLabelById(f.retiredSceneId) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          StoryChip(
            f.isRetired ? 'Retired' : f.category,
            tone: f.isRetired ? '' : 'honey',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: f.key,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' · ${f.value}'),
                  if (f.entity.isNotEmpty)
                    TextSpan(
                      text: '  (${f.entity})',
                      style: TextStyle(color: muted),
                    ),
                ],
              ),
              style: TextStyle(
                color: f.isRetired ? muted : AppColors.textSecondary(context),
                fontSize: 12.5,
                decoration: f.isRetired ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            f.isRetired
                ? '$from → $until'
                : (from.isEmpty ? 'always' : 'from $from'),
            style: TextStyle(
              color: muted,
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 14, color: muted),
            tooltip: 'Forget this fact',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () async {
              p.continuity.remove(f);
              await _save();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _loreTab() {
    if (p.lore.isEmpty) {
      return _empty(
        'No lore yet. Add a file or let the story bible create some.',
      );
    }
    final muted = AppColors.textTertiary(context);
    return Column(
      children: [
        for (final l in p.lore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l.topic,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          for (final r in l.relatedTo)
                            if (r.startsWith('file:'))
                              StoryChip(
                                r.substring(5),
                                icon: Icons.description_outlined,
                              ),
                          if (l.validFromAct > 1 || l.validFromScene > 1)
                            Text(
                              '  from act ${l.validFromAct}, scene ${l.validFromScene}',
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                        ],
                      ),
                      Text(
                        l.detail,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 14, color: muted),
                  tooltip: 'Remove',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () async {
                    p.lore.remove(l);
                    await _save();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _soFarTab() {
    final rows = <Widget>[];
    for (final seq in p.sequences) {
      final indexes = p.sceneIndexesInSequence(seq.number);
      if (indexes.isEmpty) continue;
      final act = p.actIndexForSequence(seq.number);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'Sequence ${seq.number} · ${seq.title}',
            style: TextStyle(
              color: AppColors.porchHoneyOf(context),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
      if (seq.summary.isNotEmpty) {
        rows.add(
          Text(
            seq.summary,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12.5,
            ),
          ),
        );
      }
      for (final i in indexes) {
        final s = p.scenes[act]![i];
        if (s.summary.isEmpty) continue;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${p.sceneLabel(act, i)} ${s.title}: ${s.summary}',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          ),
        );
      }
    }
    return rows.isEmpty
        ? _empty('Nothing written yet.')
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Future<void> _addFile() async {
    final result = await PickerPrefs.pickFiles(
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
        backgroundColor: AppColors.surfaceContainerOf(context),
      ),
    );
  }

  Future<void> _testSearch() async {
    final controller = TextEditingController();
    List<LoreHit> hits = const [];
    await showWarmDialog<void>(
      context,
      title: 'What would the writer see?',
      icon: Icons.search,
      width: 520,
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
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
                StoryPrimaryButton(
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
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final h in hits)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${(h.score * 100).round()}%  ${h.entry.topic}: '
                  '${h.entry.detail}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [warmDialogCancel(context, label: 'Close')],
    );
  }
}
