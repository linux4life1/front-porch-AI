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
import '../../mood/mood_look.dart';

import '../porch_accordion.dart';
import '../sidebar_reorder.dart';
import 'ambitions_row.dart';
import 'pockets_gate_line.dart';
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
/// Inside the accordion every portion is its own reorderable leaf — the off
/// note, the member card, the bars, the needs, ambitions, pockets and the
/// time strip each carry a grip and move within this accordion (ids and
/// defaults live in `SidebarLayout` under container `character_state`).
/// Gates travel with the leaf: the Needs grid still shows from the live
/// `needsActive` gate, not the stored switch (Error Book 2026-10-08).
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

  /// Appearance → Mood on the character, resolved by the sidebar body with
  /// the real storage; the needs bars throb with it. Off by default.
  final MoodLook moodLook;

  /// The reorder grip when this accordion sits in the reorderable body.
  final Widget? dragHandle;

  const CharacterStateGroup({
    super.key,
    required this.chat,
    required this.isGroup,
    this.groupMemberCard,
    required this.initiallyExpanded,
    this.onExpansionChanged,
    this.timeStripKey,
    this.moodLook = MoodLook.off,
    this.dragHandle,
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
    // The switch shows this chat's own choice. While Porch Life blocks
    // Realism it greys out there; a change made mid-reply lands when the
    // reply settles, and the note says so meanwhile.
    final realismAllowed = realismAllowedOf(context);
    final realismSwitch = chat.realismChatSwitch;
    // Hoisted: this used to be called twice in the Ambitions guard below, and
    // it warms the ambition-progress cache on each call — cheap, but this
    // sidebar rebuilds on every notify during streaming, so once is right.
    final ambitions = chat.activeCharacter == null
        ? const <({String text, int progress})>[]
        : chat.ambitionsFor(chat.activeCharacter!);
    // Mirrors ChatService._clockRunning: Porch Life Passage of Time, live.
    final storage = Provider.of<StorageService>(context);
    final clockRunning = StoryClock.isRunning(
      passageOfTimeEnabled: storage.realismSettings.passageOfTimeDefault,
    );
    // The portion order, remembered per surface-global leaf list; the ids
    // this chat can show right now filter the stored order and any unknown
    // id appends per the default (hidden portions keep their stored slot).
    final ui = storage.uiSettings;
    final hasCharacter = chat.activeCharacter != null;
    final visible = <String>[
      if (!widget.isGroup && !realismOn) 'realism_off',
      if (widget.isGroup && widget.groupMemberCard != null) 'member_card',
      if (!widget.isGroup && realismOn) 'bond_bars',
      if (!widget.isGroup &&
          realismOn &&
          chat.relationshipService.activeFixation.isNotEmpty)
        'fixation',
      // The NeedsLine leaf; its grid has the live needsActive gate inside.
      if (!widget.isGroup && realismOn) 'needs',
      if (!widget.isGroup &&
          chat.objectivesActive &&
          hasCharacter &&
          ambitions.isNotEmpty)
        'ambitions',
      // The pockets leaf stays up while a character is in the chat —
      // v64: its switch is the ONLY 1:1 way back on (the card editor is
      // the default, not the runtime switch), so an off chat must show
      // the line, like Needs does. The PANEL inside keeps its own gate.
      if (!widget.isGroup && hasCharacter) 'pockets',
      if (realismOn || widget.isGroup || clockRunning) 'time',
    ];
    final ordered = ui.sidebarLeafOrderFor('character_state', visible);
    final pump = ReorderScrollPump.maybeOf(context);

    return PorchAccordion(
      key: _accordionKey,
      id: 'character_state',
      emoji: '🎭',
      title: 'Character State',
      subtitle: _subtitle(chat),
      accent: AppColors.porchTerracottaOf(context),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      dragHandle: widget.dragHandle,
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
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        // The lifted leaf must not eat the wheel hit test (see sidebar_body
        // for why); signals fall through to the armed pump listeners below.
        proxyDecorator: (child, index, animation) => IgnorePointer(
          child: Material(
            elevation: 2,
            shadowColor: Colors.transparent,
            child: child,
          ),
        ),
        itemCount: ordered.length,
        // The body pumps its wheel scroll for portion drags too.
        onReorderStart: (_) => pump?.reportDrag(true),
        onReorderEnd: (_) => pump?.reportDrag(false),
        onReorderItem: (from, to) => ui.setSidebarLeafOrder(
          'character_state',
          _reorderIds(ordered, from, to),
        ),
        itemBuilder: (context, i) => WheelPump(
          // A portion in hand pumps the body's scroll (see [WheelPump]);
          // the item key lives here, where the list can see it.
          key: ValueKey('sidebar-leaf-${ordered[i]}'),
          pump: pump,
          child: Padding(
            // The old Column's 10px gap between portions, not after the last.
            padding: EdgeInsets.only(bottom: i == ordered.length - 1 ? 0 : 10),
            child: _part(context, chat, ordered[i], i),
          ),
        ),
      ),
    );
  }

  /// One accordion portion with its reorder grip leading. The grip is the
  /// first element of the row and wrapped opaque, so a grip tap never reaches
  /// the portion's own controls (Error Book P44).
  Widget _part(BuildContext context, ChatService chat, String id, int index) {
    final grip = opaqueReorderHandle(SidebarReorderHandle(index: index));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        grip,
        const SizedBox(width: 6),
        Expanded(child: _portion(context, chat, id)),
      ],
    );
  }

  /// The portion widget for [id], gates exactly as the old fixed Column had
  /// them.
  Widget _portion(BuildContext context, ChatService chat, String id) {
    final realismAllowed = realismAllowedOf(context);
    final realismSwitch = chat.realismChatSwitch;
    switch (id) {
      case 'realism_off':
        return Text(
          !realismAllowed
              ? "The Realism Engine is off in Porch Life. This chat's "
                    'own choice is kept.'
              : realismSwitch
              // Allowed again mid-reply: it lands when the reply settles.
              ? 'Realism starts again when this reply finishes.'
              : 'The Realism Engine is off for this chat — flip the '
                    'switch to track bond, trust, mood, and scene time for '
                    'this character.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        );
      case 'member_card':
        return widget.groupMemberCard!;
      case 'bond_bars':
        // ── Unified bars (bond / trust / lust) ──
        return BondBars(chat: chat);
      case 'fixation':
        // ── Fixation: its own movable portion (replaces the old always-on
        //     chat_page banner; the accordion subtitle carries a 🧠 marker
        //     when collapsed) ──
        return FixationChip(
          topic: chat.relationshipService.activeFixation,
          lifespan: chat.relationshipService.fixationLifespan,
          compact: false,
        );
      case 'needs':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NeedsLine(chat: chat),
            // The bars show while Needs run: the gate (Realism, this chat's
            // Needs switch, the Porch Life one), not the stored switch, or
            // they sit frozen with Needs off and read as live.
            if (chat.needsActive && chat.needsSimulation.vector.isNotEmpty) ...[
              const SizedBox(height: 4),
              NeedsGrid(
                needs: visibleNeeds(
                  chat.needsSimulation.vector,
                  chat.activeCharacter?.frontPorchExtensions?.needsOff ??
                      const [],
                ),
                mini: false,
                crossAxisCount: 2,
                pulseInTrouble: widget.moodLook.portraitOn,
                enjoysLowHygiene:
                    chat
                        .activeCharacter
                        ?.frontPorchExtensions
                        ?.enjoysLowHygiene ??
                    false,
              ),
            ],
          ],
        );
      case 'ambitions':
        // ── Ambitions (Living Time §6) ──
        // Deliberately OUTSIDE the realism branch. Ambitions are
        // card-authored text and their progress moves on quest completion,
        // so they need Objectives — not the Realism Engine. Sitting inside
        // that branch meant switching the engine off HID a feature that was
        // still running, which is the same class of bug the Porch Life tab
        // was built to end (docs/design/feature-independence.md).
        return AmbitionsRow(
          ambitions: chat.ambitionsFor(chat.activeCharacter!),
          // The quest climbing each mountain (v46). Reads the same
          // accessor in both modes — it returns the 1:1 list unchanged
          // when there is no group — so the step shown here and on the
          // group member card are computed identically.
          steps: AmbitionService.activeStepsFrom(
            chat.getObjectivesForGroupCharacter(chat.activeCharacter!),
          ),
        );
      case 'pockets':
        // Pockets & Wardrobe — answers to its own switch, so it sits OUTSIDE
        // the realism branch for the same reason Ambitions does.
        return Builder(
          builder: (context) {
            // v64 (docs/design/pockets-wardrobe-chat-toggle.md): the gate
            // LINE is always up — its switch is how an off chat turns back
            // on, and an off chat says "retained, not tracked" (hide ≠
            // erase, spoken aloud). Feature off = the PANEL absent, never
            // greyed; with it ON the panel renders even for an empty
            // record, so the FIRST item can be added by hand (2026-08-13
            // — the panel used to be ✕-only).
            final card = chat.activeCharacter!;
            final id = chat.characterIdFor(card);
            final live = chat.pocketsEnabledFor(id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PocketsGateLine(
                  chat: chat,
                  characterId: id,
                  characterName: card.name,
                ),
                if (live) ...[
                  const SizedBox(height: 4),
                  // The bars-show-from-the-gate rule (Error Book 2026-10-08):
                  // the panel asks the LIVE gate, not the stored switch.
                  PocketsRow(
                    pockets: chat.pocketsFor(id) ?? Pockets(),
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
                ],
              ],
            );
          },
        );
      case 'time':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
        );
    }
    return const SizedBox.shrink();
  }

  /// The ids reordered by a drag: onReorderItem delivers newIndex already
  /// adjusted for the removal at oldIndex (no manual decrement).
  List<String> _reorderIds(List<String> ids, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return ids;
    final out = List.of(ids);
    final item = out.removeAt(oldIndex);
    out.insert(newIndex, item);
    return out;
  }
}
