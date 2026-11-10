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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show AmbitionService, PocketSection, Pockets, visibleNeeds, visibleNeedsFor;
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart'
    show showPocketItemDialog;
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'ambitions_row.dart';
import 'needs_line.dart';
import 'pockets_gate_line.dart';
import 'pockets_row.dart';
import 'presence_word.dart';
import 'time_strip.dart';

// The Character State leaves that read a character, 1:1 host or group member
// alike. [member] is the focused group member, or null for the 1:1 host
// (whose reads are the chat's live scalars and active character).

/// The Needs line and, while Needs run, its full rows.
class NeedsLeaf extends StatelessWidget {
  const NeedsLeaf({
    super.key,
    required this.chat,
    this.member,
    this.pulseInTrouble = false,
  });

  final ChatService chat;
  final CharacterCard? member;
  final bool pulseInTrouble;

  @override
  Widget build(BuildContext context) {
    final member = this.member;
    final card = member ?? chat.activeCharacter;
    // A group member's vector is theirs, never the live one (that holds
    // whoever spoke last).
    final vector = member == null
        ? chat.needsSimulation.vector
        : chat.getNeedsForGroupCharacter(member);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeedsLine(chat: chat, inGroup: member != null),
        // The bars show while Needs run: the gate (Realism, this chat's
        // Needs switch, the Porch Life one), not the stored switch, or
        // they sit frozen with Needs off and read as live.
        if (chat.needsActive && vector.isNotEmpty) ...[
          const SizedBox(height: 4),
          NeedsGrid(
            needs: member == null
                ? visibleNeeds(
                    vector,
                    card?.frontPorchExtensions?.needsOff ?? const [],
                  )
                : visibleNeedsFor(vector, member),
            mini: false,
            crossAxisCount: 2,
            pulseInTrouble: pulseInTrouble,
            enjoysLowHygiene:
                card?.frontPorchExtensions?.enjoysLowHygiene ?? false,
          ),
        ],
      ],
    );
  }
}

/// Ambitions (Living Time §6) for [card], with the quest climbing each.
///
/// Deliberately OUTSIDE the realism branch: ambitions are card-authored text
/// and their progress moves on quest completion, so they need Objectives,
/// not the Realism Engine (docs/design/feature-independence.md).
class AmbitionsLeaf extends StatelessWidget {
  const AmbitionsLeaf({super.key, required this.chat, required this.card});

  final ChatService chat;
  final CharacterCard card;

  @override
  Widget build(BuildContext context) => AmbitionsRow(
    ambitions: chat.ambitionsFor(card),
    // The quest climbing each mountain (v46). The accessor returns the 1:1
    // list unchanged when there is no group, so the step is computed the
    // same way for the host and for a member.
    steps: AmbitionService.activeStepsFrom(
      chat.getObjectivesForGroupCharacter(card),
    ),
  );
}

/// Pockets & Wardrobe for [card]: the gate line, and the panel while live.
/// Answers to its own switch, so it sits OUTSIDE the realism branch.
class PocketsLeaf extends StatelessWidget {
  const PocketsLeaf({super.key, required this.chat, required this.card});

  final ChatService chat;
  final CharacterCard card;

  @override
  Widget build(BuildContext context) {
    // v64 (docs/design/pockets-wardrobe-chat-toggle.md): the gate LINE is
    // always up — its switch is how an off chat turns back on, and an off
    // chat says "retained, not tracked" (hide ≠ erase, spoken aloud).
    // Feature off = the PANEL absent, never greyed; with it ON the panel
    // renders even for an empty record, so the FIRST item can be added by
    // hand.
    final id = chat.characterIdFor(card);
    final live = chat.pocketsEnabledFor(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PocketsGateLine(chat: chat, characterId: id, characterName: card.name),
        if (live) ...[
          const SizedBox(height: 4),
          // The bars-show-from-the-gate rule (Error Book 2026-10-08): the
          // panel asks the LIVE gate, not the stored switch.
          PocketsRow(
            pockets: chat.pocketsFor(id) ?? Pockets(),
            day: chat.storyDayCount,
            onRemove: ({required section, required index}) =>
                chat.removePocketItem(id, section: section, index: index),
            onAdd: ({section}) async {
              final add = await showPocketItemDialog(
                context,
                characterName: card.name,
                initialSection: section ?? PocketSection.carrying,
              );
              if (add == null) return;
              await chat.addPocketItem(
                id,
                section: add.section,
                name: add.name,
                gift: add.gift,
                correction: add.correction,
              );
            },
          ),
        ],
      ],
    );
  }
}

/// The time strip and where the character is. A group member's word is
/// theirs, and tapping it marks them Away or brings them back: the one place
/// a member is set Away.
class TimeLeaf extends StatelessWidget {
  const TimeLeaf({super.key, required this.chat, this.member, this.stripKey});

  final ChatService chat;
  final CharacterCard? member;
  final Key? stripKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TimeStrip(key: stripKey, chat: chat),
        ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final member = this.member;
            if (member != null) return _memberWord(context, member);
            final ext = chat.activeCharacter?.frontPorchExtensions;
            return PresenceWord(
              where: derivePresence(
                occupation: ext?.occupation ?? '',
                hours: ext?.hours ?? '',
                clockMinutes: chat.timeService.clockMinutes,
                weekday: chat.timeService.clock.weekday,
                workDays: ext?.workDays,
                inScene: inSceneForPresence(
                  stance: chat.relationshipService.spatialStance,
                  withUser: chat.relationshipService.withUser,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _memberWord(BuildContext context, CharacterCard member) {
    CharacterRepository? repo;
    try {
      repo = Provider.of<CharacterRepository>(context, listen: false);
    } on ProviderNotFoundException {
      repo = null;
    }
    final work = workFieldsForMember(member, repo?.characters ?? const []);
    final where = derivePresence(
      occupation: work.occupation,
      hours: work.hours,
      clockMinutes: chat.timeService.clockMinutes,
      weekday: chat.timeService.clock.weekday,
      workDays: work.workDays,
      inScene: inSceneForPresence(
        stance: chat.spatialStanceForGroupCharacter(member),
        withUser: chat.withUserForGroupCharacter(member),
      ),
    );
    return PresenceWord(
      where: where,
      // Same busy read the service refuses on, or a tap while post-gen
      // settles looks live and does nothing.
      onToggle: chat.isTurnBusy
          ? null
          : () => chat.setGroupMemberAway(
              chat.characterIdFor(member),
              away: where == PresenceWhere.withYou,
            ),
    );
  }
}
