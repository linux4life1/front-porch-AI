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

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/story/faithful_mode.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Turn this chat into a story…" (Living Time §4). Small config dialog —
/// mode, length, POV — that builds the pre-configured project via the shared
/// buildChatStoryProject and hands off to the existing Story dashboard,
/// whose auto-run already goes distiller → architect. Not a wizard by
/// design: the dashboard IS the flow. 1:1 chats only (the menu hides it in
/// groups — multi-protagonist novelization is a future effort).
class ChatToStoryDialog extends StatefulWidget {
  final ChatService chatService;

  const ChatToStoryDialog({super.key, required this.chatService});

  static Future<void> show(
    BuildContext context, {
    required ChatService chatService,
  }) => showDialog(
    context: context,
    builder: (_) => ChatToStoryDialog(chatService: chatService),
  );

  @override
  State<ChatToStoryDialog> createState() => _ChatToStoryDialogState();
}

class _ChatToStoryDialogState extends State<ChatToStoryDialog> {
  bool _faithful = true;
  String _length = 'Novella';
  String _pov = 'Third Person Limited';
  bool _creating = false;

  Future<void> _create() async {
    final chat = widget.chatService;
    final character = chat.activeCharacter;
    final sessionId = chat.currentSessionId;
    if (character == null || sessionId == null) return;
    setState(() => _creating = true);

    final repo = Provider.of<StoryRepository>(context, listen: false);
    final userName = Provider.of<UserPersonaService>(
      context,
      listen: false,
    ).persona.name;
    final project = buildChatStoryProject(
      sessionId: sessionId,
      character: character,
      characterId: character.dbId ?? character.name,
      userName: userName,
      recap: chat.summary,
      faithful: _faithful,
      length: _length,
      pov: _pov,
    );
    await repo.saveProject(project);
    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryDashboardPage(
          projectId: project.dbId!,
          autoRunStoryArchitect: true,
        ),
      ),
    );
  }

  Widget _choiceRow<T>({
    required String label,
    required List<T> options,
    required T value,
    required String Function(T) name,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(name(o), style: const TextStyle(fontSize: 11)),
                    selected: o == value,
                    selectedColor: AppColors.formMasterAccent.withValues(
                      alpha: 0.25,
                    ),
                    onSelected: (_) => onChanged(o),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Text('📖', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            'Turn this chat into a story',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary(context),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _choiceRow<bool>(
              label: 'Mode',
              options: const [true, false],
              value: _faithful,
              name: (f) => f ? 'Faithful retelling' : 'Inspired by',
              onChanged: (v) => setState(() => _faithful = v),
            ),
            _choiceRow<String>(
              label: 'Length',
              options: const ['Short story', 'Novella'],
              value: _length,
              name: (s) => s,
              onChanged: (v) => setState(() => _length = v),
            ),
            _choiceRow<String>(
              label: 'POV',
              options: const [
                'First Person',
                'Third Person Limited',
                'Third Person Omniscient',
              ],
              value: _pov,
              name: (s) => s.replaceAll('Third Person', '3rd'),
              onChanged: (v) => setState(() => _pov = v),
            ),
            const SizedBox(height: 4),
            Text(
              'Creates a pre-configured Porch Stories project scoped to this '
              'chat and opens the Story dashboard — the pipeline distills '
              'your chat, drafts scene by scene, and can export an eBook '
              'when you\'re happy.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: AppColors.onChaosAccent,
          ),
          onPressed: _creating ? null : _create,
          child: _creating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create story project'),
        ),
      ],
    );
  }
}
