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

import 'package:front_porch_ai/services/waifu/waifu_honesty.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';

/// Stage directions: what happened to the turn, told as narration around
/// the coworker rather than in their voice. The plain technical line rides
/// along as [WaifuMessage.detail] so nothing the user needs is lost.
///
/// Lines use the coworker's name only. A card does not say which pronouns
/// to use, so none are guessed.
class WaifuStage {
  const WaifuStage(this.name);

  /// Built from the card; an unnamed card still reads as a sentence.
  factory WaifuStage.of(WaifuSession session) {
    final name = session.coworker.name.trim();
    return WaifuStage(name.isEmpty ? 'Your coworker' : name);
  }

  final String name;

  WaifuMessage stopped() => WaifuMessage.stage('$name sets the keyboard down.');

  WaifuMessage snag(Object error) =>
      WaifuMessage.stage('$name hit a snag.', detail: '$error');

  WaifuMessage lostLine(Object error) => WaifuMessage.stage(
    '$name lost the line to OpenCode. Send again to reconnect.',
    detail: '$error',
  );

  WaifuMessage cannotReachModel(String why) =>
      WaifuMessage.stage('$name cannot reach the model.', detail: why);

  WaifuMessage reverted() => WaifuMessage.stage(
    '$name rolls the last turn back.',
    detail: 'OpenCode reverted the files that turn changed.',
  );

  WaifuMessage restored() => WaifuMessage.stage(
    '$name puts the turn back.',
    detail: 'OpenCode restored the reverted turn.',
  );

  WaifuMessage nothingToUndo() => WaifuMessage.stage(
    '$name has nothing to take back yet.',
    detail: kWaifuUndoNeedsTurn,
  );

  WaifuMessage noPhotos() => WaifuMessage.stage(
    '$name cannot see photos on this model, so only the words go through.',
    detail: kWaifuPhotosUnsupported,
  );

  /// The work landed but the wrap-up line never came.
  WaifuMessage quietFinish() => WaifuMessage.stage(
    '$name finishes up without a word.',
    detail: 'The turn completed, but the wrap-up line did not arrive.',
  );

  /// Send with no backend or OpenCode behind the page.
  WaifuMessage noModel() => WaifuMessage.stage(
    '$name has nothing to work with yet. Your message is still in the box.',
    detail: kWaifuNoModel,
  );

  WaifuMessage noTools() => WaifuMessage.stage(
    '$name cannot pick up tools on this model.',
    detail: kWaifuToolsUnsupported,
  );
}

/// True when the coworker said anything since the last user line. With
/// [orNarrated], a stage row (an error, a lost line) counts too, so a
/// failed turn is not also told as a quiet finish.
bool waifuTurnSpoke(List<WaifuMessage> transcript, {bool orNarrated = false}) {
  for (final m in transcript.reversed) {
    if (m.kind == WaifuMsgKind.user) return false;
    if (orNarrated && m.kind == WaifuMsgKind.stage) return true;
    if (m.kind == WaifuMsgKind.assistant && m.text.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}
