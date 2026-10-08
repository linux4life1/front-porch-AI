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

// The book is a physical prop: paper, ink and the gutter shadow keep their
// colours in every app theme (theme-keep: book prop).
const _paperEdge = Color(0xFFF0E5CC); // theme-keep: book prop
const _paperMid = Color(0xFFFAF3E8); // theme-keep: book prop
const _paperInner = Color(0xFFF5ECD7); // theme-keep: book prop
const _gutterShadow = Color(0x26000000); // theme-keep: book prop
const _pageEdgeShade = Color(0x14795548); // theme-keep: book prop

/// Pure page-content rendering for [_StoryReaderPageState]: the end cover,
/// the two-page spread / single-page paper container (with binding-shadow
/// and page-edge effects), and the per-[_PageType] content builders (title,
/// act title, prose, end). Extracted from the inline build() helpers; no
/// state mutation, no side effects.
///
/// Every color literal below is `// theme-keep: book prop` — this is the
/// in-book paper/leather/sepia aesthetic (maintainer-approved: the book must
/// look like a book — cream paper, sepia ink, leather binding shadows — in
/// every app theme, light or dark), NOT app chrome. The one exception that
/// crosses files: the prose ink color lives in the shared `_kProseStyle`
/// constant in story_reader_page.pagination.dart (see hazard note there) so
/// the measured page breaks and the rendered text never drift apart.
extension _StoryReaderPageBuilders on _StoryReaderPageState {
  Widget _buildEndCover(bool isTwoPage) {
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

  Widget _buildSpreadView({_BookPage? leftPage, _BookPage? rightPage}) {
    return Row(
      children: [
        Expanded(
          child: _buildSinglePageContainer(leftPage, isLeftSpread: true),
        ),
        Expanded(
          child: _buildSinglePageContainer(rightPage, isRightSpread: true),
        ),
      ],
    );
  }

  Widget _buildSinglePageContainer(
    _BookPage? page, {
    bool isLeftSpread = false,
    bool isRightSpread = false,
  }) {
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
              alignment: page.type == _PageType.prose
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
                child: _buildPageContent(page),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent(_BookPage page) {
    switch (page.type) {
      case _PageType.title:
        return _buildTitlePage(page);
      case _PageType.actTitle:
        return _buildActTitlePage(page);
      case _PageType.prose:
        return _buildProsePage(page);
      case _PageType.end:
        return _buildEndPage(page);
    }
  }

  Widget _buildTitlePage(_BookPage page) {
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

  Widget _buildActTitlePage(_BookPage page) {
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

  Widget _buildProsePage(_BookPage page) {
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
        // Prose text — MUST use the shared _kProseStyle (declared in
        // story_reader_page.pagination.dart) so this render matches the
        // TextPainter measurement that decided this page's break point.
        Text(page.body, style: _kProseStyle),
      ],
    );
  }

  Widget _buildEndPage(_BookPage page) {
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
