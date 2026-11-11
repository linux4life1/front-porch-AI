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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/open_section_env.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../mood/mood_look.dart';
import '../widgets/director_panel.dart';
import '../widgets/director_tools.dart';
import 'character_state/character_state.dart';
import 'journal_memory/journal_memory_group.dart';
import 'porch_accordion.dart';
import 'group_dynamics_section.dart';
import 'sidebar_member_card.dart';
import 'sidebar_reorder.dart';
import 'sidebar_tokens.dart';
import 'story_tools/story_tools.dart';
import '../widgets/chat_turn_builder.dart';
import 'one_shot_eval_row.dart';
import 'tool_calling_pill.dart';
import 'wiki_panel.dart';

/// The scrolling body of the warm-porch chat sidebar: the lite-NPC banner
/// plus accordion groups (Author's Note · Character State · Journal ·
/// Objectives · Story Tools). ALL 1:1 / group / lite-NPC branching lives
/// here — replacing the old three-branch ListView in chat_page.
///
/// Composition-only: page-level concerns (chance-time overlay, avatar file
/// resolution) arrive as callbacks; accordion expansion is persisted via
/// StorageService.uiSettings.
///
/// Reorderable: every top-level section is dragged by its grip handle and the
/// order is persisted globally (sidebarOrderFor / setSidebarOrder). The
/// Director panel is built here as the first item rather than passed in, so it
/// reorders like every other section. Accordion leaves reorder inside their own
/// accordion (sidebarLeafOrderFor / setSidebarLeafOrder).
class SidebarBody extends StatefulWidget {
  final ChatService chatService;
  final ChatParticipant focused;
  final VoidCallback onSpinRequested;

  /// Receipts tap-to-jump (journal + growth rings): scroll the chat to this
  /// message position (chat_page owns the scroll controller and the seek).
  final ValueChanged<int> onJumpToMessage;

  final File? Function(String path) resolveCharImage;

  /// Composer draft for the lorebook "would trigger next" preview.
  final ValueListenable<TextEditingValue>? draft;

  /// OPEN_SECTION=edit: ChatPage opens the in-chat Edit Character dialog.
  final VoidCallback? onOpenEditFromEnv;

  const SidebarBody({
    super.key,
    required this.chatService,
    required this.focused,
    required this.onSpinRequested,
    required this.onJumpToMessage,
    required this.resolveCharImage,
    this.draft,
    this.onOpenEditFromEnv,
  });

  @override
  State<SidebarBody> createState() => _SidebarBodyState();
}

class _SidebarBodyState extends State<SidebarBody> {
  /// `--dart-define=OPEN_SECTION=…` applies once per process after ChatPage
  /// is showing. Static so a SidebarBody remount cannot re-fire.
  static bool _openSectionEnvConsumed = false;
  static int _openSectionEnvRetries = 0;
  static const int _openSectionEnvMaxRetries = 8;

  final _characterStateKey = GlobalKey<CharacterStateGroupState>();
  final _journalAccordionKey = GlobalKey<PorchAccordionState>();
  final _objectivesKey = GlobalKey<PorchAccordionState>();
  final _objectivesHeaderKey = GlobalKey();
  final _timeStripKey = GlobalKey();

  /// The wheel pump: while a tab is picked up (in this list or a nested
  /// accordion list), wheel signals scroll this list by hand — a reorderable
  /// list freezes its own scroll for the drag, which leaves mouse users
  /// unable to carry a bottom tab to the top of a long sidebar.
  final _scroll = ScrollController();
  final _dragging = ValueNotifier<bool>(false);

  void _pumpOnSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_dragging.value) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0 || !_scroll.hasClients) return;
    _scroll.position.correctBy(dy);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _dragging.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeApplyOpenSection();
    });
  }

  void _maybeApplyOpenSection() {
    if (_openSectionEnvConsumed || !mounted) return;
    if (!OpenSectionEnv.enabled) {
      _openSectionEnvConsumed = true;
      return;
    }
    final chat = widget.chatService;
    final isGroup = chat.isGroupMode;
    final isLite = widget.focused.isLite;
    final section = OpenSectionEnv.name;

    // Objectives: a first-frame isLite/null-key no-op must retry — UIC
    // prefs can leave Journal expanded and the accordion may not be in
    // the tree until realismEnabled settles. Other sections consume
    // immediately after apply, as before.
    if (section == OpenSectionEnv.objectives) {
      final ready = _objectivesHeaderKey.currentContext != null && !isLite;
      if (!ready && _openSectionEnvRetries < _openSectionEnvMaxRetries) {
        _openSectionEnvRetries++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeApplyOpenSection();
        });
        return;
      }
    }

    _openSectionEnvConsumed = true;
    OpenSectionEnv.apply(
      section: section,
      isGroup: isGroup,
      isLite: isLite,
      collapseCharacterState: () => _characterStateKey.currentState?.collapse(),
      collapseJournal: () => _journalAccordionKey.currentState?.collapse(),
      expandCharacterState: () => _characterStateKey.currentState?.expand(),
      expandJournal: () => _journalAccordionKey.currentState?.expand(),
      expandObjectives: () => _objectivesKey.currentState?.expand(),
      journalKey: _journalAccordionKey,
      objectivesKey: _objectivesHeaderKey,
      timeStripKey: _timeStripKey,
      onOpenEdit: widget.onOpenEditFromEnv,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChatTurnBuilder(
      builder: (context, chat) {
        // Listening: evolution/journal/one-shot toggles live on storage and
        // must repaint the panels (each old section listened individually).
        final storage = Provider.of<StorageService>(context);
        final ui = storage.uiSettings;
        final isGroup = chat.isGroupMode;
        final isLite = widget.focused.isLite;

        final showDirector = isGroup || chat.cast.length > 1;
        final showCharacterState = characterStateAccordionVisible(
          isLite: isLite,
          isGroup: isGroup,
        );
        // In a group the section is the focused member's own goals.
        final showObjectives =
            !isLite &&
            (chat.objectivesActive ||
                OpenSectionEnv.name == OpenSectionEnv.objectives);

        // The ids this chat can show right now; the stored order filters to
        // them and appends any it does not know per the default order.
        final visibleIds = <String>[
          if (showDirector) 'director',
          'one_shot_eval',
          'tool_calling_pill',
          if (isLite) 'lite_banner',
          'author_note',
          'wiki',
          if (showCharacterState) 'character_state',
          'journal_memory',
          if (showObjectives) 'objectives',
          'story_tools',
        ];
        final ordered = ui.sidebarOrderFor(visibleIds);

        return SidebarReorderLock(
          locked: ui.sidebarLayoutLocked,
          child: ReorderScrollPump(
            dragging: _dragging,
            onWheel: _pumpOnSignal,
            child: ReorderableListView.builder(
              scrollController: _scroll,
              padding: const EdgeInsets.all(12),
              buildDefaultDragHandles: false,
              itemCount: ordered.length,
              onReorderStart: (_) => _dragging.value = true,
              onReorderEnd: (_) => _dragging.value = false,
              onReorderItem: (from, to) =>
                  ui.setSidebarOrder(_reorderIds(ordered, from, to)),
              itemBuilder: (context, i) => WheelPump(
                // The item key the reorderable list demands, and the wheel
                // claim inside the item (deeper than the list's own signal
                // handler) so a tab in hand still scrolls.
                key: ValueKey('sidebar-section-${ordered[i]}'),
                pump: ReorderScrollPump.maybeOf(context),
                child: _section(context, chat, ordered[i], i),
              ),
              // The lifted card normally floats in the root Overlay and eats
              // the wheel hit test, so armed listeners below never see a
              // signal mid-drag. Let signals pass through the feedback.
              proxyDecorator: (child, index, animation) => IgnorePointer(
                child: Material(
                  elevation: 4,
                  shadowColor: Colors.transparent,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The section widget for [id], with its reorder grip at [index]. Built by
  /// the item builder so every section carries the grip its own list item
  /// needs (the listener reads that list's state from its context).
  Widget _section(
    BuildContext context,
    ChatService chat,
    String id,
    int index,
  ) {
    final storage = Provider.of<StorageService>(context);
    final ui = storage.uiSettings;
    final isGroup = chat.isGroupMode;
    final isLite = widget.focused.isLite;
    final grip = SidebarReorderHandle(index: index);
    switch (id) {
      case 'director':
        return Consumer<StorageService>(
          builder: (context, storage, _) {
            final delay = storage.ttsSettings.directorDelay;
            chat.directorDelaySec = delay;
            return DirectorPanel(
              directing: chat.observerMode,
              busy: chat.isGenerating || chat.isNarrating,
              delaySeconds: delay,
              onStepOut: () => unawaited(chat.sendMessage('/director')),
              onStepIn: () => unawaited(chat.sendMessage('/director off')),
              onDelayChanged: storage.ttsSettings.setDirectorDelay,
              dragHandle: grip,
              tools: DirectorTools(
                memberNames: [for (final c in chat.groupCharacters) c.name],
                goal: chat.directorGoal,
                whispers: chat.directorWhisperRows,
                turnBudget: storage.ttsSettings.directorTurnBudget,
                turnsLeft: chat.autoChatTurnsLeft,
                busy: chat.isGenerating || chat.isNarrating,
                onCue: (name) => unawaited(chat.sendMessage('/speak $name')),
                onBeat: (note) => unawaited(chat.sendMessage(note)),
                onGoal: (text) => unawaited(chat.setDirectorGoal(text)),
                onClearWhisper: (id) =>
                    unawaited(chat.setDirectorWhisper(id, '')),
                onTurnBudget: (n) =>
                    unawaited(storage.ttsSettings.setDirectorTurnBudget(n)),
              ),
            );
          },
        );
      case 'one_shot_eval':
        return OneShotEvalRow(chat: chat, dragHandle: grip);
      case 'tool_calling_pill':
        return ToolCallingPill(chatService: chat, dragHandle: grip);
      case 'lite_banner':
        return LiteNpcBanner(dragHandle: grip);
      case 'author_note':
        return PorchAccordion(
          id: 'author_note',
          emoji: '📝',
          title: "Author's Note",
          subtitle: chat.authorNote.trim().isEmpty
              ? null
              : 'active · strength ${chat.authorNoteStrength}',
          accent: AppColors.porchAmberOf(context),
          initiallyExpanded: ui.sidebarGroupExpanded(
            'author_note',
            fallback: true,
          ),
          onExpansionChanged: (v) =>
              ui.setSidebarGroupExpanded('author_note', v),
          dragHandle: grip,
          child: AuthorNoteSection(chatService: chat),
        );
      case 'wiki':
        return WikiPanel(
          chatService: chat,
          initiallyExpanded: ui.sidebarGroupExpanded('wiki', fallback: true),
          onExpansionChanged: (v) => ui.setSidebarGroupExpanded('wiki', v),
          dragHandle: grip,
        );
      case 'character_state':
        final member = isGroup ? widget.focused.card : null;
        final dynamicsVisible = GroupDynamicsSection.visibleFor(chat, member);
        final state = CharacterStateGroup(
          key: _characterStateKey,
          chat: chat,
          isGroup: isGroup,
          moodLook: MoodLook.of(storage),
          member: member,
          initiallyExpanded: ui.sidebarGroupExpanded(
            'character_state',
            fallback: true,
          ),
          onExpansionChanged: (v) =>
              ui.setSidebarGroupExpanded('character_state', v),
          dragHandle: grip,
          timeStripKey: _timeStripKey,
        );
        // Group Dynamics rides under Character State: it moves with it, so
        // it always sits directly below, whatever order was saved.
        if (!dynamicsVisible) return state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            state,
            GroupDynamicsSection(
              chat: chat,
              member: member!,
              initiallyExpanded: ui.sidebarGroupExpanded(
                'group_dynamics',
                fallback: true,
              ),
              onExpansionChanged: (v) =>
                  ui.setSidebarGroupExpanded('group_dynamics', v),
            ),
          ],
        );
      case 'journal_memory':
        return JournalMemoryGroup(
          accordionKey: _journalAccordionKey,
          chatService: chat,
          isGroup: isGroup,
          isLite: isLite,
          diaryOwnerId: widget.focused.id,
          diaryOwnerName: widget.focused.name,
          diaryOwnerCard: widget.focused.card,
          onJumpToMessage: widget.onJumpToMessage,
          initiallyExpanded: ui.sidebarGroupExpanded(
            'journal_memory',
            fallback: false,
          ),
          onExpansionChanged: (v) =>
              ui.setSidebarGroupExpanded('journal_memory', v),
          dragHandle: grip,
        );
      case 'objectives':
        return PorchAccordion(
          key: _objectivesKey,
          headerKey: _objectivesHeaderKey,
          id: 'objectives',
          emoji: '🎯',
          title: 'Objectives',
          subtitle: () {
            // A group's loaded goal is the next speaker's, not the focused
            // member's: name the member instead.
            if (isGroup) return widget.focused.name;
            final goal = chat.primaryObjective?.objective.trim() ?? '';
            return goal.isNotEmpty ? goal : 'auto · expand to steer';
          }(),
          accent: AppColors.porchHoneyOf(context),
          initiallyExpanded: ui.sidebarGroupExpanded(
            'objectives',
            fallback: false,
          ),
          onExpansionChanged: (v) =>
              ui.setSidebarGroupExpanded('objectives', v),
          dragHandle: grip,
          child: isGroup
              ? GroupObjectivesPanel(
                  chatService: chat,
                  member: widget.focused.card,
                )
              : ObjectivePanel(chatService: chat),
        );
      case 'story_tools':
        return StoryToolsGroup(
          draft: widget.draft,
          chatService: chat,
          isGroup: isGroup,
          isLite: isLite,
          character: widget.focused.card,
          onSpinRequested: widget.onSpinRequested,
          initiallyExpanded: ui.sidebarGroupExpanded(
            'story_tools',
            fallback: false,
          ),
          onExpansionChanged: (v) =>
              ui.setSidebarGroupExpanded('story_tools', v),
          dragHandle: grip,
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
