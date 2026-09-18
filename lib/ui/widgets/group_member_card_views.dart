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

part of 'group_member_card.dart';

/// Per-build snapshot so expanded/compact stay byte-identical to the old
/// inlined locals. NeedsGrid stays the shared widget.
class _GroupMemberCardLook {
  const _GroupMemberCardLook({
    required this.chat,
    required this.isRealism,
    required this.emotion,
    required this.intensity,
    required this.affection,
    required this.longTerm,
    required this.trust,
    required this.arousal,
    required this.fixation,
    required this.fixationLife,
    required this.needs,
    required this.topNeeds,
    required this.ambitions,
    required this.memberObjectives,
    required this.bondTier,
    required this.bondName,
    required this.bondColor,
    required this.longTermTier,
    required this.longTermName,
    required this.trustTier,
    required this.trustName,
    required this.trustColor,
    required this.lustOn,
    required this.arousalTier,
    required this.arousalName,
    required this.arousalColor,
    required this.isDirector,
  });

  final ChatService chat;
  final bool isRealism;
  final String? emotion;
  final String? intensity;
  final int affection;
  final int longTerm;
  final int trust;
  final int arousal;
  final String? fixation;
  final int? fixationLife;
  final Map<String, int> needs;
  final List<(String, int)> topNeeds;
  final List<({String text, int progress})> ambitions;
  final List<Objective> memberObjectives;
  final int bondTier;
  final String bondName;
  final Color bondColor;
  final int longTermTier;
  final String longTermName;
  final int trustTier;
  final String trustName;
  final Color trustColor;
  final bool lustOn;
  final int arousalTier;
  final String arousalName;
  final Color arousalColor;
  final bool isDirector;
}

/// Expanded 1:1-parity body and compact mini-state. NeedsGrid stays shared.
extension _GroupMemberCardViews on _GroupMemberCardState {
  List<Widget> _expandedChildren(_GroupMemberCardLook look) {
    final chat = look.chat;
    final emotion = look.emotion;
    final intensity = look.intensity;
    final affection = look.affection;
    final longTerm = look.longTerm;
    final trust = look.trust;
    final arousal = look.arousal;
    final fixation = look.fixation;
    final fixationLife = look.fixationLife;
    final needs = look.needs;
    final ambitions = look.ambitions;
    final memberObjectives = look.memberObjectives;
    final bondTier = look.bondTier;
    final bondName = look.bondName;
    final bondColor = look.bondColor;
    final longTermTier = look.longTermTier;
    final longTermName = look.longTermName;
    final trustTier = look.trustTier;
    final trustName = look.trustName;
    final trustColor = look.trustColor;
    final lustOn = look.lustOn;
    final arousalTier = look.arousalTier;
    final arousalName = look.arousalName;
    final arousalColor = look.arousalColor;
    final isDirector = look.isDirector;
    return [
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
        icon: longTerm < 0 ? Icons.heart_broken_sharp : Icons.monitor_heart,
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
        FixationChip(topic: fixation, lifespan: fixationLife, compact: false),

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
                  chat.removePocketItem(id, section: section, index: index),
              onAdd: ({section}) async {
                final add = await showPocketItemDialog(
                  context,
                  characterName: widget.character.name,
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
              style: const TextStyle(fontSize: 11, color: AppColors.taskAccent),
            ),
            const Spacer(),
            TextButton(
              onPressed: widget.onOpenObjectives,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
              child: const Text('Manage', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _compactChildren(_GroupMemberCardLook look) {
    final chat = look.chat;
    final isRealism = look.isRealism;
    final emotion = look.emotion;
    final affection = look.affection;
    final trust = look.trust;
    final arousal = look.arousal;
    final fixation = look.fixation;
    final fixationLife = look.fixationLife;
    final topNeeds = look.topNeeds;
    final bondColor = look.bondColor;
    final trustColor = look.trustColor;
    final lustOn = look.lustOn;
    final arousalColor = look.arousalColor;
    return [
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
              style: TextStyle(fontSize: 10, color: emotionRingColor(emotion)),
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
            if (lustOn)
              MiniTierChip(label: 'L', value: arousal, color: arousalColor),
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
                const Icon(Icons.flag, size: 11, color: AppColors.taskAccent),
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
    ];
  }
}
