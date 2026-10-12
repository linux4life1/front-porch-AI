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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

const _ordinals = [
  'ONE',
  'TWO',
  'THREE',
  'FOUR',
  'FIVE',
  'SIX',
  'SEVEN',
  'EIGHT',
  'NINE',
  'TEN',
  'ELEVEN',
  'TWELVE',
  'THIRTEEN',
  'FOURTEEN',
  'FIFTEEN',
  'SIXTEEN',
  'SEVENTEEN',
  'EIGHTEEN',
  'NINETEEN',
  'TWENTY',
];

String _chapterWord(int n) => n <= _ordinals.length ? _ordinals[n - 1] : '$n';

/// Scenes with prose, in story order.
List<SceneRef> storyChapters(StoryProject project) => [
  for (final ref in project.orderedScenes)
    if (project.sceneHasProse(ref.act, ref.index)) ref,
];

/// Scroll mode: one continuous column with a heading per chapter (a scene
/// with prose). A tap in the middle hides the controls; the chapter buttons
/// sit at the bottom.
class StoryScrollBody extends StatelessWidget {
  final StoryProject project;
  final List<SceneRef> chapters;
  final ScrollController controller;

  /// One key per entry of [chapters], on that chapter's column.
  final List<GlobalKey> chapterKeys;
  final int scrollChapter;
  final bool hudHidden;
  final VoidCallback onToggleHud;
  final VoidCallback onScrolled;
  final ValueChanged<int> onJumpToChapter;

  const StoryScrollBody({
    super.key,
    required this.project,
    required this.chapters,
    required this.controller,
    required this.chapterKeys,
    required this.scrollChapter,
    required this.hudHidden,
    required this.onToggleHud,
    required this.onScrolled,
    required this.onJumpToChapter,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (d) {
        final w = MediaQuery.of(context).size.width;
        if (d.globalPosition.dx > w * 0.3 && d.globalPosition.dx < w * 0.7) {
          onToggleHud();
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollEndNotification || n is ScrollUpdateNotification) {
            onScrolled();
          }
          return false;
        },
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
                    itemCount: chapters.length,
                    itemBuilder: (context, i) {
                      final ref = chapters[i];
                      final text = project.sceneText(ref.act, ref.index);
                      return Column(
                        key: chapterKeys[i],
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (i > 0) const SizedBox(height: 48),
                          Text(
                            'CHAPTER ${_chapterWord(i + 1)}',
                            textAlign: TextAlign.center,
                            style: StudioType.prose(
                              context,
                              size: 12,
                              color: StudioColors.honeyOf(context),
                            ).copyWith(letterSpacing: 2.5),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ref.scene.title,
                            textAlign: TextAlign.center,
                            style: StudioType.prose(context, size: 22),
                          ),
                          const SizedBox(height: 18),
                          for (final para in text.split(RegExp(r'\n\s*\n')))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: SelectableText(
                                para.trim(),
                                style: StudioType.prose(
                                  context,
                                  size: 17,
                                  height: 1.75,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            if (!hudHidden)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: StudioColors.sideOf(context),
                  border: Border(
                    top: BorderSide(color: StudioColors.lineOf(context)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StoryButton.ghost(
                      'Ch. $scrollChapter',
                      icon: Icons.chevron_left,
                      onPressed: scrollChapter > 0
                          ? () => onJumpToChapter(scrollChapter - 1)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    StoryButton.ghost(
                      'Ch. ${scrollChapter + 2}',
                      icon: Icons.chevron_right,
                      onPressed: scrollChapter < chapters.length - 1
                          ? () => onJumpToChapter(scrollChapter + 1)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
