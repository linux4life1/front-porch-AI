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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// The tools snapshot's chaos block, built in one place (PR 5b,
/// docs/design/chaos-per-character.md). In a group it speaks for the
/// focused member through their own member-scoped reads; in 1:1 (a null
/// [switchId]) for the chat's scalars, unchanged. The cast list drives
/// the dice badge on the cast chips.
Map<String, dynamic> chaosBlock(
  ChatService chat,
  ChaosModeService chaos, {
  CharacterCard? switchOwner,
  String? switchId,
}) {
  final group = switchOwner != null && switchId != null;
  return {
    'enabled': group
        ? chat.chaosSwitchFor(switchId)
        : chaos.chaosModeEnabled,
    'nsfwEnabled': group
        ? chat.chaosNsfwFor(switchId)
        : chaos.chaosNsfwEnabled,
    'pressure': group
        ? chat.chaosPressureFor(switchId)
        : chaos.chaosPressure,
    'hasPendingEvent': group
        ? chat.chaosHasPendingFor(switchId)
        : chaos.hasPendingChaosEvent,
    // Additive: the spicy row shows only with 18+ themes on, and the
    // hint reads the Porch Life frequency and any cooldown.
    'adultAllowed': chaos.adultAllowed,
    'base': chaos.frequency.base,
    'growth': chaos.frequency.growth,
    'cooldownTurns': group
        ? chat.chaosCooldownFor(switchId)
        : chaos.cooldownTurns,
    // Whose chaos this block carries (the id the toggle and the spin
    // routes take), and the cast-wide on/off for the badge on the
    // cast chips — visible without selecting each member.
    'memberId': group ? groupMemberStoreId(switchOwner) : null,
    'cast': [
      for (final c in chat.groupCharacters)
        if (!c.isLite && chat.characterIdFor(c).isNotEmpty)
          {
            'memberId': groupMemberStoreId(c),
            'name': c.name,
            'enabled': chat.chaosSwitchFor(chat.characterIdFor(c)),
          },
    ],
  };
}

/// Shared spin helper: a group spin carries the cast member's store id,
/// which the spin matches to the session id, the same conversion the
/// member toggles make.
bool requestManualSpin({
  required ChatService chat,
  String? memberId,
}) {
  if (memberId == null || memberId.isEmpty) {
    return chat.requestManualChanceTime();
  }
  for (final c in chat.groupCharacters) {
    if (groupMemberStoreId(c) != memberId || c.isLite) continue;
    return chat.requestManualChanceTime(memberId: chat.characterIdFor(c));
  }
  return false;
}
