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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Run log (sketch U): every model call, newest first, live while a run is
/// on. A row opens the prompt and the reply. Clear asks first.
class RunLogSection extends StatefulWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;

  const RunLogSection({
    super.key,
    required this.project,
    required this.pipeline,
  });

  @override
  State<RunLogSection> createState() => _RunLogSectionState();
}

class _RunLogSectionState extends State<RunLogSection> {
  String _filter = 'all';
  List<StoryRunEntry> _entries = const [];
  int _seen = -1;

  static String verdictTone(String verdict) => switch (verdict) {
    'PASS' || 'OK' => 'teal',
    'FAIL' || 'ERROR' => 'bad',
    'INVALID' || 'FIXED' => 'honey',
    _ => '',
  };

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    widget.pipeline.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.pipeline.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final id = widget.project.dbId;
    if (id == null) return;
    final list = await widget.pipeline.store.entries(id);
    if (!mounted || list.length == _seen) return;
    setState(() {
      _entries = list.reversed.toList();
      _seen = list.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    final shown = _filter == 'failures'
        ? _entries
              .where(
                (e) =>
                    verdictTone(e.verdict) == 'bad' || e.verdict == 'INVALID',
              )
              .toList()
        : _entries;
    final running = widget.pipeline.isRunning;
    return ListView(
      key: const ValueKey('studio-log'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _entries.isEmpty
                  ? 'No model calls yet. Every call this story makes is '
                        'listed here.'
                  : '${_entries.length} call${_entries.length == 1 ? '' : 's'} · newest first',
              style: StudioType.ui(context, size: 12.5, color: muted),
            ),
            if (running) const StoryChip('● live', tone: 'amber'),
            StorySegmented(
              options: const {'all': 'All', 'failures': 'Failures'},
              selected: _filter,
              onSelect: (v) => setState(() => _filter = v),
            ),
            StoryButton.ghost(
              'Clear…',
              onPressed: _entries.isEmpty || running ? null : _clear,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_entries.isNotEmpty) ...[_timeCard(), const SizedBox(height: 10)],
        if (shown.isNotEmpty)
          StoryCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            children: [for (final e in shown) _row(e)],
          ),
      ],
    );
  }

  /// Where the model time went, per job, and a plain note when checking
  /// is what makes the story slow.
  Widget _timeCard() {
    final slow = slowChecksNote(_entries);
    return StoryCard(
      key: const ValueKey('studio-log-time'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      children: [
        const StoryKeyLabel('Time by job'),
        for (final job in storyJobTimes(_entries))
          Text(job.line, style: StudioType.mono(context, size: 11.5)),
        if (slow != null)
          Text(
            slow,
            key: const ValueKey('studio-log-slow'),
            style: StudioType.ui(
              context,
              size: 12.5,
              color: StudioColors.honeyOf(context),
            ),
          ),
      ],
    );
  }

  Widget _row(StoryRunEntry e) {
    final muted = StudioColors.mutedOf(context);
    final seconds = (e.millis / 1000).toStringAsFixed(1);
    final tone = verdictTone(e.verdict);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _open(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(_clock(e.at), style: StudioType.mono(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                e.attempt > 1 ? '${e.stage} · try ${e.attempt}' : e.stage,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(context, size: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            StoryChip(
              e.role,
              tone: e.role == 'prose'
                  ? 'terra'
                  : e.role == 'planning'
                  ? 'honey'
                  : '',
            ),
            if (e.verdict.isNotEmpty) ...[
              const SizedBox(width: 6),
              StoryChip(e.verdict, tone: tone),
            ],
            const SizedBox(width: 10),
            Text(
              '${seconds}s · ${e.tokens} tok',
              style: StudioType.mono(context, size: 11.5, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await showStoryConfirm(
      context,
      title: 'Clear the run log?',
      body:
          '${_entries.length} call${_entries.length == 1 ? '' : 's'} with '
          'their prompts and replies are removed. The story is not touched.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await widget.pipeline.store.clearLog(widget.project.dbId!);
    _seen = -1;
    await _reload();
  }

  void _open(StoryRunEntry e) {
    showStoryDialog<void>(
      context,
      title: e.stage,
      width: 720,
      body: DefaultTabController(
        length: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StoryChip(e.backend),
                StoryChip(e.role),
                if (e.attempt > 1) StoryChip('try ${e.attempt}'),
                if (e.verdict.isNotEmpty)
                  StoryChip(e.verdict, tone: verdictTone(e.verdict)),
                StoryChip('${(e.millis / 1000).toStringAsFixed(1)}s'),
                StoryChip('${e.tokens} tok'),
              ],
            ),
            if (e.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                e.note,
                style: StudioType.ui(
                  context,
                  size: 12.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TabBar(
              labelColor: StudioColors.inkOf(context),
              unselectedLabelColor: StudioColors.mutedOf(context),
              indicatorColor: StudioColors.amberOf(context),
              dividerColor: StudioColors.lineOf(context),
              labelStyle: StudioType.ui(context, weight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Prompt'),
                Tab(text: 'Reply'),
              ],
            ),
            SizedBox(
              height: 380,
              child: TabBarView(
                children: [
                  for (final text in [e.prompt, e.response])
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: SelectableText(
                        text.isEmpty ? '(empty)' : text,
                        style: StudioType.mono(
                          context,
                          size: 11.5,
                          color: StudioColors.inkOf(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        StoryButton.ghost(
          'Copy both',
          onPressed: () => Clipboard.setData(
            ClipboardData(
              text: '### Prompt\n${e.prompt}\n\n### Reply\n${e.response}',
            ),
          ),
        ),
        StoryButton.primary('Close', onPressed: () => Navigator.pop(ctx)),
      ],
    );
  }
}
