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

/// A scene action on the board, addressed by act and scene index.
typedef StructureSceneAction = void Function(int act, int scene);

/// What the Structure board asks its page to do. The page runs the
/// pipeline, the dialogs and the saves; the board only draws and taps.
class StructureBoardActions {
  /// Opens or closes an act; [open] is whether it was open when drawn.
  final void Function(int act, bool open) onToggleAct;
  final ValueChanged<int> onEditAct;
  final ValueChanged<int> onGenerateAct;
  final ValueChanged<int> onPlanSequence;
  final StructureSceneAction onOpenScene;
  final StructureSceneAction onWriteScene;
  final StructureSceneAction onPlanBeats;
  final StructureSceneAction onEditScene;
  final StructureSceneAction onInsertAfter;
  final StructureSceneAction onRewriteScene;
  final StructureSceneAction onDeleteScene;

  const StructureBoardActions({
    required this.onToggleAct,
    required this.onEditAct,
    required this.onGenerateAct,
    required this.onPlanSequence,
    required this.onOpenScene,
    required this.onWriteScene,
    required this.onPlanBeats,
    required this.onEditScene,
    required this.onInsertAfter,
    required this.onRewriteScene,
    required this.onDeleteScene,
  });
}
