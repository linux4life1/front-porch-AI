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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/story_setup/chat_source_picker.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_setup/world_picker_sheet.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Step 1 of 4 (sketch I): title, the idea, sparks, "start from a chat",
/// and "where does it happen?" (docs/design/stories-in-worlds.md §5).
class IdeaStep extends StatefulWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const IdeaStep({super.key, required this.draft, required this.onChanged});

  @override
  State<IdeaStep> createState() => _IdeaStepState();
}

class _IdeaStepState extends State<IdeaStep> {
  List<Map<String, String>> _sparks = StoryPipelineService.generateArchetypes(
    count: 4,
  );

  StorySetupDraft get draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    final chat = draft.chatSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryCard(
          children: [
            SetupField(
              label: 'Title',
              child: StoryField(
                key: const ValueKey('story-title'),
                controller: draft.titleController,
                hint: 'Leave blank and the bible will suggest one',
                onChanged: (_) => widget.onChanged(),
              ),
            ),
            SetupField(
              label: 'What is the story?',
              child: StoryTextArea(
                key: const ValueKey('story-concept'),
                controller: draft.conceptController,
                minLines: 4,
                hint:
                    'A courier on a drowned coast owes a smuggler forty '
                    'silver by the spring caravan…',
                onChanged: (_) => widget.onChanged(),
              ),
            ),
            Row(
              children: [
                const Expanded(child: StoryKeyLabel('Need a spark?')),
                StoryButton.ghost(
                  'New ideas',
                  icon: Icons.refresh,
                  onPressed: () => setState(
                    () => _sparks = StoryPipelineService.generateArchetypes(
                      count: 4,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in _sparks)
                  StoryChip(
                    s['spark'] ?? s['label'] ?? '',
                    onTap: () => _useSpark(s['value'] ?? ''),
                  ),
              ],
            ),
            const SetupNote(
              'Tapping a spark fills an empty box. If you\'ve written '
              'something, it asks before replacing it.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        StoryCard(
          children: [
            Row(
              children: [
                const Expanded(child: StoryKeyLabel('Or start from a chat')),
                if (chat == null)
                  StoryButton(
                    'Choose a chat…',
                    key: const ValueKey('story-choose-chat'),
                    onPressed: _chooseChat,
                  )
                else
                  StoryButton.ghost(
                    'Remove',
                    onPressed: () {
                      draft.dropChat();
                      widget.onChanged();
                    },
                  ),
              ],
            ),
            if (chat != null) ...[
              Row(
                children: [
                  StoryAvatar(chat.characterName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.characterName,
                          style: StudioType.ui(
                            context,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          chat.messageCount > 0
                              ? '${chat.messageCount} messages'
                              : 'this chat',
                          style: StudioType.ui(
                            context,
                            size: 12,
                            color: StudioColors.mutedOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  StorySegmented(
                    options: const {
                      'faithful': 'Faithful retelling',
                      'inspired': 'Inspired by',
                    },
                    selected: chat.faithful ? 'faithful' : 'inspired',
                    onSelect: (v) {
                      chat.faithful = v == 'faithful';
                      widget.onChanged();
                    },
                  ),
                ],
              ),
              SetupNote(
                'Faithful keeps what happened in the chat as canon for every '
                'stage. Inspired by uses it as a starting point only. '
                '${chat.characterName} joins the cast on the next step.',
              ),
            ] else
              const SetupNote(
                'The chat becomes canon: its events are distilled into a '
                'timeline the bible must respect, and its character joins '
                'the cast.',
              ),
          ],
        ),
        const SizedBox(height: 12),
        _worldCard(context),
      ],
    );
  }

  Widget _worldCard(BuildContext context) {
    final world = draft.world;
    return StoryCard(
      key: const ValueKey('story-world-card'),
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Where does it happen?')),
            if (world == null)
              StoryButton(
                'Choose a world…',
                key: const ValueKey('story-choose-world'),
                onPressed: _chooseWorld,
              )
            else
              StoryButton.ghost(
                'Remove',
                key: const ValueKey('story-remove-world'),
                onPressed: () {
                  draft.world = null;
                  widget.onChanged();
                },
              ),
          ],
        ),
        if (world != null)
          Row(
            children: [
              Icon(Icons.public, color: StudioColors.honeyOf(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      world.worldName.isEmpty ? 'A world' : world.worldName,
                      style: StudioType.ui(context, weight: FontWeight.w600),
                    ),
                    if (world.detail.isNotEmpty)
                      Text(
                        world.detail,
                        style: StudioType.ui(
                          context,
                          size: 12,
                          color: StudioColors.mutedOf(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (world.fromChat) ...[
                const StoryChip('from the chat', tone: 'amber'),
                const SizedBox(width: 8),
              ],
              StoryButton(
                'Change…',
                key: const ValueKey('story-change-world'),
                onPressed: _chooseWorld,
              ),
            ],
          ),
        const SetupNote(
          'The world\'s places and lore ground every stage. The story reads '
          'the world; it never changes it.',
        ),
      ],
    );
  }

  Future<void> _chooseWorld() async {
    final worlds = worldsOrNull(context);
    if (worlds == null) return;
    final chosen = await showStoryWorldPicker(
      context,
      places: worlds.placeWorlds,
    );
    if (chosen == null || !mounted) return;
    draft.world = storyWorldPickFor(chosen, worlds);
    widget.onChanged();
  }

  /// A chat with a Setting puts the story there, unless a world was already
  /// picked by hand.
  Future<void> _adoptChatWorld(StoryChatSource source) async {
    if (draft.world != null && !draft.world!.fromChat) return;
    final worlds = worldsOrNull(context);
    if (worlds == null) return;
    final slots = await worlds.getChatWorldAttachments(source.sessionId);
    final id = slots.primaryId;
    if (!mounted ||
        id == null ||
        draft.chatSource?.sessionId != source.sessionId) {
      return;
    }
    final place = worlds.worldById(id);
    if (place == null) return;
    draft.world = storyWorldPickFor(place, worlds, fromChat: true);
    widget.onChanged();
  }

  Future<void> _useSpark(String concept) async {
    if (draft.conceptController.text.trim().isNotEmpty) {
      final ok = await showStoryConfirm(
        context,
        title: 'Replace your idea?',
        body: 'The spark replaces what you\'ve written in the box.',
        confirmLabel: 'Replace',
      );
      if (!ok) return;
    }
    draft.conceptController.text = concept;
    widget.onChanged();
  }

  Future<void> _chooseChat() async {
    final source = await showChatSourcePicker(context);
    if (source == null || !mounted) return;
    draft.adoptChat(source);
    widget.onChanged();
    await _adoptChatWorld(source);
  }
}
