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
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/pages/import_lorebook_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';
import 'lorebook_panel.dart';

/// The chat-scoped lorebook section: lore that lives and dies with this one
/// conversation. Add/edit/delete reuse the shared entry editor; Import…
/// opens the wizard (whose "This chat only" destination lands here).
class ChatLorebookSection extends StatelessWidget {
  final ChatService chatService;
  const ChatLorebookSection({super.key, required this.chatService});

  Future<void> _addOrEdit(BuildContext context, {int? index}) async {
    final entries = chatService.chatLorebook.entries;
    final result = await showLorebookEntryDialog(
      context: context,
      existing: index != null ? entries[index] : null,
      showEnabled: true,
    );
    if (result == null) return;
    if (index != null) {
      entries[index] = result;
    } else {
      entries.add(result);
    }
    await chatService.commitChatLorebookEdit();
  }

  @override
  Widget build(BuildContext context) {
    final entries = chatService.chatLorebook.entries;
    final honey = AppColors.porchHoneyOf(context);
    final injected = chatService.currentlyActiveLoreEntries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.chat_bubble_outline,
          label: 'This Chat',
          accent: honey,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ImportLorebookPage(),
                  ),
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.download,
                    size: 14,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _addOrEdit(context),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.add, size: 15, color: honey),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: entries.isEmpty
              ? Text(
                  'Lore for this conversation only — nothing here yet.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      LoreEntryRow(
                        entry: entries[i],
                        label: entries[i].displayName,
                        verticalPadding: 3,
                        injected: injected.contains(entries[i]),
                        pill: loreTimerPill(context, chatService, entries[i]),
                        onTap: () => _addOrEdit(context, index: i),
                        trailing: InkWell(
                          onTap: () async {
                            entries.removeAt(i);
                            await chatService.commitChatLorebookEdit();
                          },
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
