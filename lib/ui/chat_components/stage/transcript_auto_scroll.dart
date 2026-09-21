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

void applyTranscriptAutoScroll(
  ScrollController controller, {
  required bool generating,
}) {
  // Option B: never jumpTo(0) / pin to newest. [generating] is unused
  // on purpose. Viewport hold on reverse-list growth lives on
  // [TranscriptScrollController] via [heldTranscriptOffset].
}

/// Reverse-list hold. Offset is distance from the newest edge; when that
/// end grows, add the growth so the same rows stay on screen — even at
/// offset 0 (already watching generation).
double heldTranscriptOffset({
  required double offset,
  required double previousMax,
  required double newMax,
  required double minExtent,
}) {
  final growth = newMax - previousMax;
  if (growth == 0) return offset;
  final next = offset + growth;
  if (next < minExtent) return minExtent;
  if (next > newMax) return newMax;
  return next;
}
