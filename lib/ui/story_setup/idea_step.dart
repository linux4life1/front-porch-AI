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
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Step 1 of 4 (sketch I): title, the idea, sparks, and "start from a chat".
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
      ],
    );
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
    if (source == null) return;
    draft.adoptChat(source);
    widget.onChanged();
  }
}
