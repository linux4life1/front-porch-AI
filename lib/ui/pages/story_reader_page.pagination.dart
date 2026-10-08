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

/// Shared prose text style, used at TWO sites that must stay byte-identical:
/// the TextPainter measuring pass in this file's [_StoryReaderPagination]
/// (which decides where a page break falls) and the actual on-page render in
/// story_reader_page.pages.dart's `_buildProsePage`. If the two ever drift —
/// even by a font size or letter-spacing value — the measured page break stops
/// matching what's rendered, and prose silently overflows or underflows at
/// page boundaries. Edit this ONE constant; never re-duplicate it at either
/// call site.
const TextStyle _kProseStyle = TextStyle(
  fontFamily: 'Georgia',
  fontSize: 15,
  // theme-keep: book prop — the page ink stays this sepia-brown in every app
  // theme; it's the color of "text printed on paper", not app chrome.
  color: Color(0xFF3A2A1A), // theme-keep: book prop
  height: 1.75,
  letterSpacing: 0.2,
);

/// Text pagination for [_StoryReaderPageState]: measures available width/
/// height for the current layout and greedily binary-searches how much prose
/// fits per page (word-boundary snapped), plus the flip-page count derived
/// from the resulting page list. Extracted from the inline build() helpers;
/// direct state access preserves behavior.
extension _StoryReaderPagination on _StoryReaderPageState {
  void _buildPages(BoxConstraints constraints, bool isTwoPageSpread) {
    if (_pages != null && _lastConstraints == constraints) {
      return; // Already built for this size
    }
    _lastConstraints = constraints;

    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) {
      _pages = [
        _BookPage(type: _PageType.title, title: 'Story Not Found', body: ''),
      ];
      return;
    }

    // Determine available height and width for text
    final mq = MediaQuery.of(context);

    double availableWidth =
        (isTwoPageSpread ? constraints.maxWidth / 2 : constraints.maxWidth) -
        72;
    if (availableWidth > (600 - 72)) availableWidth = 600 - 72;

    // Subtract external elements from available height:
    // kToolbarHeight (56), SafeArea top/bottom padding, page margins (64), and page padding (96).
    // Adding a 20px extra buffer for text rendering strictness.
    double availableHeight =
        constraints.maxHeight -
        kToolbarHeight -
        mq.padding.top -
        mq.padding.bottom -
        96 // Page padding
        -
        64 // Margin outside book
        -
        24; // Extra safety buffer

    final List<_BookPage> newPages = [];

    // Title page
    newPages.add(
      _BookPage(
        type: _PageType.title,
        title: project.title,
        body: project.concept,
      ),
    );

    final textStyle = _kProseStyle;

    // Assemble prose pages
    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      final scenes = project.scenes[actIdx] ?? [];

      // Act title page
      newPages.add(
        _BookPage(
          type: _PageType.actTitle,
          title: 'Act ${act.number}',
          subtitle: act.title,
          body: act.description,
        ),
      );

      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];

        // Collect all prose for this scene
        final proseBuffer = StringBuffer();
        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose =
              project.prose[bId]?.final_ ?? project.prose[bId]?.draft ?? '';
          if (prose.isNotEmpty) {
            if (proseBuffer.isNotEmpty) proseBuffer.write('\n\n');
            proseBuffer.write(prose);
          }
        }

        final fullProse = proseBuffer.toString();
        if (fullProse.isEmpty) continue;

        // Header takes up some height (~80px to safely clear the title and margins)
        final headerHeight = 80.0;
        var isFirstPage = true;

        // Split text dynamically
        String remainingText = fullProse;

        while (remainingText.isNotEmpty) {
          final currentAvailableHeight = isFirstPage
              ? availableHeight - headerHeight
              : availableHeight;

          // Find how much text fits
          int startLimit = 0;
          int endLimit = remainingText.length;
          int bestFitLength = endLimit;

          while (startLimit <= endLimit) {
            final mid = (startLimit + endLimit) ~/ 2;
            String testChunk = remainingText.substring(0, mid);

            // Avoid breaking words if possible
            if (mid < remainingText.length &&
                remainingText[mid] != ' ' &&
                remainingText[mid] != '\n') {
              final lastSpace = testChunk.lastIndexOf(RegExp(r'\s'));
              if (lastSpace != -1) {
                testChunk = testChunk.substring(0, lastSpace);
              }
            }

            final tp = TextPainter(
              text: TextSpan(text: testChunk, style: textStyle),
              textDirection: TextDirection.ltr,
            );
            tp.layout(maxWidth: availableWidth);

            if (tp.size.height <= currentAvailableHeight) {
              bestFitLength = testChunk.length;
              startLimit = mid + 1;
            } else {
              endLimit = mid - 1;
            }
          }

          if (bestFitLength == 0) {
            bestFitLength = 1; // Prevent infinite loop on tiny screens
          }

          // Snap strictly to word boundary for aesthetic
          if (bestFitLength < remainingText.length) {
            final testSubstring = remainingText.substring(0, bestFitLength);
            final lastSpace = testSubstring.lastIndexOf(RegExp(r'\s'));
            if (lastSpace > 0 && lastSpace > bestFitLength * 0.5) {
              // Only snap if space isn't too far back
              bestFitLength = lastSpace;
            }
          }

          final chunk = remainingText.substring(0, bestFitLength).trim();
          newPages.add(
            _BookPage(
              type: _PageType.prose,
              title: isFirstPage ? scene.title : '',
              subtitle: isFirstPage ? scene.location : '',
              body: chunk,
              actIndex: actIdx,
              sceneIndex: sceneIdx,
            ),
          );

          remainingText = remainingText.substring(bestFitLength).trimLeft();
          isFirstPage = false;
        }
      }
    }

    // End page
    newPages.add(
      _BookPage(
        type: _PageType.end,
        title: 'The End',
        body: '— ${project.title} —',
      ),
    );

    _pages = newPages;
  }

  /// Calculates the number of flip views.
  /// On wide screens (2 pages per flip), the count is Math.ceil(_pages.length / 2).
  /// On narrow screens (1 page per flip), it equals _pages.length.
  int _getFlipPageCount() {
    if (_pages == null) return 0;
    final width = MediaQuery.of(context).size.width;
    if (width > 800) {
      return (_pages!.length / 2).ceil();
    }
    return _pages!.length;
  }
}

// ── Page model ──

enum _PageType { title, actTitle, prose, end }

class _BookPage {
  final _PageType type;
  final String title;
  final String? subtitle;
  final String body;
  final int? actIndex;
  final int? sceneIndex;

  const _BookPage({
    required this.type,
    required this.title,
    this.subtitle,
    required this.body,
    this.actIndex,
    this.sceneIndex,
  });
}
