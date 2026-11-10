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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/about_license_card.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/app_system_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/prompts_section.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

/// Settings → General.
///
/// Reorganized into 4 card-contained categories:
/// 1. Application & System (updates, spellcheck, 18+ themes)
/// 2. Chat Behavior & Display (message alignment, follow streaming)
/// 3. Default Prompts & Instructions (1:1 fallback, group, global additions)
/// 4. About & License (app version, AGPL-3.0 notice, repo links)
class GeneralTab extends StatelessWidget {
  const GeneralTab({super.key, required this.systemPromptController});

  final TextEditingController systemPromptController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSystemSection(),
          const SizedBox(height: 28),
          const ChatBehaviorSection(),
          const SizedBox(height: 28),
          PromptsSection(systemPromptController: systemPromptController),
          const SizedBox(height: 28),
          const SectionHeader('About & License'),
          const SizedBox(height: 12),
          const AboutLicenseCard(),
        ],
      ),
    );
  }
}

/// Settings → General → Chat Behavior & Display.
///
/// Houses chat layout preferences (message alignment) and live generation
/// behavior (follow streaming auto-scroll).
class ChatBehaviorSection extends StatelessWidget {
  const ChatBehaviorSection({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Chat Behavior & Display'),
        const SizedBox(height: 12),
        SettingsGroupCard(
          children: [
            SwitchListTile(
              key: const ValueKey('user-messages-on-right'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'My messages on the right',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Off, your messages sit on the left with your picture, like '
                'the character\'s. On, they move to the right with your '
                'picture on the right, the way chat looked before.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  height: 1.45,
                ),
              ),
              value: storageService.realismSettings.userMessagesOnRight,
              onChanged: (v) =>
                  storageService.realismSettings.setUserMessagesOnRight(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Follow streaming replies',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Keep the chat pinned to the newest words while a reply is '
                'writing, as long as you are at the bottom. Scroll up to stop.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  height: 1.45,
                ),
              ),
              value: storageService.uiSettings.followStreamingReplies,
              onChanged: (v) =>
                  storageService.uiSettings.setFollowStreamingReplies(v),
            ),
          ],
        ),
      ],
    );
  }
}
