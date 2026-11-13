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

import 'package:front_porch_ai/services/services.dart';

/// What the Chance Time overlay asks of the chat: the trigger to consume,
/// the eight events, who they name, how a raw event reads, and the apply
/// that resumes the parked send. The product host wraps [ChatService]'s
/// chance door; a test stands in with its own events.
abstract interface class ChanceTimeHost {
  void consumeTrigger();
  List<String> spinWheelEvents();
  String get speakerName;
  String resolve(String raw, String charName);
  Future<void> apply(String event, String charName);
}

/// The overlay's host in the app: the chance door through its old names.
/// PR 5b: a group's manual spin from a member's card passes [memberName] —
/// the wheel gates on that member (their spicy switch, their hard lock)
/// and the event lands on their state. Null keeps the pre-PR surface: the
/// upcoming speaker, the chat's gate.
class ChatChanceTimeHost implements ChanceTimeHost {
  const ChatChanceTimeHost(this.chat, {this.memberName});

  final ChatService chat;
  final String? memberName;

  @override
  void consumeTrigger() => chat.consumeChanceTimeTrigger();

  @override
  List<String> spinWheelEvents() => chat.spinWheelEvents(forName: memberName);

  @override
  String get speakerName => memberName ?? chat.chanceTimeSpeakerName;

  @override
  String resolve(String raw, String charName) =>
      chat.resolveChanceTimeEvent(raw, charName);

  @override
  Future<void> apply(String event, String charName) =>
      chat.applyChanceTimeResult(event, charName);
}
