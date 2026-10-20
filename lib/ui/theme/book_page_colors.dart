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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The story reader's printed page: paper and ink for one app theme.
///
/// The page is a prop, so it does not follow light/dark mode within a theme;
/// each theme picks one page. Porch keeps cream paper and sepia ink; darker
/// themes may print light ink on a dark page. Read it with [of].
@immutable
class BookPageColors {
  const BookPageColors({
    required this.paperEdge,
    required this.paper,
    required this.paperInner,
    required this.cover,
    required this.edgeShade,
    required this.inkStrong,
    required this.ink,
    required this.inkWarm,
    required this.inkMuted,
    required this.inkFaint,
  });

  /// The paper gradient: outer edge, middle, and the edge by the spine.
  final Color paperEdge;
  final Color paper;
  final Color paperInner;

  /// The back cover after the last page.
  final Color cover;

  /// The faint shade along the page's outer edge.
  final Color edgeShade;

  /// Titles.
  final Color inkStrong;

  /// Prose.
  final Color ink;

  /// Drop caps and chapter ornaments.
  final Color inkWarm;

  /// Subtitles and summaries.
  final Color inkMuted;

  /// Flourishes, rules, page numbers and running heads.
  final Color inkFaint;

  /// Cream paper and sepia ink: the page every theme had before themes.
  static const BookPageColors cream = BookPageColors(
    paperEdge: Color(0xFFF0E5CC),
    paper: Color(0xFFFAF3E8),
    paperInner: Color(0xFFF5ECD7),
    cover: Color(0xFFE8DCC8),
    edgeShade: Color(0x14795548),
    inkStrong: Color(0xFF2C1810),
    ink: Color(0xFF3A2A1A),
    inkWarm: Color(0xFF4A2F1D),
    inkMuted: Color(0xFF5A4A3A),
    inkFaint: Color(0xFF8B7355),
  );

  /// The active theme's page.
  static BookPageColors of(BuildContext context) => AppPalette.of(context).page;

  List<Color> get _roles => [
    paperEdge,
    paper,
    paperInner,
    cover,
    edgeShade,
    inkStrong,
    ink,
    inkWarm,
    inkMuted,
    inkFaint,
  ];

  static BookPageColors lerp(BookPageColors a, BookPageColors b, double t) {
    Color c(Color Function(BookPageColors p) role) =>
        Color.lerp(role(a), role(b), t)!;
    return BookPageColors(
      paperEdge: c((p) => p.paperEdge),
      paper: c((p) => p.paper),
      paperInner: c((p) => p.paperInner),
      cover: c((p) => p.cover),
      edgeShade: c((p) => p.edgeShade),
      inkStrong: c((p) => p.inkStrong),
      ink: c((p) => p.ink),
      inkWarm: c((p) => p.inkWarm),
      inkMuted: c((p) => p.inkMuted),
      inkFaint: c((p) => p.inkFaint),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookPageColors && listEquals(_roles, other._roles);

  @override
  int get hashCode => Object.hashAll(_roles);
}
