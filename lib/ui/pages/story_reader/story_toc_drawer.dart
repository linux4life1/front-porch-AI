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
import 'package:front_porch_ai/ui/pages/story_reader/book_page.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Table of Contents end drawer: builds the (act, scene) -> page-index map
/// and renders the tappable entry list. AppColors + warm-porch accents — this
/// is navigation chrome, not the in-book paper prop, so it follows the app
/// theme like any other drawer.
class StoryTocDrawer extends StatelessWidget {
  final StoryProject? project;
  final List<BookPage>? pages;
  final bool isTwoPageSpread;

  /// The flip page currently showing; its entries are highlighted.
  final int currentPage;

  /// An entry was tapped: the book page it starts on and that page's flip
  /// index for the current layout.
  final void Function(int pageIndex, int flipPage) onSelect;

  const StoryTocDrawer({
    super.key,
    required this.project,
    required this.pages,
    required this.isTwoPageSpread,
    required this.currentPage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final project = this.project;
    final pages = this.pages;
    if (project == null || pages == null) {
      return const Drawer(child: SizedBox.shrink());
    }

    // Build a map of (actIdx, sceneIdx) -> first page index for that scene
    final Map<String, int> sceneToPage = {};
    for (int i = 0; i < pages.length; i++) {
      final p = pages[i];
      if (p.actIndex != null && p.sceneIndex != null) {
        final key = '${p.actIndex}-${p.sceneIndex}';
        sceneToPage.putIfAbsent(key, () => i);
      }
      if (p.type == BookPageType.actTitle) {
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
                  _entry(
                    context,
                    'Title Page',
                    0,
                    isTwoPageSpread,
                    isTitle: true,
                  ),

                  for (
                    int actIdx = 0;
                    actIdx < project.acts.length;
                    actIdx++
                  ) ...[
                    const SizedBox(height: 8),
                    // Act header
                    _entry(
                      context,
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
                      _entry(
                        context,
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

  Widget _entry(
    BuildContext context,
    String label,
    int pageIndex,
    bool isTwoPageSpread, {
    bool isTitle = false,
    bool isAct = false,
  }) {
    final flipPage = isTwoPageSpread ? pageIndex ~/ 2 : pageIndex;
    final isCurrentPage = currentPage == flipPage;

    return InkWell(
      onTap: () => onSelect(pageIndex, flipPage),
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
