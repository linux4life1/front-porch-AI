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

part of 'story_reader_page.dart';

/// The reader bar (sketch P), shared by Book and Scroll: ☰ (fold the studio
/// sidebar), title, Book | Scroll, where you are, Read aloud, Contents, ⋯.
extension _StoryReaderBar on _StoryReaderPageState {
  PreferredSizeWidget _studioBar(
    StoryProject project,
    String where,
  ) => PreferredSize(
    preferredSize: const Size.fromHeight(48),
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: StudioColors.sideOf(context),
        border: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          if (widget.onToggleSidebar != null)
            StoryIconButton(
              Icons.menu,
              key: const ValueKey('reader-sidebar-toggle'),
              tooltip: 'Show or hide the studio sidebar',
              onPressed: widget.onToggleSidebar,
            )
          else if (!widget.embedded)
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
              style: StudioType.ui(context, size: 15, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          StorySegmented(
            key: const ValueKey('reader-mode'),
            options: const {'book': 'Book', 'scroll': 'Scroll'},
            selected: project.readerMode,
            onSelect: (m) => _setReaderMode(project, m),
          ),
          const Spacer(),
          Text(where, style: StudioType.mono(context)),
          const SizedBox(width: 8),
          _readAloudButton(project),
          StoryButton.ghost(
            'Contents',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          StoryMenuButton(
            entries: [
              StoryMenuEntry(
                _isAudioMuted ? 'Ambient sound on' : 'Ambient sound off',
                onSelect: _toggleAudio,
              ),
              StoryMenuEntry(
                'Export text…',
                divider: true,
                onSelect: _exportStory,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// Read aloud / Stop, with the buffered-pages pill while reading.
  Widget _readAloudButton(StoryProject project) {
    if (_isReadingAlong) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_bufferedPageCount > 0) ...[
            StoryChip('$_bufferedPageCount pg', tone: 'teal'),
            const SizedBox(width: 6),
          ],
          StoryButton.ghost(
            'Stop',
            icon: Icons.stop,
            onPressed: _stopReadAlong,
          ),
        ],
      );
    }
    return StoryButton.ghost(
      'Read aloud',
      key: const ValueKey('reader-read-aloud'),
      icon: Icons.play_arrow,
      onPressed: project.readerMode == 'scroll'
          ? () => _readAloudVisibleChapter(project)
          : _startReadAlong,
    );
  }
}
