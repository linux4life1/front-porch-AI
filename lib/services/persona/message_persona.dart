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

import 'package:front_porch_ai/services/persona/user_persona.dart';

/// Metadata on a user message: the id of the persona it was sent as.
///
/// Persona names are not unique (people keep several "Sam"s with different
/// looks), so the name in `ChatMessage.sender` cannot say which one spoke.
const kUserPersonaIdMeta = 'user_persona_id';

/// The persona a user message was written as, or null when none matches.
///
/// 1. The id stamped at send ([kUserPersonaIdMeta]), while that persona
///    still exists.
/// 2. Unstamped (sent before the stamp existed) or the stamped persona was
///    deleted: the chat's [current] persona when its name is the sender's,
///    so a same-named persona never stands in for the one the chat uses.
/// 3. Otherwise the first persona with the sender's name.
UserPersona? personaForUserMessage({
  required List<UserPersona> personas,
  required UserPersona current,
  required String sender,
  Object? stampedId,
}) {
  if (stampedId is String && stampedId.isNotEmpty) {
    for (final p in personas) {
      if (p.id == stampedId) return p;
    }
  }
  if (current.name == sender && personas.any((p) => p.id == current.id)) {
    return current;
  }
  for (final p in personas) {
    if (p.name == sender) return p;
  }
  return null;
}
