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
    show AmbitionService, PocketSection, Pockets, StoryClock, visibleNeeds;
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart'
    show showPocketItemDialog;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../porch_accordion.dart';
import 'ambitions_row.dart';
import 'pockets_row.dart';
import 'bond_bars.dart';
import 'needs_line.dart';
import 'time_strip.dart';
import 'presence_word.dart';

/// 🎭 Character State — the first warm-porch accordion: everything about who
/// the character *is right now* in one card. 1:1 shows the unified
/// bond/trust/lust bars (BondBars — the nsfw_section merge),
/// fixation, needs grid, and the time strip; group mode shows the focused
/// member's GroupMemberCard (which renders the same shared bar widgets) plus
/// the shared time strip.
///
/// The realism master switch lives in the header for 1:1; group realism is
/// governed by Group Settings. There is no settings gear: Needs is set on the
/// card (or in Group Settings), and One-Shot Eval sits above the tool-calling
/// pill (OneShotEvalRow).
class CharacterStateGroup extends StatefulWidget {
  final ChatService chat;
  final bool isGroup;

  /// The focused member's card, built by SidebarBody (needs page-level
  /// callbacks: remove, objectives, avatar file). Null in 1:1 mode.
  final Widget? groupMemberCard;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  /// OPEN_SECTION=timestrip scrolls this [TimeStrip], not the CS header.
  final Key? timeStripKey;

  const CharacterStateGroup({
    super.key,
    required this.chat,
    required this.isGroup,
    this.groupMemberCard,
    required this.initiallyExpanded,
    this.onExpansionChanged,
    this.timeStripKey,
  });

  @override
  State<CharacterStateGroup> createState() => CharacterStateGroupState();
}

class CharacterStateGroupState extends State<CharacterStateGroup> {
  final _accordionKey = GlobalKey<PorchAccordionState>();

  void expand() => _accordionKey.currentState?.expand();

  void collapse() => _accordionKey.currentState?.collapse();

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
    // Porch Life allows Realism: this chat's switch then is the gate itself.
    // While it does not, the switch greys out at the chat's own choice.
    final realismAllowed = realismAllowedOf(context);
    final realismSwitch = realismAllowed
        ? chat.realismEnabled
        : chat.realismChatSwitch;
    // Hoisted: this used to be called twice in the Ambitions guard below, and
    // it warms the ambition-progress cache on each call — cheap, but this
    // sidebar rebuilds on every notify during streaming, so once is right.
    final ambitions = chat.activeCharacter == null
        ? const <({String text, int progress})>[]
        : chat.ambitionsFor(chat.activeCharacter!);
    // Mirrors ChatService._clockRunning: Porch Life Passage of Time, live.
    final clockRunning = StoryClock.isRunning(
      passageOfTimeEnabled: Provider.of<StorageService>(
        context,
      ).realismSettings.passageOfTimeDefault,
    );

    return PorchAccordion(
      key: _accordionKey,
      id: 'character_state',
      emoji: '🎭',
      title: 'Character State',
      subtitle: _subtitle(chat),
      accent: AppColors.porchTerracottaOf(context),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      trailing: widget.isGroup
          ? null
          : SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: realismSwitch,
                  activeThumbColor: AppColors.porchTerracottaOf(context),
                  onChanged: !realismAllowed || chat.isGenerating
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!realismOn && !widget.isGroup)
            Text(
              realismAllowed
                  ? 'Realism Mode is off — flip the switch to track bond, '
                        'trust, mood, and scene time for this character.'
                  : "The Realism Engine is off in Porch Life. This chat's "
                        'own choice is kept.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          if (widget.isGroup && widget.groupMemberCard != null)
            widget.groupMemberCard!,
          if (!widget.isGroup && realismOn) ...[
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
          ],
          if (!widget.isGroup && realismOn) ...[
            const SizedBox(height: 10),
            NeedsLine(chat: chat),
          ],
          // The bars show while Needs run: the gate (Realism, this chat's
          // Needs switch, the Porch Life one), not the stored switch, or
          // they sit frozen with Needs off and read as live.
          if (!widget.isGroup &&
              chat.needsActive &&
              chat.needsSimulation.vector.isNotEmpty) ...[
            const SizedBox(height: 4),
            NeedsGrid(
              needs: visibleNeeds(
                chat.needsSimulation.vector,
                chat.activeCharacter?.frontPorchExtensions?.needsOff ??
                    const [],
              ),
              mini: false,
              crossAxisCount: 2,
            ),
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
                final card = chat.activeCharacter!;
                final id = chat.characterIdFor(card);
                if (!chat.pocketsEnabledFor(id)) {
                  return const SizedBox.shrink();
                }
                final p = chat.pocketsFor(id) ?? Pockets();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: PocketsRow(
                    pockets: p,
                    day: chat.storyDayCount,
                    onRemove: ({required section, required index}) => chat
                        .removePocketItem(id, section: section, index: index),
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
                );
              },
            ),
          ],
          if (realismOn || widget.isGroup || clockRunning) ...[
            const SizedBox(height: 10),
            TimeStrip(key: widget.timeStripKey, chat: chat),
            ListenableBuilder(
              listenable: chat,
              builder: (context, _) {
                final ext = chat.activeCharacter?.frontPorchExtensions;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isGroup)
                      PresenceWord(
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
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
