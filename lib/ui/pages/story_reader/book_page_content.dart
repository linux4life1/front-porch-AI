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

/// The printed content of one book page, by [BookPageType]: title, act
/// title, prose, end.
///
/// Every color literal below is `// theme-keep: book prop` — this is the
/// in-book paper/leather/sepia aesthetic (maintainer-approved: the book must
/// look like a book — cream paper, sepia ink, leather binding shadows — in
/// every app theme, light or dark), NOT app chrome. The prose ink color lives
/// in the shared [kStoryProseStyle] so the measured page breaks and the
/// rendered text never drift apart.
class BookPageContent extends StatelessWidget {
  final BookPage page;

  const BookPageContent({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    switch (page.type) {
      case BookPageType.title:
        return _titlePage(page);
      case BookPageType.actTitle:
        return _actTitlePage(page);
      case BookPageType.prose:
        return _prosePage(page);
      case BookPageType.end:
        return _endPage(page);
    }
  }

  Widget _titlePage(BookPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative flourish
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(
              0xFF8B7355,
            ).withValues(alpha: 0.5), // theme-keep: book prop
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C1810), // theme-keep: book prop
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 60,
          height: 1,
          color: const Color(
            0xFF8B7355,
          ).withValues(alpha: 0.4), // theme-keep: book prop
        ),
        const SizedBox(height: 16),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: Color(0xFF5A4A3A), // theme-keep: book prop
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(
              0xFF8B7355,
            ).withValues(alpha: 0.5), // theme-keep: book prop
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 48),
        const Text(
          'A Porch Story',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 12,
            color: Color(0xFF8B7355), // theme-keep: book prop
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  Widget _actTitlePage(BookPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          page.title,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 16,
            letterSpacing: 6,
            color: Color(0xFF8B7355), // theme-keep: book prop
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 40,
          height: 1,
          color: const Color(
            0xFF8B7355,
          ).withValues(alpha: 0.4), // theme-keep: book prop
        ),
        const SizedBox(height: 16),
        Text(
          page.subtitle ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C1810), // theme-keep: book prop
            height: 1.3,
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Color(0xFF5A4A3A), // theme-keep: book prop
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _prosePage(BookPage page) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scene heading (only on first page of scene)
        if (page.title.isNotEmpty) ...[
          Text(
            page.title,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C1810), // theme-keep: book prop
              height: 1.4,
            ),
          ),
          if (page.subtitle != null && page.subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                page.subtitle!,
                style: const TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF8B7355), // theme-keep: book prop
                ),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            width: 40,
            height: 1,
            color: const Color(
              0xFF8B7355,
            ).withValues(alpha: 0.3), // theme-keep: book prop
          ),
          const SizedBox(height: 16),
        ],
        // Prose text — MUST use the shared kStoryProseStyle (declared in
        // book_page.dart) so this render matches the TextPainter
        // measurement that decided this page's break point.
        Text(page.body, style: kStoryProseStyle),
      ],
    );
  }

  Widget _endPage(BookPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(
              0xFF8B7355,
            ).withValues(alpha: 0.5), // theme-keep: book prop
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'The End',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 28,
            fontStyle: FontStyle.italic,
            color: Color(0xFF2C1810), // theme-keep: book prop
          ),
        ),
        const SizedBox(height: 16),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 14,
            color: Color(0xFF8B7355), // theme-keep: book prop
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 48),
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(
              0xFF8B7355,
            ).withValues(alpha: 0.5), // theme-keep: book prop
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
      ],
    );
  }
}
