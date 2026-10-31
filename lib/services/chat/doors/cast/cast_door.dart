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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/away_pulse_runner.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_collapse.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_controller.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_deps.dart';
import 'package:front_porch_ai/services/chat/doors/cast/director_stage.dart';
import 'package:front_porch_ai/services/chat/doors/cast/greeting_baseline.dart';
import 'package:front_porch_ai/services/chat/doors/cast/greeting_picker.dart';
import 'package:front_porch_ai/services/chat/doors/cast/guest_flow.dart';
import 'package:front_porch_ai/services/chat/doors/cast/guest_join.dart';
import 'package:front_porch_ai/services/chat/doors/cast/idle_autonomy.dart';

export 'package:front_porch_ai/services/chat/doors/cast/away_pulse_runner.dart';
export 'package:front_porch_ai/services/chat/doors/cast/cast_collapse.dart';
export 'package:front_porch_ai/services/chat/doors/cast/cast_controller.dart';
export 'package:front_porch_ai/services/chat/doors/cast/cast_deps.dart';
export 'package:front_porch_ai/services/chat/doors/cast/director_stage.dart';
export 'package:front_porch_ai/services/chat/doors/cast/greeting_baseline.dart';
export 'package:front_porch_ai/services/chat/doors/cast/greeting_picker.dart';
export 'package:front_porch_ai/services/chat/doors/cast/guest_flow.dart';
export 'package:front_porch_ai/services/chat/doors/cast/guest_join.dart';
export 'package:front_porch_ai/services/chat/doors/cast/idle_autonomy.dart';

/// Who is in the scene and how they come and go: the group roster and its
/// exits, 1:1 Scene Guests, the opening greeting, the Away pulse and the
/// idle (AFK) turns.
///
/// Not a notifier: every part calls the shell's `notifyListeners` in place
/// ([CastDeps.notify]), as the parts this replaces did.
///
/// A `/join`ed guest in a 1:1 is a guest on both rosters (#648): a 1:1
/// guest stays in [GuestFlow.state] and turns into a soft group member
/// (tier lite) when the chat becomes a group, never a silent full member.
class CastDoor {
  CastDoor(this._d);

  final CastDeps _d;

  late final CastController roster = CastController(this, _d);
  late final CastCollapse collapse = CastCollapse(this, _d);
  late final DirectorStage stage = DirectorStage(this, _d);
  late final GuestFlow guests = GuestFlow(this, _d);
  late final GuestJoin joins = GuestJoin(this, _d);
  late final GreetingPicker greetings = GreetingPicker(this, _d);
  late final GreetingBaseline baseline = GreetingBaseline(this, _d);
  late final AwayPulseRunner away = AwayPulseRunner(_d);
  late final IdleAutonomy idle = IdleAutonomy(_d);

  /// One-shot hidden stage direction for the next speaker (an entrance, a
  /// goodbye, the user stepping off or on stage). The prompt consumes it.
  String? entranceDirective;

  /// A `/narrate` call is in flight (it runs before the turn it starts).
  bool narrating = false;

  /// The director's pinned scene goal and private whispers, saved per chat.
  final DirectorScene directorScene = DirectorScene();

  /// The chat changed (chat, character or session switched) or the service
  /// was disposed since [token] (a session id snapshot) was taken. Async
  /// cast work bails after an await when this is true.
  bool sceneChanged(String? token) =>
      _d.hooks.disposed() || _d.session.currentSessionId != token;
}
