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

part of 'waifu_harness.dart';

extension WaifuHarnessPlan on WaifuHarness {
  Future<void> _refreshPlanBlock() async {
    _planBlock = await waifuPlanPromptBlock(
      root: session.folderRoot,
      mode: session.mode,
      activePlanPath: session.activePlanPath,
    );
  }

  Future<WaifuPlan?> acceptActivePlan({String? editedBody}) async {
    permissions.mode = session.mode;
    final plan = await waifuAcceptPlan(
      session: session,
      todos: todos,
      editedBody: editedBody,
    );
    permissions.mode = session.mode;
    await _refreshPlanBlock();
    await store?.saveLast(session);
    _emit();
    return plan;
  }

  Future<WaifuPlan?> reviseActivePlan({String? editedBody}) async {
    final plan = await waifuRevisePlan(
      session: session,
      editedBody: editedBody,
    );
    permissions.mode = session.mode;
    await _refreshPlanBlock();
    await store?.saveLast(session);
    _emit();
    return plan;
  }

  Future<void> discardActivePlan() async {
    await waifuDiscardPlan(session);
    permissions.mode = session.mode;
    await _refreshPlanBlock();
    await store?.saveLast(session);
    _emit();
  }
}
