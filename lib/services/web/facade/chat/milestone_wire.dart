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

import 'package:front_porch_ai/services/chat/milestone_burst.dart'
    show burstSeedFor;
import 'package:front_porch_ai/services/chat_service.dart';

/// The milestone card on screen, for the chat-state snapshot
/// (docs/design/boons-and-bogies.md §7): the same [MilestoneView] the
/// desktop card reads, plus whether it replays and the seed its
/// celebration draws from. Null when no card is up — and then only the
/// shell forwarder [ChatService.milestoneShowing] was read, which the golden
/// fakes answer.
Map<String, dynamic>? milestoneWire(ChatService chat) {
  final showing = chat.milestoneShowing;
  if (showing == null) return null;
  return {
    ...chat.milestoneViewOf(showing).toJson(),
    'replaying': chat.milestoneReplaying,
    'seed': burstSeedFor(showing.id),
  };
}
