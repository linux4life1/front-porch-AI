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

import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';

/// The toggles that act on one group member, by name: each takes the member's
/// id and answers false when it is not one of the group's.
final memberToggles =
    <String, Future<bool> Function(ChatToolsFacade, String, bool)>{
      'memberPockets': (f, id, v) => f.setMemberPockets(id, v),
      'memberAfterglow': (f, id, v) => f.setMemberAfterglow(id, v),
      'memberRealism': (f, id, v) => f.setMemberRealism(id, v),
      'memberNeeds': (f, id, v) => f.setMemberNeeds(id, v),
      // PR 5b: Chaos per member (docs/design/chaos-per-character.md).
      'memberChaos': (f, id, v) => f.setMemberChaos(id, v),
      'memberChaosNsfw': (f, id, v) => f.setMemberChaosNsfw(id, v),
    };
