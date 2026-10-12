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

/// Shared prose text style, used at TWO sites that must stay byte-identical:
/// the TextPainter measuring pass in [paginateStory] (which decides where a
/// page break falls) and the actual on-page render in [BookPageContent]. If
/// the two ever drift — even by a font size or letter-spacing value — the
/// measured page break stops matching what's rendered, and prose silently
/// overflows or underflows at page boundaries. Edit this ONE constant; never
/// re-duplicate it at either call site.
const TextStyle kStoryProseStyle = TextStyle(
  fontFamily: 'Georgia',
  fontSize: 15,
  // theme-keep: book prop — the page ink stays this sepia-brown in every app
  // theme; it's the color of "text printed on paper", not app chrome.
  color: Color(0xFF3A2A1A), // theme-keep: book prop
  height: 1.75,
  letterSpacing: 0.2,
);

enum BookPageType { title, actTitle, prose, end }

/// One printed page of the book reader.
class BookPage {
  final BookPageType type;
  final String title;
  final String? subtitle;
  final String body;
  final int? actIndex;
  final int? sceneIndex;

  const BookPage({
    required this.type,
    required this.title,
    this.subtitle,
    required this.body,
    this.actIndex,
    this.sceneIndex,
  });
}
