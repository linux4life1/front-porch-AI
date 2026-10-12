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

import 'dart:convert';

import 'package:front_porch_ai/services/image/image.dart';

/// A request to the phone desk that is refused, with a stable [code] and
/// words for the person. Nothing has been changed when this is thrown.
class DeskRefused implements Exception {
  const DeskRefused(this.code, this.message, [this.status = 400]);

  final String code;
  final String message;
  final int status;

  @override
  String toString() => 'DeskRefused($code)';
}

/// The most a graph file, or a picture to edit, may weigh.
const int kMaxDeskGraphBytes = 8 * 1024 * 1024;
const int kMaxDeskPictureBytes = 12 * 1024 * 1024;

/// Whether a config write would store a ComfyUI graph the caller supplied.
/// A graph is what Comfy runs on this computer, so it is credential-grade.
bool imageConfigUploadsGraph(Map<String, dynamic> body) {
  for (final key in [
    'comfyCreateUploadedWorkflow',
    'comfyEditUploadedWorkflow',
  ]) {
    final value = body[key];
    if (value is String && value.trim().isNotEmpty) return true;
  }
  return false;
}

/// [raw] as a ComfyUI graph the desk may store: within the size limit and a
/// JSON object. Throws [DeskRefused] otherwise.
String checkedDeskGraph(String raw) {
  if (utf8.encode(raw).length > kMaxDeskGraphBytes) {
    throw const DeskRefused(
      'too_large',
      'That graph is too large to use.',
      413,
    );
  }
  final kept = pngWorkflowText({'prompt': raw});
  if (kept == null || workflowNodeCount(kept) == 0) {
    throw const DeskRefused('not_graph', 'That file isn’t a ComfyUI graph.');
  }
  return kept;
}
