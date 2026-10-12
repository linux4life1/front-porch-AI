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

/// The one generation flight [ImageGenService] runs at a time: the lock, the
/// status line, the last picture and the live progress. Every change that the
/// UI must see goes out through [notify] (the service's notifyListeners).
class ImageGenStatus {
  ImageGenStatus(this.notify);

  final VoidCallback notify;

  bool isGenerating = false;

  /// True while an expression pack holds the lock, so the frames it runs
  /// can go through it without refusing themselves.
  bool packFlight = false;
  String statusMessage = '';
  Uint8List? lastGeneratedImage;
  String? lastSavedPath;

  /// Live generation progress (0..1) and the latest in-progress preview
  /// frame, so the UI can show the image "coming to life" instead of a
  /// spinner. Fed per backend: A1111 polls /sdapi/v1/progress (percent +
  /// preview), ComfyUI streams its WebSocket (percent + preview when the
  /// server has previews enabled), Draw Things reports sampling steps
  /// (percent only). Remote APIs return in one shot — both stay null there
  /// (indeterminate). Cleared at the start and end of every generation.
  double? genProgress;
  Uint8List? genPreview;

  void updateGenProgress(double? progress, [Uint8List? preview]) {
    genProgress = progress;
    if (preview != null) genPreview = preview;
    notify();
  }

  /// Sets the status line and tells listeners.
  void say(String message) {
    statusMessage = message;
    notify();
  }

  /// Ends a generation's hold on the lock, unless a pack holds it.
  void endGenerationLock() {
    if (packFlight) return;
    isGenerating = false;
  }
}
