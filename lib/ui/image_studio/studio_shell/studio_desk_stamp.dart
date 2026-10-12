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

import 'package:front_porch_ai/services/storage/storage.dart';

/// Remembers which desk graph + model files the last generate ran against, so
/// a refusal can be dropped once either has changed.
class StudioDeskStamp {
  String _graph = '';
  String _model = '';

  /// Records the current desk choice. True when it changed since a previous
  /// recording (the very first recording never counts as a change).
  bool changed(ImageGenSettings settings) {
    final graph =
        '${settings.comfyCreateWorkflowId}|${settings.comfyEditWorkflowId}';
    final model =
        '${settings.imageGenModel}|${settings.imageGenEditModel}|${settings.comfyCreateModelChoices}|${settings.comfyEditModelChoices}';
    final first = _graph.isEmpty && _model.isEmpty;
    if (graph == _graph && model == _model) return false;
    _graph = graph;
    _model = model;
    return !first;
  }
}
