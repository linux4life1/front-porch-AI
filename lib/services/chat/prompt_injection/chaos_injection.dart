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
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/group_member_realism.dart';

/// Plain chaos / Chance Time injection builder (_getChanceTimeInjection).
/// Thin in god per plan; full event text + mark delivered here (step 8).
class ChaosInjection {
  final ChaosModeService chaosModeService;
  final CharacterCard? Function() getActiveCharacter;

  /// PR 5b: the bag of the member pinned to answer THIS generation — a
  /// group's pending event lives on the member it was rolled for, and
  /// injects only when they speak. Null in 1:1 and before the seed,
  /// where the scalar path stays law.
  final GroupMemberRealism? Function()? getSpeakerBag;

  ChaosInjection({
    required this.chaosModeService,
    required this.getActiveCharacter,
    this.getSpeakerBag,
  });

  String buildChanceTimeInjection() {
    // Delegation to extracted service for pending + delivered flag (builder
    // here for step 8). Group: the speaker's own bag; a parked event that
    // belongs to another member waits for their turn — this builder runs
    // only for the member actually generating.
    final bag = getSpeakerBag?.call();
    final event = bag == null
        ? chaosModeService.pendingChaosInjection
        : chaosModeService.memberPending(bag);
    if (event == null || event.isEmpty) {
      return '';
    }
    final charName = getActiveCharacter()?.name ?? 'the character';
    // Mark as delivered via service so it can be cleared on the NEXT sendMessage.
    if (bag == null) {
      chaosModeService.markEventDelivered();
    } else {
      chaosModeService.markEventDeliveredMember(bag);
    }
    // Calm-but-firm house register (same as the needs-catastrophe block —
    // ALL-CAPS instruction walls read as jailbreak-fight energy and backfire
    // on local models). Placement stays post-suffix: a documented recency
    // choice, only to be moved after a measured A/B (spec §5b).
    return '\n[SCENE EVENT — CANON, happening this very moment:\n'
        '$event\n'
        'Open the reply with this event as it happens — do not skip it, '
        'soften it to a near-miss, or save it for later. If a detail does not '
        'fit this setting or era, swap it for the closest equivalent that '
        'does. Write $charName\'s immediate reaction in their own voice '
        'first, then let the scene continue from its consequences. Never '
        'mention "Chance Time", game mechanics, or systems.]\n';
  }
}
