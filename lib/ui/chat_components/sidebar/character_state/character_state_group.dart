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
import 'package:front_porch_ai/services/chat/chat.dart' show StoryClock;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../../mood/mood_look.dart';

import '../porch_accordion.dart';
import '../sidebar_reorder.dart';
import 'bond_bars.dart';
import 'bond_reads.dart';
import 'character_state_leaves.dart';
import 'time_strip.dart';

/// 🎭 Character State — the first warm-porch accordion: everything about who
/// the character *is right now* in one card. The 1:1 host shows the unified
/// bond/trust/lust bars (BondBars — the nsfw_section merge), fixation, needs
/// grid, ambitions, pockets and the time strip. In a group the SAME leaves
/// show for the focused member ([member]), each read from that member's own
/// entry rather than the chat's live scalars (which hold whoever spoke last).
///
/// Inside the accordion every portion is its own reorderable leaf — the off
/// note, the bars, the needs, ambitions, pockets and the time strip each
/// carry a grip and move within this accordion (ids and defaults live in
/// `SidebarLayout` under container `character_state`). Gates travel with the
/// leaf: the Needs grid still shows from the live `needsActive` gate, not the
/// stored switch (Error Book 2026-10-08).
///
/// The Realism switch lives in the header and, in a group, drives the focused
/// member for this chat only (docs/design/one-chat-ux.md PR 3); Needs and
/// Afterglow sit on their own lines and Pockets on its line, each the same.
/// There is no settings gear: Needs is set on its line, and One-Shot Eval
/// sits above the tool-calling pill (OneShotEvalRow).
class CharacterStateGroup extends StatefulWidget {
  final ChatService chat;
  final bool isGroup;

  /// The focused group member whose state the leaves show. Null in 1:1 mode,
  /// where the leaves read the chat's active character.
  final CharacterCard? member;

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
    this.member,
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

  /// The focused group member, when there is one and this is a group.
  CharacterCard? get _groupMember => widget.isGroup ? widget.member : null;

  /// Whether Realism runs for what the leaves show: the focused member's own
  /// switch in a group (Director Mode keeps it on), else the chat's.
  bool _realismOn(ChatService chat) {
    if (!widget.isGroup) return chat.realismEnabled;
    final member = _groupMember;
    return member != null &&
        chat.isGroupMode &&
        chat.realismEnabledFor(chat.characterIdFor(member));
  }

  String _subtitle(ChatService chat) {
    final time = TimeStrip.timeLabel(chat.timeService.timeOfDay);
    if (widget.isGroup) {
      final member = _groupMember;
      final on = _realismOn(chat);
      if (!on || member == null || member.isLite) {
        return on ? time : 'Realism off · $time';
      }
      final reads = BondReads.member(chat, member);
      final fixated = chat.getFixationForGroupCharacter(member) != null
          ? ' · 🧠'
          : '';
      return '${reads.shortTerm.tierName} · ${reads.trust.tierName} · '
          '$time$fixated';
    }
    if (!chat.realismEnabled) return 'Realism off';
    final rel = chat.relationshipService;
    final fixated = rel.activeFixation.isNotEmpty ? ' · 🧠' : '';
    return '${rel.shortTermTierName} · ${rel.trustTierName} · $time$fixated';
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final member = _groupMember;
    // A group's Realism runs when the focused member's does; Director Mode
    // keeps it on (the cast's state still shows, held still while the user
    // is off stage).
    final realismOn = _realismOn(chat);
    // A lite guest carries no realism, needs, ambitions or pockets.
    final lite = member?.isLite ?? false;
    // Whose state the leaves read: the focused member, or the 1:1 host.
    final card = widget.isGroup ? member : chat.activeCharacter;
    // The switch shows this chat's own choice. While Porch Life blocks
    // Realism it greys out there; a change made mid-reply lands when the
    // reply settles, and the note says so meanwhile.
    final realismAllowed = realismAllowedOf(context);
    // The focused member's id; '' for the 1:1 host, whose switch is the chat's.
    final memberId = member == null ? '' : chat.characterIdFor(member);
    final realismSwitch = chat.realismSwitchFor(memberId);
    // Mirrors ChatService._clockRunning: Porch Life Passage of Time, live.
    final storage = Provider.of<StorageService>(context);
    final clockRunning = StoryClock.isRunning(
      passageOfTimeEnabled: storage.realismSettings.passageOfTimeDefault,
    );
    // The portion order, remembered per surface-global leaf list; the ids
    // this chat can show right now filter the stored order and any unknown
    // id appends per the default (hidden portions keep their stored slot).
    final ui = storage.uiSettings;
    final fixation = widget.isGroup
        ? (member == null || lite
              ? null
              : chat.getFixationForGroupCharacter(member))
        : (realismOn ? chat.relationshipService.activeFixation : '');
    final visible = <String>[
      if (!realismOn || lite) 'realism_off',
      if (realismOn && !lite) 'bond_bars',
      if (realismOn && !lite && fixation != null && fixation.isNotEmpty)
        'fixation',
      // The NeedsLeaf; its grid has the live needsActive gate inside.
      if (realismOn && !lite) 'needs',
      if (chat.objectivesActive &&
          card != null &&
          !lite &&
          chat.ambitionsFor(card).isNotEmpty)
        'ambitions',
      // The pockets leaf stays up while a character is in the chat —
      // v64: its switch is the ONLY 1:1 way back on (the card editor is
      // the default, not the runtime switch), so an off chat must show
      // the line, like Needs does. The PANEL inside keeps its own gate.
      if (card != null && !lite) 'pockets',
      // One rule in both modes: the member's Realism, or the clock running.
      if (realismOn || clockRunning) 'time',
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
      // A group mounts it for the focused member; a lite guest carries no
      // Realism, so it has no switch to flip.
      trailing: widget.isGroup && (member == null || lite)
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
                          chat.setMemberRealismEnabled(memberId, val);
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
    final member = _groupMember;
    final realismSwitch = chat.realismSwitchFor(
      member == null ? '' : chat.characterIdFor(member),
    );
    final card = widget.isGroup ? member : chat.activeCharacter;
    switch (id) {
      case 'realism_off':
        return Text(
          member?.isLite ?? false
              ? 'Lite NPC — no realism or needs tracking for this guest.'
              : !realismAllowed
              ? "The Realism Engine is off in Porch Life. This chat's "
                    'own choice is kept.'
              : widget.isGroup && !realismSwitch
              // This member's own switch, in the header.
              ? 'The Realism Engine is off for ${member?.name ?? 'this '
                            'character'} in this chat — flip the switch to track '
                    'bond, trust, mood, and scene time for them.'
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
      case 'bond_bars':
        // ── Unified bars (bond / trust / lust) ──
        return BondBars(chat: chat, member: widget.isGroup ? member : null);
      case 'fixation':
        // ── Fixation: its own movable portion (replaces the old always-on
        //     chat_page banner; the accordion subtitle carries a 🧠 marker
        //     when collapsed) ──
        return widget.isGroup
            ? FixationChip(
                topic: chat.getFixationForGroupCharacter(member!) ?? '',
                lifespan: chat.getFixationLifespanForGroupCharacter(member),
                compact: false,
              )
            : FixationChip(
                topic: chat.relationshipService.activeFixation,
                lifespan: chat.relationshipService.fixationLifespan,
                compact: false,
              );
      case 'needs':
        return NeedsLeaf(
          chat: chat,
          member: widget.isGroup ? member : null,
          pulseInTrouble: widget.moodLook.portraitOn,
        );
      case 'ambitions':
        return AmbitionsLeaf(chat: chat, card: card!);
      case 'pockets':
        return PocketsLeaf(chat: chat, card: card!);
      case 'time':
        return TimeLeaf(
          chat: chat,
          member: widget.isGroup ? member : null,
          stripKey: widget.timeStripKey,
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
