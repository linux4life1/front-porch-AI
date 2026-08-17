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

import 'package:front_porch_ai/services/chat/chat.dart'
    show AmbitionService, Pockets;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart'
    show showPocketItemDialog;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../porch_accordion.dart';
import 'ambitions_row.dart';
import 'pockets_row.dart';
import 'bond_bars.dart';
import 'character_state_settings.dart';
import 'time_strip.dart';
import 'today_line.dart';

/// 🎭 Character State — the first warm-porch accordion: everything about who
/// the character *is right now* in one card. 1:1 shows the emotion line,
/// the unified bond/trust/lust bars (BondBars — the nsfw_section merge),
/// fixation, needs grid, and the time strip; group mode shows the focused
/// member's GroupMemberCard (which renders the same shared bar widgets) plus
/// the shared time strip. The gear opens an inline settings flyout
/// (CharacterStateSettings) in both modes.
///
/// The realism master switch lives in the header for 1:1; group realism is
/// governed by Group Settings, so groups get only the gear.
class CharacterStateGroup extends StatefulWidget {
  final ChatService chat;
  final bool isGroup;

  /// The focused member's card, built by SidebarBody (needs page-level
  /// callbacks: remove, objectives, avatar file). Null in 1:1 mode.
  final Widget? groupMemberCard;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const CharacterStateGroup({
    super.key,
    required this.chat,
    required this.isGroup,
    this.groupMemberCard,
    required this.initiallyExpanded,
    this.onExpansionChanged,
  });

  @override
  State<CharacterStateGroup> createState() => _CharacterStateGroupState();
}

class _CharacterStateGroupState extends State<CharacterStateGroup> {
  bool _showSettings = false;
  final _accordionKey = GlobalKey<PorchAccordionState>();

  String _subtitle(ChatService chat) {
    if (widget.isGroup) {
      final active = chat.isGroupRealismActive;
      final time = TimeStrip.timeLabel(chat.timeService.timeOfDay);
      return active ? time : 'Realism off · $time';
    }
    if (!chat.realismEnabled) return 'Realism off';
    final rel = chat.relationshipService;
    final fixated = rel.activeFixation.isNotEmpty ? ' · 🧠' : '';
    return '${rel.shortTermTierName} · ${rel.trustTierName} · '
        '${TimeStrip.timeLabel(chat.timeService.timeOfDay)}$fixated';
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final realismOn = widget.isGroup
        ? chat.isGroupRealismActive
        : chat.realismEnabled;
    // Hoisted: this used to be called twice in the Ambitions guard below, and
    // it warms the ambition-progress cache on each call — cheap, but this
    // sidebar rebuilds on every notify during streaming, so once is right.
    final ambitions = chat.activeCharacter == null
        ? const <({String text, int progress})>[]
        : chat.ambitionsFor(chat.activeCharacter!);
    // Mirrors ChatService._clockRunning: the clock has TWO drivers, the engine
    // or the opt-in standalone clock. Porch Life only OFFERS that switch with
    // the engine off, so gating the strip on realism alone hid the clock in
    // the one configuration where a user can turn the standalone one on — it
    // was spending a model call per turn with nothing to show for it.
    final clockRunning =
        chat.timeService.passageOfTimeEnabled &&
        (chat.realismEnabled ||
            Provider.of<StorageService>(
              context,
            ).realismSettings.standaloneClockEnabled);

    return PorchAccordion(
      key: _accordionKey,
      id: 'character_state',
      emoji: '🎭',
      title: 'Character State',
      subtitle: _subtitle(chat),
      accent: AppColors.porchTerracottaOf(context),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.isGroup)
            SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: chat.realismEnabled,
                  activeThumbColor: AppColors.porchTerracottaOf(context),
                  onChanged: chat.isGenerating
                      ? null
                      : (val) {
                          chat.setRealismEnabled(val);
                          // Turning realism ON reveals the stats it enables
                          // (old RealismSection auto-expanded the same way).
                          if (val) _accordionKey.currentState?.expand();
                        },
                ),
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: 'Simulation settings',
            icon: const Icon(Icons.tune),
            color: _showSettings
                ? AppColors.porchTerracottaOf(context)
                : AppColors.iconSecondary(context),
            onPressed: () {
              setState(() => _showSettings = !_showSettings);
              // Opening the flyout while collapsed would show nothing.
              if (_showSettings) _accordionKey.currentState?.expand();
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!realismOn && !widget.isGroup)
            Text(
              'Realism Mode is off — flip the switch to track bond, trust, '
              'mood, needs, and scene time for this character.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          if (widget.isGroup && widget.groupMemberCard != null)
            widget.groupMemberCard!,
          // ── Standing Mood ──
          // OUTSIDE the realismOn gate on purpose. Standing Mood depends on
          // nothing (it is derived from needs, the clock and the weather, none
          // of which need the engine), so gating it here would be the exact
          // dead-switch bug the Porch Life tab exists to end: the feature would
          // still be colouring every reply while the user had no way to see it.
          //
          // It reads "Came in …" so it can never be mistaken for a reaction to
          // something the user did — which is the whole point of the feature.
          if (chat.standingMoodSummary.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_queue,
                  size: 13,
                  color: AppColors.textTertiary(context),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Came in ${chat.standingMoodSummary}',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (!widget.isGroup && realismOn) ...[
            // ── Emotion line ──
            if (chat.characterEmotion.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    _emotionEmoji(chat.characterEmotion),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${chat.characterEmotion.substring(0, 1).toUpperCase()}'
                      '${chat.characterEmotion.substring(1)} '
                      '(${chat.emotionIntensity})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            // ── Unified bars (bond / trust / lust) ──
            BondBars(chat: chat),
            // ── Fixation (replaces the old always-on chat_page banner; the
            //     accordion subtitle carries a 🧠 marker when collapsed) ──
            if (chat.relationshipService.activeFixation.isNotEmpty) ...[
              const SizedBox(height: 10),
              FixationChip(
                topic: chat.relationshipService.activeFixation,
                lifespan: chat.relationshipService.fixationLifespan,
                compact: false,
              ),
            ],
            // ── Needs ──
            if (chat.needsSimEnabled &&
                chat.needsSimulation.vector.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Needs',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 4),
              NeedsGrid(
                needs: chat.needsSimulation.vector,
                mini: false,
                crossAxisCount: 2,
              ),
            ],
          ],
          // ── Ambitions (Living Time §6) ──
          // Deliberately OUTSIDE the realism branch above. Ambitions are
          // card-authored text and their progress moves on quest completion,
          // so they need Objectives — not the Realism Engine. Sitting inside
          // that branch meant switching the engine off HID a feature that was
          // still running, which is the same class of bug the Porch Life tab
          // was built to end (docs/design/feature-independence.md).
          if (!widget.isGroup &&
              chat.objectivesActive &&
              chat.activeCharacter != null &&
              ambitions.isNotEmpty) ...[
            const SizedBox(height: 10),
            AmbitionsRow(
              ambitions: ambitions,
              // The quest climbing each mountain (v46). Reads the same
              // accessor in both modes — it returns the 1:1 list unchanged
              // when there is no group — so the step shown here and on the
              // group member card are computed identically.
              steps: AmbitionService.activeStepsFrom(
                chat.getObjectivesForGroupCharacter(chat.activeCharacter!),
              ),
            ),
          ],
          // Pockets & Wardrobe — answers to its own switch, so it sits OUTSIDE
          // the realism branch for the same reason Ambitions does.
          if (!widget.isGroup && chat.activeCharacter != null) ...[
            Builder(
              builder: (context) {
                // Feature off = panel absent. With it ON the panel renders
                // even for a missing/empty record, so the FIRST item can be
                // added by hand (2026-08-13 — the panel used to be ✕-only).
                if (!chat.pocketsFeatureEnabled) {
                  return const SizedBox.shrink();
                }
                final card = chat.activeCharacter!;
                final id = chat.characterIdFor(card);
                final p = chat.pocketsFor(id) ?? Pockets();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: PocketsRow(
                    pockets: p,
                    day: chat.storyDayCount,
                    onRemove: ({required section, required index}) =>
                        chat.removePocketItem(id, section: section, index: index),
                    onAdd: () async {
                      final add = await showPocketItemDialog(
                        context,
                        characterName: card.name,
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
          ],
          if (realismOn || widget.isGroup || clockRunning) ...[
            const SizedBox(height: 10),
            TimeStrip(chat: chat),
            ListenableBuilder(
              listenable: chat,
              builder: (context, _) => TodayLine(
                enabled: Provider.of<StorageService>(context)
                    .realismSettings
                    .plannerEnabled,
                text: chat.todaySentence,
                onDelete: () => chat.setTodaySentence(null),
              ),
            ),
          ],
          if (_showSettings) ...[
            const SizedBox(height: 10),
            CharacterStateSettings(chat: chat, isGroup: widget.isGroup),
          ],
        ],
      ),
    );
  }

  /// Emotion → emoji (ported verbatim from the old realism_section so the
  /// nuanced-word coverage doesn't change).
  String _emotionEmoji(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'amused':
      case 'playful':
      case 'happy':
        return '😄';
      case 'angry':
      case 'furious':
        return '😠';
      case 'sad':
      case 'melancholy':
        return '😢';
      case 'anxious':
      case 'nervous':
      case 'worried':
        return '😰';
      case 'excited':
      case 'thrilled':
        return '🤩';
      case 'flirtatious':
      case 'aroused':
        return '😏';
      case 'calm':
      case 'relaxed':
      case 'content':
        return '😌';
      case 'suspicious':
      case 'wary':
        return '🤨';
      case 'fearful':
      case 'scared':
        return '😨';
      case 'embarrassed':
      case 'flustered':
        return '😳';
      case 'annoyed':
      case 'irritated':
        return '😤';
      case 'confused':
      case 'conflicted':
        return '😕';
      case 'protective':
        return '🛡️';
      default:
        return '🎭';
    }
  }
}
