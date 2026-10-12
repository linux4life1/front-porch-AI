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
import 'package:front_porch_ai/ui/pages/story_reader/book_page.dart';
import 'package:front_porch_ai/ui/pages/story_reader/book_page_container.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/custom_page_flip.dart';

/// The leather cover's drop shadow: a physical prop, black in every theme.
const _coverShadow = Color(0x99000000); // theme-keep: book prop

/// Book mode: the leather-backed 3D page flip with a progress bar and the
/// page indicator / previous-next controls.
class BookReaderView extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final GlobalKey<CustomPageFlipState> flipKey;
  final PreferredSizeWidget? appBar;
  final Widget endDrawer;
  final List<BookPage> pages;
  final bool isTwoPageSpread;
  final int flipCount;
  final int currentPage;

  /// The visible page number(s), e.g. "3" or "3-4".
  final String pageLabel;
  final ValueChanged<int> onPageFlipped;
  final VoidCallback onFlipStart;

  const BookReaderView({
    super.key,
    required this.scaffoldKey,
    required this.flipKey,
    required this.appBar,
    required this.endDrawer,
    required this.pages,
    required this.isTwoPageSpread,
    required this.flipCount,
    required this.currentPage,
    required this.pageLabel,
    required this.onPageFlipped,
    required this.onFlipStart,
  });

  @override
  Widget build(BuildContext context) {
    // Rebuild the list of flip pages so it's fresh for current screen width
    final List<Widget> flipPages = [];
    for (int i = 0; i < flipCount; i++) {
      if (isTwoPageSpread) {
        final leftIndex = i * 2;
        final rightIndex = leftIndex + 1;
        flipPages.add(
          BookSpreadView(
            leftPage: leftIndex < pages.length ? pages[leftIndex] : null,
            rightPage: rightIndex < pages.length ? pages[rightIndex] : null,
          ),
        );
      } else {
        flipPages.add(BookPageContainer(page: pages[i]));
      }
    }

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: StudioColors.bgOf(context),
      endDrawer: endDrawer,
      appBar: appBar,
      body: Stack(
        children: [
          // Background Book Cover Context
          Positioned.fill(
            child: Container(
              color: StudioColors.sideOf(context),
              child: Center(
                // Leather backing
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: isTwoPageSpread ? 1200 : 600,
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    // Dark leather binding color — theme-keep: book prop
                    // (the reader is a book prop; its cover stays leather
                    // brown in every app theme, light or dark).
                    color: const Color(0xFF4A2F1D), // theme-keep: book prop
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        // theme-keep: book prop (a physical drop shadow
                        // stays black regardless of app theme).
                        color: _coverShadow,
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3D Page Flip Widget
          SafeArea(
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isTwoPageSpread ? 1160 : 580,
                ),
                margin: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 24,
                ),
                child: CustomPageFlip(
                  key: flipKey,
                  initialPage: currentPage,
                  pages: flipPages,
                  backCover: const BookEndCover(),
                  onPageFlipped: onPageFlipped,
                  onFlipStart: onFlipStart,
                ),
              ),
            ),
          ),

          // Reading progress bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isTwoPageSpread ? 1160 : 580,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: flipCount > 1 ? currentPage / (flipCount - 1) : 1.0,
                    backgroundColor: StudioColors.raiseOf(
                      context,
                    ).withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      StudioColors.amberOf(context).withValues(alpha: 0.5),
                    ),
                    minHeight: 3,
                  ),
                ),
              ),
            ),
          ),

          // Bottom page indicator with navigation buttons
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: StudioColors.sideOf(context).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => flipKey.currentState?.previousPage(),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.chevron_left,
                          color: StudioColors.inkOf(context),
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Page $pageLabel / ${pages.length}',
                      style: TextStyle(
                        color: StudioColors.inkOf(context),
                        fontFamily: 'Georgia',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () => flipKey.currentState?.nextPage(),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.chevron_right,
                          color: StudioColors.inkOf(context),
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
