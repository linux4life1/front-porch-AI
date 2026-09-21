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
  // Option B: never jumpTo(0) / pin to newest on send or stream. Do not
  // rewrite the reverse-list offset when content grows — that fight with
  // Flutter's own applyContentDimensions is what made the chat page jump.
}

/// Reverse list: offset 0 is the newest end. One-shot for open / session
/// restore only — not for tokens or a newly completed bubble.
bool pinTranscriptToLatest(ScrollController controller) {
  if (!controller.hasClients) return false;
  if (controller.offset != 0) controller.jumpTo(0);
  return true;
}
