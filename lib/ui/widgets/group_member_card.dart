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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart'
    show showPocketItemDialog;
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/tier_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_progress_row.dart';
import 'package:front_porch_ai/ui/widgets/needs_bar.dart';
import 'package:front_porch_ai/ui/widgets/fixation_chip.dart';
import 'package:front_porch_ai/ui/widgets/group_member_chips.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// First-class representation of a group chat member in the sidebar.
///
/// Implements the required "speaker expanded / others compact" model:
/// - The current/next speaker (or explicitly tapped member) renders the
///   *full rich view* that is visually and structurally identical to the
///   1:1 chat sidebar (separate Short-Term Bond + Long-Term Bond rows,
///   full 7-need grid, fixation card treatment, etc.).
/// - All other members render in a compact, scannable mini state
///   (emotion ring, name, tiny tier indicators, fixation tag, mini needs).
///
/// This replaces the old bolted-on ListTile + enormous subtitle pattern
/// that produced jank, hidden needs, and tiny fixation text.
class GroupMemberCard extends StatefulWidget {
  final CharacterCard character;
  final ChatService chatService;
  final Color avatarColor;
  final bool isNextSpeaker;
  final bool isExpanded;
  final VoidCallback onTap; // promote to expanded / set next speaker
  final File? avatarFile; // pre-resolved for performance

  /// Active Growth Rings count (🌱 badge; 0 hides it).
  final int ringCount;
  final bool canRemove;
  final VoidCallback? onRemove;
  final VoidCallback? onOpenObjectives;

  const GroupMemberCard({
    super.key,
    required this.character,
    required this.chatService,
    required this.avatarColor,
    required this.isNextSpeaker,
    required this.isExpanded,
    required this.onTap,
    this.avatarFile,
    this.ringCount = 0,
    this.canRemove = false,
    this.onRemove,
    this.onOpenObjectives,
  });

  @override
  State<GroupMemberCard> createState() => _GroupMemberCardState();
}

class _GroupMemberCardState extends State<GroupMemberCard> {
  @override
  Widget build(BuildContext context) {
    final chat = widget.chatService;
    // Public getters — isGroupRealismActive reads a library-private field
    // and cannot be faked. Same formula.
    final isRealism =
        chat.realismEnabled && chat.isGroupMode && !chat.observerMode;

    // Resolve per-character state (only meaningful when realism is on)
    final emotion = isRealism
        ? (chat.getEmotionForGroupCharacter(widget.character) ?? 'neutral')
        : null;
    final intensity = isRealism
        ? chat.getEmotionIntensityForGroupCharacter(widget.character)
        : null;
    final affection = isRealism
        ? chat.getAffectionForGroupCharacter(widget.character)
        : 0;
    final longTerm = isRealism
        ? chat.getLongTermForGroupCharacter(widget.character)
        : 0;
    final trust = isRealism
        ? chat.getTrustForGroupCharacter(widget.character)
        : 0;
    final arousal = isRealism
        ? chat.getArousalForGroupCharacter(widget.character)
        : 0;
    final fixation = isRealism
        ? chat.getFixationForGroupCharacter(widget.character)
        : null;
    final fixationLife = isRealism
        ? chat.getFixationLifespanForGroupCharacter(widget.character)
        : null;
    final needs = isRealism
        ? chat.getNeedsForGroupCharacter(widget.character)
        : const <String, int>{};
    final topNeeds = isRealism
        ? chat.getTopUrgentNeedsForGroupCharacter(widget.character, count: 2)
        : const <(String, int)>[];
    // Hoisted: both of these were called twice further down (ambitions guard +
    // row, and the active-objectives count). This card renders once per group
    // member on every notify, so the duplicates were paid per member per frame.
    final ambitions = chat.ambitionsFor(widget.character);
    final memberObjectives = chat.getObjectivesForGroupCharacter(
      widget.character,
    );

    final bondTier = RelationshipService.bondTierFor(affection);
    final bondName = RelationshipService.bondTierLabel(bondTier);
    final longTermTier = RelationshipService.bondTierFor(longTerm);
    final longTermName = RelationshipService.longTermTierLabel(longTermTier);
    final bondColor = TierColors.tierColor(context, bondTier);

    final trustTier = RelationshipService.bondTierFor(trust);
    // Trust has its own vocabulary ('Deeply Trusting'), and it is a +/-100
    // scale. Using the bond table here printed bond words like 'Smitten'
    // against a trust score.
    final trustName = RelationshipService.trustTierLabel(trustTier);
    final trustColor = TierColors.tierColor(context, trustTier);

    // Lust visibility follows the stable per-member group flag (the live
    // nsfwService scalar is per-speaker-volatile in groups).
    final lustOn = isRealism && chat.isGroupNsfwEnabled;
    // Arousal has its own ±100 ladder (level ÷ 10) and its own vocabulary, and
    // both must be read for THIS member. The tier came from the bond ladder,
    // and the name came from nsfwService.arousalTierName — the LIVE SPEAKER's
    // scalar — so in a group every member's card showed whoever spoke last.
    final arousalTier = NsfwService.arousalTierForLevel(arousal);
    final arousalName = chat.nsfwService.arousalTierNameForLevel(arousal);
    final arousalColor = arousalTier >= 6
        ? AppColors.lustDeepOf(context)
        : arousalTier <= -1
        ? AppColors.frostAccentOf(context)
        : AppColors.lustAccentOf(context);

    final ext = widget.character.frontPorchExtensions;
    CharacterRepository? repo;
    try {
      repo = Provider.of<CharacterRepository>(context, listen: false);
    } on ProviderNotFoundException {
      repo = null;
    }
    final library = MemberOriginResolver.resolve(
      stampedOriginStableId: null,
      memberName: widget.character.name,
      libraryCharacters: repo?.characters ?? const [],
    );
    final work = workFieldsForGroupMember(
      copyOccupation: ext?.occupation ?? '',
      copyHours: ext?.hours ?? '',
      libraryOccupation: library?.frontPorchExtensions?.occupation,
      libraryHours: library?.frontPorchExtensions?.hours,
    );
    final presence = PresenceWord(
      where: derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        timeOfDay: chat.timeService.timeOfDay,
        inScene: !stanceSaysAway(
          chat.spatialStanceForGroupCharacter(widget.character),
        ),
      ),
      padTop: false,
    );
    final isDirector = chat.observerMode;
    // Away / At work uses the signed 0.45. Director 0.38 is only for With you.
    final opacity = presence.dimCard ? 0.45 : (isDirector ? 0.38 : 1.0);

    final ringColor = (emotion != null && isRealism)
        ? emotionRingColor(emotion)
        : widget.avatarColor;

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: widget.onTap,
        // NOTE: secondary (right-click "Edit Group") is deliberately on the header-only wrapper below
        // so that expanded rich-view children (IconButton, TextButton, inner GestureDetectors) do not absorb it.
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: widget.isExpanded
                ? AppColors.resolve(
                    context,
                    Colors.white.withValues(alpha: 0.035),
                    Colors.black.withValues(alpha: 0.04),
                  )
                : (widget.isNextSpeaker
                      ? widget.avatarColor.withValues(alpha: 0.10)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: widget.isNextSpeaker
                ? Border.all(
                    color: widget.avatarColor.withValues(alpha: 0.45),
                    width: 1.2,
                  )
                : (widget.isExpanded
                      ? Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                        )
                      : null),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row (avatar + name + badges) — secondary tap only here for reliable "Edit Group" right-click
                // even on fully-expanded rich speaker view (avoids child gesture absorption).
                GestureDetector(
                  onSecondaryTapUp: (details) {
                    final active = widget.chatService.activeGroup;
                    if (active == null) return;
                    final position = details.globalPosition;
                    showMenu<String>(
                      context: context,
                      position: RelativeRect.fromLTRB(
                        position.dx,
                        position.dy,
                        position.dx,
                        position.dy,
                      ),
                      color: AppColors.surfaceContainerOf(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      items: [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(
                              Icons.edit,
                              color: AppColors.iconSecondary(context),
                              size: 20,
                            ),
                            title: const Text('Edit Group'),
                            dense: true,
                          ),
                        ),
                      ],
                    ).then((value) {
                      if (value == 'edit' && mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditGroupPage(group: active),
                          ),
                        );
                      }
                    });
                  },
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ringColor,
                            width: widget.isExpanded ? 2.5 : 2.0,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: widget.isExpanded ? 18 : 16,
                          backgroundColor: widget.avatarColor,
                          backgroundImage: widget.avatarFile != null
                              ? FileImage(widget.avatarFile!)
                              : null,
                          child: widget.avatarFile == null
                              ? Text(
                                  widget.character.name.isNotEmpty
                                      ? widget.character.name[0]
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.character.name,
                          style: TextStyle(
                            fontSize: widget.isExpanded ? 14 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      presence,
                      const SizedBox(width: 6),
                      if (widget.isNextSpeaker)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: widget.avatarColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEXT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (widget.ringCount > 0) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message:
                              '${widget.ringCount} growth ring'
                              '${widget.ringCount == 1 ? '' : 's'}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.porchHoneyOf(
                                context,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '🌱${widget.ringCount}',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.porchHoneyOf(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (widget.canRemove && widget.onRemove != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          onPressed: widget.onRemove,
                          color: AppColors.textTertiary(context),
                          tooltip: 'Remove from group',
                        ),
                    ],
                  ),
                ),

                // === EXPANDED (speaker) — full 1:1 parity view ===
                if (widget.isExpanded && isRealism) ...[
                  const SizedBox(height: 8),
                  // Emotion
                  Row(
                    children: [
                      Text(
                        EmotionLabels.emoji[emotion] ?? '🎭',
                        style: const TextStyle(fontSize: 15),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(emotion ?? 'neutral')[0].toUpperCase()}${(emotion ?? 'neutral').substring(1)}${intensity != null && intensity.isNotEmpty ? ' ($intensity)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: emotionRingColor(emotion ?? 'neutral'),
                        ),
                      ),
                      if (isDirector) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.pause_circle_outline,
                          size: 12,
                          color: Colors.amberAccent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Short-Term Bond (exact 1:1 treatment)
                  RealismProgressRow(
                    label: 'Short-Term Bond',
                    value: affection,
                    tier: bondTier,
                    tierName: bondName,
                    color: bondColor,
                    // Fill toward the NEXT tier, then drain and refill — the
                    // same bar the 1:1 sidebar draws. The group card used the
                    // absolute ±300 fill, so the same score looked different
                    // depending on which screen you were on.
                    progress: RelationshipService.bondScalePercent(affection),
                    icon: affection < 0 ? Icons.heart_broken : Icons.favorite,
                  ),
                  const SizedBox(height: 8),

                  // Long-Term Bond. This row was fed `affection` — the SHORT
                  // term score — so the card drew the same number twice.
                  RealismProgressRow(
                    label: 'Long-Term Bond',
                    value: longTerm,
                    tier: longTermTier,
                    tierName: longTermName,
                    progress: RelationshipService.bondScalePercent(longTerm),
                    color: TierColors.tierColor(context, longTermTier),
                    icon: longTerm < 0
                        ? Icons.heart_broken_sharp
                        : Icons.monitor_heart,
                  ),
                  const SizedBox(height: 8),

                  // Trust
                  RealismProgressRow(
                    label: 'Trust',
                    value: trust,
                    progress: RelationshipService.trustScalePercent(trust),
                    tier: trustTier,
                    tierName: trustName,
                    color: trustColor,
                    icon: trust < 0 ? Icons.vpn_key_off : Icons.vpn_key,
                    maxValue: 100,
                  ),
                  const SizedBox(height: 8),

                  // Lust (the merged arousal bar — same treatment as 1:1)
                  if (lustOn) ...[
                    RealismProgressRow(
                      label: 'Lust',
                      value: arousal,
                      tier: arousalTier,
                      tierName: arousalName,
                      color: arousalColor,
                      icon: arousalTier >= 6
                          ? Icons.local_fire_department
                          : arousalTier <= -1
                          ? Icons.ac_unit
                          : Icons.favorite_border,
                      maxValue: 100,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Fixation (rich card)
                  if (fixation != null && fixation.isNotEmpty)
                    FixationChip(
                      topic: fixation,
                      lifespan: fixationLife,
                      compact: false,
                    ),

                  // Full needs grid
                  if (needs.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Needs',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    NeedsGrid(needs: needs, mini: false, crossAxisCount: 2),
                  ],

                  // Ambitions (Living Time §6) — per-member, same widget and
                  // same v46 step merge as the 1:1 Character State accordion.
                  // The objectivesActive gate matches 1:1 and the web facade,
                  // which both had it; this card did not, so Objectives-off
                  // showed ambitions nothing could move — and would have named
                  // an open quest from the disabled feature (Grok, 2026-08-07).
                  if (chat.objectivesActive && ambitions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    AmbitionsRow(
                      ambitions: ambitions,
                      steps: AmbitionService.activeStepsFrom(memberObjectives),
                    ),
                  ],

                  // Pockets & Wardrobe — per-member, the same widget the 1:1
                  // Character State accordion uses.
                  //
                  // A group had NO wardrobe surface at all until 2026-08-08:
                  // the only mount was gated `!isGroup`, so the eval ran every
                  // turn per member, the injection told the model what each of
                  // them was wearing, the web drawer displayed it — and on
                  // desktop a group member's pockets were invisible, with the
                  // hand-remove that "stops a wrong entry becoming permanent"
                  // unreachable. Needs and Ambitions were already per-member
                  // here; wardrobe simply never followed them across.
                  Builder(
                    builder: (context) {
                      // Same off-absent / on-even-when-empty gate as the 1:1
                      // panel (2026-08-13, add-by-hand parity).
                      if (!chat.pocketsFeatureEnabled) {
                        return const SizedBox.shrink();
                      }
                      final id = chat.characterIdFor(widget.character);
                      final p = chat.pocketsFor(id) ?? Pockets();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: PocketsRow(
                          pockets: p,
                          day: chat.storyDayCount,
                          onRemove: ({required section, required index}) =>
                              chat.removePocketItem(
                                id,
                                section: section,
                                index: index,
                              ),
                          onAdd: () async {
                            final add = await showPocketItemDialog(
                              context,
                              characterName: widget.character.name,
                            );
                            if (add == null) return;
                            await chat.addPocketItem(
                              id,
                              section: add.section,
                              name: add.name,
                              gift: add.gift,
                            );
                          },
                        ),
                      );
                    },
                  ),

                  // Objectives quick access
                  if (widget.onOpenObjectives != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.flag, size: 13, color: AppColors.taskAccent),
                        const SizedBox(width: 4),
                        Text(
                          '${memberObjectives.where((o) => o.active).length} active objectives',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.taskAccent,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onOpenObjectives,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                          ),
                          child: const Text(
                            'Manage',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],

                // === COMPACT (non-speaker) — mini state only ===
                if (!widget.isExpanded) ...[
                  const SizedBox(height: 6),
                  if (isRealism && emotion != null)
                    Row(
                      children: [
                        Text(
                          EmotionLabels.emoji[emotion] ?? '🎭',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          emotion[0].toUpperCase() + emotion.substring(1),
                          style: TextStyle(
                            fontSize: 10,
                            color: emotionRingColor(emotion),
                          ),
                        ),
                        const Spacer(),
                        if (fixation != null && fixation.isNotEmpty)
                          FixationChip(
                            topic: fixation,
                            lifespan: fixationLife,
                            compact: true,
                          ),
                      ],
                    ),
                  if (isRealism) ...[
                    const SizedBox(height: 4),
                    // Compact bond/trust/arousal + mini needs
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        MiniTierChip(label: 'B', value: affection, color: bondColor),
                        MiniTierChip(label: 'T', value: trust, color: trustColor),
                        if (lustOn) MiniTierChip(label: 'L', value: arousal, color: arousalColor),
                        if (topNeeds.isNotEmpty)
                          ...topNeeds.map((n) => MiniNeedChip(name: n.$1, value: n.$2)),
                      ],
                    ),
                  ],
                  // Subtle hint when realism is off
                  if (!isRealism)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Realism off — enable in sidebar for per-character state',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textTertiary(context),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                  // Compact objectives count
                  if (widget.onOpenObjectives != null) ...[
                    const SizedBox(height: 3),
                    Builder(
                      builder: (ctx) {
                        final count = chat
                            .getObjectivesForGroupCharacter(widget.character)
                            .where((o) => o.active)
                            .length;
                        if (count == 0) return const SizedBox.shrink();
                        return Row(
                          children: [
                            const Icon(
                              Icons.flag,
                              size: 11,
                              color: AppColors.taskAccent,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$count obj',
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.taskAccent,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: widget.onOpenObjectives,
                              child: const Text(
                                'edit',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.taskAccent,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- tiny helpers for compact row ---
}
