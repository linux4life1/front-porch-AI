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
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Every model call made for this story, newest first: what stage, which
/// model, how long, and whether the check passed. Tap one to read the
/// prompt and the reply.
class RunLogSection extends StatelessWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;

  const RunLogSection({
    super.key,
    required this.project,
    required this.pipeline,
  });

  static String verdictTone(String verdict) => switch (verdict) {
    'PASS' => 'teal',
    'FAIL' || 'ERROR' => 'bad',
    'INVALID' => 'honey',
    _ => '',
  };

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final id = project.dbId;
    if (id == null) return const SizedBox.shrink();
    return FutureBuilder<List<StoryRunEntry>>(
      future: pipeline.store.entries(id),
      builder: (context, snapshot) {
        final entries = (snapshot.data ?? const <StoryRunEntry>[]).reversed
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entries.isEmpty
                        ? 'No model calls yet. Every call this story makes '
                              'will be listed here.'
                        : '${entries.length} call${entries.length == 1 ? '' : 's'}'
                              ' · newest first · tap one to read it',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await pipeline.store.clearLog(id);
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in entries) _row(context, e),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, StoryRunEntry e) {
    final seconds = (e.millis / 1000).toStringAsFixed(1);
    return WarmCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () => _open(context, e),
      child: Row(
        children: [
          Text(
            _clock(e.at),
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.stage.isEmpty ? '(call)' : e.stage,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StoryChip(e.role),
              if (e.attempt > 1) StoryChip('try ${e.attempt}', tone: 'honey'),
              if (e.verdict.isNotEmpty)
                StoryChip(e.verdict, tone: verdictTone(e.verdict)),
              Text(
                '${seconds}s · ${e.tokens} tok',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, StoryRunEntry e) {
    showWarmDialog<void>(
      context,
      title: e.stage.isEmpty ? 'Model call' : e.stage,
      width: 720,
      content: SizedBox(
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: [
                StoryChip(e.backend),
                StoryChip(e.role),
                StoryChip('try ${e.attempt}'),
                if (e.verdict.isNotEmpty)
                  StoryChip(e.verdict, tone: verdictTone(e.verdict)),
                StoryChip('${(e.millis / 1000).toStringAsFixed(1)}s'),
                StoryChip('${e.tokens} tokens'),
              ],
            ),
            if (e.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  e.note,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: AppColors.textPrimary(context),
                      indicatorColor: AppColors.porchAmberOf(context),
                      tabs: const [
                        Tab(text: 'Prompt'),
                        Tab(text: 'Reply'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _text(context, e.prompt),
                          _text(context, e.response),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(
              ClipboardData(
                text: 'PROMPT\n${e.prompt}\n\nREPLY\n${e.response}',
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: const Text('Copy both'),
        ),
        warmDialogCancel(context, label: 'Close'),
      ],
    );
  }

  Widget _text(BuildContext context, String text) => SingleChildScrollView(
    padding: const EdgeInsets.only(top: 8),
    child: SelectableText(
      text.isEmpty ? '(empty)' : text,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        height: 1.5,
        fontFamily: 'monospace',
      ),
    ),
  );
}
