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

part of 'general_tab.dart';

/// About card, Porch Life pointer, and system-prompt preset chips.
extension _GeneralTabAbout on GeneralTab {
  /// The Realism/feature toggles moved to the Porch Life tab (2026-08-07):
  /// nesting them under the master realism switch meant turning the engine OFF
  /// also HID the switches for features that work without it. This pointer is
  /// all that remains here — see lib/ui/settings/tabs/porch_life_tab.dart.
  Widget _buildPorchLifePointer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cottage_outlined,
            size: 18,
            color: AppColors.porchAmberOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The Realism Engine, passage of time, weather, the Journal, '
              'dreams, promises, ambitions and the welcome-back recap all live '
              'in the Porch Life tab now — each one saying plainly what it '
              'needs.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A built-in system-prompt preset. It MUST move the visible field as well as
  /// storage: the controller belongs to the settings page, so a notify-driven
  /// rebuild never touches its text — writing storage alone left the old prompt
  /// on screen and the next keystroke saved that stale text back over the
  /// preset. (The saved-prompt dropdown above does the same two-step.)
  Widget _presetChip(String label, String prompt, StorageService storage) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        storage.generationSettings.setSystemPrompt(prompt);
        systemPromptController.text = prompt;
      },
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    const repoUrl = 'https://github.com/linux4life1/front-porch-ai';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Front Porch AI v$appVersion',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Free, open-source software © 2026 Front Porch AI, licensed under '
            'the GNU Affero General Public License v3.0. You are free to use, '
            'study, modify, and redistribute it under the AGPL. The complete '
            'source code is available below; if you received this app without '
            'that source, or as part of a closed-source product, that is a '
            'license violation.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                avatar: const Icon(Icons.code, size: 16),
                label: const Text('Source code'),
                onPressed: () => launchUrl(
                  Uri.parse(repoUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.gavel, size: 16),
                label: const Text('Report a license violation'),
                onPressed: () => launchUrl(
                  Uri.parse('$repoUrl/issues'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
