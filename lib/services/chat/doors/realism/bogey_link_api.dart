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

import 'package:front_porch_ai/services/chat_service.dart';

/// The boon link's one write (docs/design/boons-and-bogies.md phase 7):
/// the desktop card's Link / Change picker and the web facade's `link`
/// action both call this, so the two surfaces cannot diverge. A plain
/// function, not a ChatService member, so the shell's public surface
/// (`test/baselines/chat_service_api.json`) is unchanged; tap-only, so the
/// golden fakes never meet it.
///
/// Links [ringId] (one of [ownerId]'s bogeys) to the boon [boonRingId], or
/// unlinks it with null. A boon from another owner, or one retired
/// meanwhile, is ignored.
Future<void> setBogeyLink(
  ChatService chat,
  String ownerId,
  String ringId,
  String? boonRingId,
) => chat.realism.growthDesk.setBogeyLink(ownerId, ringId, boonRingId);
