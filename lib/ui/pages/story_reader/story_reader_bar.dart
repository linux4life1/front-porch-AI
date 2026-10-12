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

/// The reader bar (sketch P), shared by Book and Scroll: ☰ (fold the studio
/// sidebar), title, Book | Scroll, where you are, Read aloud, Contents, ⋯.
class StoryReaderBar extends StatelessWidget implements PreferredSizeWidget {
  final StoryProject project;

  /// Where the reader is ("Page 3 of 12", "Ch. 2 · 40%"); hidden when compact.
  final String where;
  final bool embedded;
  final VoidCallback? onToggleSidebar;
  final ValueChanged<String> onReaderModeSelected;
  final VoidCallback onOpenContents;
  final bool isAudioMuted;
  final VoidCallback onToggleAudio;
  final VoidCallback onExport;
  final bool isReadingAlong;
  final int bufferedPageCount;
  final VoidCallback onReadAloud;
  final VoidCallback onStopReadAlong;

  const StoryReaderBar({
    super.key,
    required this.project,
    required this.where,
    required this.embedded,
    required this.onToggleSidebar,
    required this.onReaderModeSelected,
    required this.onOpenContents,
    required this.isAudioMuted,
    required this.onToggleAudio,
    required this.onExport,
    required this.isReadingAlong,
    required this.bufferedPageCount,
    required this.onReadAloud,
    required this.onStopReadAlong,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Under 760px (the phone frame) the labels give way to icons.
        final compact = constraints.maxWidth < 760;
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: StudioColors.sideOf(context),
            border: Border(
              bottom: BorderSide(color: StudioColors.lineOf(context)),
            ),
          ),
          child: Row(
            children: [
              if (onToggleSidebar != null)
                StoryIconButton(
                  Icons.menu,
                  key: const ValueKey('reader-sidebar-toggle'),
                  tooltip: 'Show or hide the studio sidebar',
                  onPressed: onToggleSidebar,
                )
              else if (!embedded)
                StoryIconButton(
                  Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  project.title,
                  overflow: TextOverflow.ellipsis,
                  style: StudioType.ui(
                    context,
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              StorySegmented(
                key: const ValueKey('reader-mode'),
                options: const {'book': 'Book', 'scroll': 'Scroll'},
                selected: project.readerMode,
                onSelect: onReaderModeSelected,
              ),
              const Spacer(),
              if (!compact) ...[
                Text(where, style: StudioType.mono(context)),
                const SizedBox(width: 8),
              ],
              ReadAloudButton(
                isReadingAlong: isReadingAlong,
                bufferedPageCount: bufferedPageCount,
                onReadAloud: onReadAloud,
                onStop: onStopReadAlong,
                compact: compact,
              ),
              if (compact)
                StoryIconButton(
                  Icons.list,
                  tooltip: 'Contents',
                  onPressed: onOpenContents,
                )
              else
                StoryButton.ghost('Contents', onPressed: onOpenContents),
              StoryMenuButton(
                entries: [
                  StoryMenuEntry(
                    isAudioMuted ? 'Ambient sound on' : 'Ambient sound off',
                    onSelect: onToggleAudio,
                  ),
                  StoryMenuEntry(
                    'Export text…',
                    divider: true,
                    onSelect: onExport,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Read aloud / Stop, with the buffered-pages pill while reading.
class ReadAloudButton extends StatelessWidget {
  final bool isReadingAlong;
  final int bufferedPageCount;
  final VoidCallback onReadAloud;
  final VoidCallback onStop;
  final bool compact;

  const ReadAloudButton({
    super.key,
    required this.isReadingAlong,
    required this.bufferedPageCount,
    required this.onReadAloud,
    required this.onStop,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isReadingAlong) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bufferedPageCount > 0) ...[
            StoryChip('$bufferedPageCount pg', tone: 'teal'),
            const SizedBox(width: 6),
          ],
          StoryButton.ghost('Stop', icon: Icons.stop, onPressed: onStop),
        ],
      );
    }
    if (compact) {
      return StoryIconButton(
        Icons.play_arrow,
        key: const ValueKey('reader-read-aloud'),
        tooltip: 'Read aloud',
        onPressed: onReadAloud,
      );
    }
    return StoryButton.ghost(
      'Read aloud',
      key: const ValueKey('reader-read-aloud'),
      icon: Icons.play_arrow,
      onPressed: onReadAloud,
    );
  }
}
