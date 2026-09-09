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

import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan_codec.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';

const kWaifuPlanBuildGateCue =
    'This session has a draft plan. Accept → Build, Revise, or Discard '
    'it before switching to Build.';

enum WaifuModeApply { applied, blockedDraft }

/// Main-stage Plan chrome is Plan mode only. Empty Plan is a one-line
/// hint. Build/Yolo keep the accepted plan in the prompt; the editor
/// does not stay on the composer.
bool waifuPlanStageVisible(WaifuSession session) {
  return session.mode == WaifuMode.plan;
}

/// Pin and last-write must be copied onto the panel widget at build.
/// `didUpdateWidget` comparing `oldWidget.session.activePlanPath` is a
/// no-op: the session is mutated in place, so both widgets see the new
/// value. Captured strings from the previous frame still differ.
bool waifuPlanPanelShouldReload({
  required String? previousPin,
  required String? nextPin,
  required String? previousWrite,
  required String? nextWrite,
  required WaifuMode previousMode,
  required WaifuMode nextMode,
}) {
  return previousPin != nextPin ||
      previousWrite != nextWrite ||
      previousMode != nextMode;
}

/// Soft gate: Build with no plan stays freeform. A draft pin/file blocks
/// a silent Plan→Build flip. Accepted pins may enter Build.
Future<WaifuModeApply> waifuTrySetMode({
  required WaifuSession session,
  required WaifuMode next,
}) async {
  if (next == WaifuMode.build && session.mode != WaifuMode.build) {
    final plan = await waifuLoadActivePlan(session);
    if (plan != null && plan.status == WaifuPlanStatus.draft) {
      return WaifuModeApply.blockedDraft;
    }
  }
  session.mode = next;
  return WaifuModeApply.applied;
}
