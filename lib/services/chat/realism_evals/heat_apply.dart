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

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/heat_meter.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';

/// Applies the judge's `contact` read to Heat (docs/design/heat-meter.md)
/// and records what landed as `heat_delta` in [pending].
///
/// Called by the ONE eval that owns arousal this turn (the emotional judge
/// in multi-call, the fused judge in one-shot), right after Lust's delta
/// landed, with that effective [lustDelta]: an unwanted advance (a negative
/// delta) moves nobody toward release. A missing `contact` moves nothing.
/// Returns the Heat change that landed (0 when none).
int applyJudgedHeat(
  NsfwService nsfw,
  String text, {
  required int lustDelta,
  required Map<String, dynamic> pending,
}) {
  final contact = HeatMeter.parseContact(evalJsonString(text, 'contact'));
  if (contact == null) return 0;
  final landed = nsfw.applyHeatContact(contact, lustDelta: lustDelta);
  if (landed != 0) pending['heat_delta'] = landed;
  return landed;
}
