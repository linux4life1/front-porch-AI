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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';

/// Scroll-mode position keeping: the list's controller, one key per chapter
/// heading, and the debounced save of the reader's scroll fraction.
class StoryScrollTracker {
  final ScrollController controller = ScrollController();
  final List<GlobalKey> chapterKeys = [];
  Timer? _saveTimer;

  /// Keeps one heading key per chapter.
  void syncChapterCount(int count) {
    if (chapterKeys.length != count) {
      chapterKeys
        ..clear()
        ..addAll(List.generate(count, (_) => GlobalKey()));
    }
  }

  /// Stores the scroll fraction on [project] and schedules [save] after a
  /// pause. Returns false (doing nothing) while the list is not attached.
  bool recordProgress(StoryProject project, VoidCallback save) {
    if (!controller.hasClients) return false;
    final max = controller.position.maxScrollExtent;
    project.readerScroll = max <= 0
        ? 0
        : (controller.offset / max).clamp(0.0, 1.0);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), save);
    return true;
  }

  /// Scrolled percentage of the list, 0 while unattached or unscrollable.
  int get percent =>
      controller.hasClients && controller.position.maxScrollExtent > 0
      ? (controller.offset / controller.position.maxScrollExtent * 100).round()
      : 0;

  /// The chapter whose heading is nearest above the top of the view.
  int visibleChapter() {
    var visible = 0;
    for (var i = 0; i < chapterKeys.length; i++) {
      final box = chapterKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= 160) visible = i;
    }
    return visible;
  }

  void jumpToChapter(int index) {
    if (index < 0 || index >= chapterKeys.length) return;
    final ctx = chapterKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      alignment: 0.02,
    );
  }

  void dispose() {
    _saveTimer?.cancel();
    controller.dispose();
  }
}
