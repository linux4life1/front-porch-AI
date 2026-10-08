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

/// Table of Contents end drawer for [_StoryReaderPageState]: builds the
/// (act, scene) -> page-index map and renders the tappable entry list.
/// Extracted from the inline build() helpers; direct state access preserves
/// behavior. AppColors + warm-porch accents — this is navigation chrome, not
/// the in-book paper prop, so it follows the app theme like any other drawer.
extension _StoryReaderToc on _StoryReaderPageState {
  /// Build the Table of Contents end drawer.
  Widget _buildTocDrawer(bool isTwoPageSpread) {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null || _pages == null) {
      return const Drawer(child: SizedBox.shrink());
    }

    // Build a map of (actIdx, sceneIdx) -> first page index for that scene
    final Map<String, int> sceneToPage = {};
    for (int i = 0; i < _pages!.length; i++) {
      final p = _pages![i];
      if (p.actIndex != null && p.sceneIndex != null) {
        final key = '${p.actIndex}-${p.sceneIndex}';
        sceneToPage.putIfAbsent(key, () => i);
      }
      if (p.type == _PageType.actTitle) {
        // Find which act this is by matching the title
        for (int a = 0; a < project.acts.length; a++) {
          if (p.title == 'Act ${project.acts[a].number}') {
            sceneToPage.putIfAbsent('act-$a', () => i);
            break;
          }
        }
      }
    }

    return Drawer(
      backgroundColor: StudioColors.bgOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: StudioColors.lineOf(context),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: StudioColors.inkOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Table of Contents',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: StudioColors.mutedOf(context),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // TOC entries
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  // Title page
                  _tocEntry('Title Page', 0, isTwoPageSpread, isTitle: true),

                  for (
                    int actIdx = 0;
                    actIdx < project.acts.length;
                    actIdx++
                  ) ...[
                    const SizedBox(height: 8),
                    // Act header
                    _tocEntry(
                      'Act ${project.acts[actIdx].number}: ${project.acts[actIdx].title}',
                      sceneToPage['act-$actIdx'] ?? 0,
                      isTwoPageSpread,
                      isAct: true,
                    ),
                    // Scenes
                    for (
                      int sceneIdx = 0;
                      sceneIdx < (project.scenes[actIdx]?.length ?? 0);
                      sceneIdx++
                    )
                      _tocEntry(
                        project.scenes[actIdx]![sceneIdx].title,
                        sceneToPage['$actIdx-$sceneIdx'] ?? 0,
                        isTwoPageSpread,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tocEntry(
    String label,
    int pageIndex,
    bool isTwoPageSpread, {
    bool isTitle = false,
    bool isAct = false,
  }) {
    final flipPage = isTwoPageSpread ? pageIndex ~/ 2 : pageIndex;
    final isCurrentPage = _currentPage == flipPage;

    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close drawer
        // Scroll mode has no flip widget: jump to the page's chapter.
        if (_flipKey.currentState == null) {
          final page = _pages![pageIndex.clamp(0, _pages!.length - 1)];
          final act = page.actIndex;
          final scene = page.sceneIndex;
          if (act != null && scene != null) {
            final project = Provider.of<StoryRepository>(
              context,
              listen: false,
            ).getById(widget.projectId);
            if (project != null) {
              final chapters = _chapters(project);
              final i = chapters.indexWhere(
                (c) => c.act == act && c.index == scene,
              );
              if (i >= 0) _jumpToChapter(i);
            }
          }
          return;
        }
        rebuildState(() => _currentPage = flipPage);
        _flipKey.currentState?.goToPage(flipPage);
      },
      child: Container(
        padding: EdgeInsets.only(
          left: isAct || isTitle ? 20 : 40,
          right: 20,
          top: isAct ? 10 : 6,
          bottom: isAct ? 10 : 6,
        ),
        color: isCurrentPage
            ? StudioColors.amberOf(context).withValues(alpha: 0.15)
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: isAct ? 14 : 13,
                  fontWeight: isAct || isTitle
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: isCurrentPage
                      ? StudioColors.amberOf(context)
                      : isAct || isTitle
                      ? StudioColors.inkOf(context)
                      : StudioColors.mutedOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${pageIndex + 1}',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 11,
                color: StudioColors.faintOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
