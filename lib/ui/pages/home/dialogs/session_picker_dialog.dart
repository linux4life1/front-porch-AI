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

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The "continue a chat / start new" session picker shown when a character has
/// existing chats. Returns the picked session id, the sentinel `__new__` to
/// start fresh, or null on dismiss. Extracted verbatim from _HomePageState
/// (self-contained — no page state).

Future<String?> showSessionPickerDialog(
  BuildContext context,
  List<Map<String, dynamic>> sessions,
  String characterName,
) {
  return showWarmDialog<String>(
    context,
    title: 'Continue a chat with $characterName?',
    icon: Icons.chat_bubble_outline,
    accent: AppColors.porchHoneyOf(context),
    width: 420,
    content: SizedBox(
      height: 350,
      child: Column(
          children: [
            // New chat button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('__new__'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Start New Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.porchTerracottaOf(context),
                  side: BorderSide(color: AppColors.porchTerracottaOf(context)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(color: AppColors.borderOf(context)),
            const SizedBox(height: 4),
            // Session list
            Expanded(
              child: ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final s = sessions[index];
                  final date = s['date'] as DateTime;
                  final dateStr =
                      '${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")} ${date.hour}:${date.minute.toString().padLeft(2, "0")}';
                  final messageCount = s['message_count'] ?? 0;
                  final userMessageCount = s['user_message_count'] ?? 0;
                  final isBranch = s['parent_session'] != null;
                  final description = s['session_description'] as String?;

                  return Card(
                    color: AppColors.cardOf(context),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: isBranch
                          ? Icon(
                              Icons.call_split,
                              size: 20,
                              color: AppColors.porchHoneyOf(context),
                            )
                          : Icon(
                              Icons.chat,
                              size: 20,
                              color: AppColors.textTertiary(context),
                            ),
                      title: Text(
                        s['preview'],
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                          if (description != null &&
                              description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary(context),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.porchHoneyOf(
                                    context,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppColors.porchHoneyOf(
                                      context,
                                    ).withValues(alpha: 0.3),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.forum,
                                      size: 10,
                                      color: AppColors.porchHoneyOf(context),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$messageCount total',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.porchHoneyOf(context),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (userMessageCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.porchTerracottaOf(
                                      context,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppColors.porchTerracottaOf(
                                        context,
                                      ).withValues(alpha: 0.3),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 10,
                                        color: AppColors.porchTerracottaOf(
                                          context,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$userMessageCount user',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.porchTerracottaOf(
                                            context,
                                          ),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          if (isBranch) ...[
                            const SizedBox(height: 4),
                            Text(
                              '↳ Branched at message #${(s['fork_index'] ?? 0) + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(s['id']),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [warmDialogCancel(context)],
  );
}
