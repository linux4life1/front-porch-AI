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

/// Text pagination for the book reader: measures available width/height for
/// the current layout and greedily binary-searches how much prose fits per
/// page (word-boundary snapped). [viewPadding] is the reader's MediaQuery
/// padding.
List<BookPage> paginateStory({
  required StoryProject? project,
  required BoxConstraints constraints,
  required bool isTwoPageSpread,
  required EdgeInsets viewPadding,
}) {
  if (project == null) {
    return [
      BookPage(type: BookPageType.title, title: 'Story Not Found', body: ''),
    ];
  }

  // Determine available height and width for text

  double availableWidth =
      (isTwoPageSpread ? constraints.maxWidth / 2 : constraints.maxWidth) - 72;
  if (availableWidth > (600 - 72)) availableWidth = 600 - 72;

  // Subtract external elements from available height:
  // kToolbarHeight (56), SafeArea top/bottom padding, page margins (64), and page padding (96).
  // Adding a 20px extra buffer for text rendering strictness.
  double availableHeight =
      constraints.maxHeight -
      kToolbarHeight -
      viewPadding.top -
      viewPadding.bottom -
      96 // Page padding
      -
      64 // Margin outside book
      -
      24; // Extra safety buffer

  final List<BookPage> newPages = [];

  // Title page
  newPages.add(
    BookPage(
      type: BookPageType.title,
      title: project.title,
      body: project.concept,
    ),
  );

  final textStyle = kStoryProseStyle;

  // Assemble prose pages
  for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
    final act = project.acts[actIdx];
    final scenes = project.scenes[actIdx] ?? [];

    // Act title page
    newPages.add(
      BookPage(
        type: BookPageType.actTitle,
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
          BookPage(
            type: BookPageType.prose,
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
    BookPage(
      type: BookPageType.end,
      title: 'The End',
      body: '— ${project.title} —',
    ),
  );

  return newPages;
}

/// Calculates the number of flip views.
/// On wide screens (2 pages per flip), the count is Math.ceil(pages.length / 2).
/// On narrow screens (1 page per flip), it equals pages.length.
int flipPageCountFor(List<BookPage> pages, double screenWidth) {
  if (screenWidth > 800) {
    return (pages.length / 2).ceil();
  }
  return pages.length;
}

/// The text content for a given flip-page index.
String flipPageText(List<BookPage> pages, int flipPage, bool isTwoPageSpread) {
  if (isTwoPageSpread) {
    final leftIdx = flipPage * 2;
    final rightIdx = leftIdx + 1;
    final buf = StringBuffer();
    if (leftIdx < pages.length) {
      buf.write('${pages[leftIdx].title}. ${pages[leftIdx].body}\n\n');
    }
    if (rightIdx < pages.length) {
      buf.write('${pages[rightIdx].title}. ${pages[rightIdx].body}');
    }
    return buf.toString();
  } else {
    if (flipPage < pages.length) {
      return '${pages[flipPage].title}. ${pages[flipPage].body}';
    }
    return '';
  }
}
