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
import 'package:front_porch_ai/services/services.dart';

/// The kind of the phone's pending Chance Time event, for its wheel's
/// reveal: `kind` (the [ChaosCategory] name), `label` and `emoji`. Empty
/// when nothing is pending, so the keys are simply absent on the wire
/// (additive: an older PWA ignores them, an older desktop never sends them
/// and the PWA falls back to Wild Card's reveal).
Map<String, Object> chanceTimeKindWire(ChatService chat) {
  final raw = chat.controlsDoor.chance.webEvent;
  if (raw == null) return const {};
  final c = ChaosModeService.categoryOf(raw);
  return {'kind': c.name, 'label': c.label, 'emoji': c.emoji};
}
