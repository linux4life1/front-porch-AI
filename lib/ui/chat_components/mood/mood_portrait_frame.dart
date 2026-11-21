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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/realism_colors.dart';
import 'mood_look.dart';
import 'mood_ring.dart';

/// The chat sidebar's big portrait inside its mood ring: the character's
/// live mood, bond, trust and a need in trouble, from the chat's Realism
/// state alone. In a group the portrait is the focused member's, so the
/// ring reads that member's own registers, keyed by their card. Reads the
/// real storage for the setting; mounted by the chat page, never by a
/// widget under test with a fake storage.
class MoodPortraitFrame extends StatelessWidget {
  const MoodPortraitFrame({
    super.key,
    required this.chat,
    required this.character,
    required this.isGroup,
    required this.child,
  });

  final ChatService chat;
  final CharacterCard character;
  final bool isGroup;
  final Widget child;

  /// What the ring paints for [character], or null when nothing should.
  static MoodRingSpec? specFor(
    BuildContext context,
    ChatService chat,
    CharacterCard character, {
    required bool isGroup,
    required MoodLook look,
  }) {
    if (!look.portraitOn) return null;
    // A group member's ring answers to that member's own Realism switch.
    final id = chat.characterIdFor(character);
    final realism = isGroup
        ? chat.realismEnabledFor(id) && chat.isGroupMode
        : chat.realismEnabled;
    if (!realism) return null;
    final enjoysLowHygiene =
        character.frontPorchExtensions?.enjoysLowHygiene ?? false;
    final MoodState? mood;
    final int bond;
    final int trust;
    final Map<String, int> needs;
    if (isGroup) {
      mood = chat.getMoodForGroupCharacter(character);
      bond = chat.getAffectionForGroupCharacter(character);
      trust = chat.getTrustForGroupCharacter(character);
      needs = chat.needsActiveFor(id)
          ? visibleNeedsFor(
              chat.getNeedsForGroupCharacter(character),
              character,
            )
          : const {};
    } else {
      mood = MoodState(
        label: chat.characterEmotion,
        intensity: chat.emotionIntensity,
        held: chat.emotionHeldTurns,
      );
      bond = chat.relationshipService.affectionScore;
      trust = chat.relationshipService.trustLevel;
      needs = chat.needsActive
          ? visibleNeedsFor(chat.needsSimulation.vector, character)
          : const {};
    }
    final need = firstNeedInTrouble(needs, enjoysLowHygiene: enjoysLowHygiene);
    return MoodRingSpec(
      mood: mood == null
          ? MoodAtmosphere.none
          : MoodAtmosphere.of(mood, drama: look.drama),
      bond: bond,
      trust: trust,
      needHue: need == null ? null : RealismColors.needHueOf(context, need),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = MoodLook.of(Provider.of<StorageService>(context));
    final spec = specFor(
      context,
      chat,
      character,
      isGroup: isGroup,
      look: look,
    );
    if (spec == null) return child;
    return MoodRing(
      spec: spec,
      animate: !MediaQuery.disableAnimationsOf(context),
      radius: BorderRadius.circular(4),
      child: child,
    );
  }
}
