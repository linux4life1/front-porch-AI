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
import 'package:front_porch_ai/ui/pages/story_reader/book_page_content.dart';

// The book is a physical prop: paper, ink and the gutter shadow keep their
// colours in every app theme (theme-keep: book prop).
const _paperEdge = Color(0xFFF0E5CC); // theme-keep: book prop
const _paperMid = Color(0xFFFAF3E8); // theme-keep: book prop
const _paperInner = Color(0xFFF5ECD7); // theme-keep: book prop
const _gutterShadow = Color(0x26000000); // theme-keep: book prop
const _pageEdgeShade = Color(0x14795548); // theme-keep: book prop

/// The back cover shown after the last flip page.
class BookEndCover extends StatelessWidget {
  const BookEndCover({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8DCC8), // theme-keep: book prop
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Text(
          '⸻ ✦ ⸻\nClosed',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 24,
            color: Color(0xFF8B7355), // theme-keep: book prop
          ),
        ),
      ),
    );
  }
}

/// Two pages side by side; a missing page renders as blank paper.
class BookSpreadView extends StatelessWidget {
  final BookPage? leftPage;
  final BookPage? rightPage;

  const BookSpreadView({super.key, this.leftPage, this.rightPage});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: BookPageContainer(page: leftPage, isLeftSpread: true)),
        Expanded(
          child: BookPageContainer(page: rightPage, isRightSpread: true),
        ),
      ],
    );
  }
}

/// One sheet of paper (with binding-shadow and page-edge effects) holding a
/// page's content, or blank paper when [page] is null.
class BookPageContainer extends StatelessWidget {
  final BookPage? page;
  final bool isLeftSpread;
  final bool isRightSpread;

  const BookPageContainer({
    super.key,
    required this.page,
    this.isLeftSpread = false,
    this.isRightSpread = false,
  });

  @override
  Widget build(BuildContext context) {
    final page = this.page;
    if (page == null) {
      // Empty blank page at end of a right-hand spread
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5ECD7), // theme-keep: book prop
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isRightSpread ? 0 : 4),
            right: Radius.circular(isLeftSpread ? 0 : 4),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        // Paper texture effect — theme-keep: book prop
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isLeftSpread
              ? const [_paperEdge, _paperMid, _paperInner]
              : isRightSpread
              ? const [_paperInner, _paperMid, _paperEdge]
              : const [_paperEdge, _paperMid, _paperEdge],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isRightSpread ? 0 : 4),
          right: Radius.circular(isLeftSpread ? 0 : 4),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isRightSpread ? 0 : 4),
          right: Radius.circular(isLeftSpread ? 0 : 4),
        ),
        child: Stack(
          children: [
            // Center binding shadow
            if (isLeftSpread)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [_gutterShadow, Colors.transparent],
                    ),
                  ),
                ),
              ),
            if (isRightSpread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [_gutterShadow, Colors.transparent],
                    ),
                  ),
                ),
              ),

            // Subtle page edge effect (left side "binding") for single page
            if (!isLeftSpread && !isRightSpread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [_pageEdgeShade, Colors.transparent],
                    ),
                  ),
                ),
              ),

            // Content
            Container(
              alignment: page.type == BookPageType.prose
                  ? Alignment.topLeft
                  : Alignment.center,
              padding: EdgeInsets.fromLTRB(
                isRightSpread ? 40 : 32, // More padding near binding
                48,
                isLeftSpread ? 40 : 32,
                48,
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: BookPageContent(page: page),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
