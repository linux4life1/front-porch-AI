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
class ChatChanceTimeHost implements ChanceTimeHost {
  const ChatChanceTimeHost(this.chat);

  final ChatService chat;

  @override
  void consumeTrigger() => chat.consumeChanceTimeTrigger();

  @override
  List<String> spinWheelEvents() => chat.spinWheelEvents();

  @override
  String get speakerName => chat.chanceTimeSpeakerName;

  @override
  String resolve(String raw, String charName) =>
      chat.resolveChanceTimeEvent(raw, charName);

  @override
  Future<void> apply(String event, String charName) =>
      chat.applyChanceTimeResult(event, charName);
}
