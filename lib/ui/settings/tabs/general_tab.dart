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
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_save_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_delete_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/general_tab.dart';

/// Settings → General.
class GeneralTab extends StatelessWidget {
  const GeneralTab({super.key, required this.systemPromptController});

  final TextEditingController systemPromptController;

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);
    final shownPrompt = storageService.presetSettings.savedPrompts
        .where(
          (p) => p['content'] == storageService.generationSettings.systemPrompt,
        )
        .map((p) => p['name'])
        .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('user-messages-on-right'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'My messages on the right',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            subtitle: Text(
              'Off, your messages sit on the left with your picture, like '
              'the character\'s. On, they move to the right with your '
              'picture on the right, the way chat looked before.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
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
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            subtitle: Text(
              'Keep the chat pinned to the newest words while a reply is '
              'writing, as long as you are at the bottom. Scroll up to stop.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
              ),
            ),
            value: storageService.uiSettings.followStreamingReplies,
            onChanged: (v) =>
                storageService.uiSettings.setFollowStreamingReplies(v),
          ),
          const SizedBox(height: 16),
          if (UpdateService.isSupported) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Auto-check for Updates',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<UpdateService>(
                  builder: (context, updateService, _) => Switch(
                    value: updateService.autoCheckEnabled,
                    onChanged: (val) => updateService.setAutoCheckEnabled(val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Consumer<UpdateService>(
              builder: (context, updateService, _) {
                final isBusy = updateService.checking;
                return SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () async {
                            final hasUpdate = await updateService
                                .checkForUpdate();
                            if (!context.mounted) return;
                            if (hasUpdate) {
                              await UpdateDialog.show(context);
                              return;
                            }
                            final error = updateService.checkError;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error == null
                                      ? 'You are up to date.'
                                      : 'Update check failed ($error). '
                                            'Try again later.',
                                ),
                                duration: Duration(
                                  seconds: error == null ? 2 : 4,
                                ),
                              ),
                            );
                          },
                    icon: isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      isBusy
                          ? 'Checking...'
                          : updateService.checkError != null
                          ? 'Check failed, try again'
                          : 'Check for Updates Now',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary(context),
                      side: BorderSide(color: AppColors.textTertiary(context)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          const SpellCheckLanguageRow(),
          const SizedBox(height: 24),
          const SectionHeader('Porch Life'),
          const SizedBox(height: 8),
          // The 18+ master switch. It lives HERE rather than in the Porch Life
          // tab on purpose: it hides that tab's "After Dark" group entirely
          // (the approved sketch: shown only when 18+ themes are enabled), so
          // putting it inside the thing it hides would leave no way back on.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '18+ themes',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            subtitle: Text(
              'Shows the adult features — the After Dark group in Porch Life, '
              'and intimate preferences in the character editor. Off means '
              'they are simply not there. Turning this off never erases what '
              'you already set; it only hides the switches.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
              ),
            ),
            value: storageService.realismSettings.adultThemesEnabled,
            onChanged: (v) =>
                storageService.realismSettings.setAdultThemesEnabled(v),
          ),
          const SizedBox(height: 8),
          const PorchLifePointerCard(),
          const SizedBox(height: 24),
          const SectionHeader('Fallback system prompt'),
          const SizedBox(height: 8),
          Text(
            'Used in one-to-one chats when the character has no system prompt. Groups use their own prompt or a group default.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 8),
          // Prompt library row simplified for smallest (full chips/load/save use the extracted dialogs)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  // Shows the saved prompt whose text is in the box, else
                  // the hint: a preset chip or a hand edit must not leave
                  // the last pick's name on show. The key re-seeds it.
                  key: ValueKey(shownPrompt),
                  initialValue: shownPrompt,
                  isExpanded: true,
                  hint: const Text(
                    'Load saved prompt...',
                    style: TextStyle(fontSize: 13),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.cardOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: storageService.presetSettings.savedPrompts
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['name'],
                          child: Text(
                            p['name']!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (name) {
                    if (name != null) {
                      storageService.presetSettings.loadSavedPrompt(name, (p) {
                        storageService.generationSettings.setSystemPrompt(p);
                      });
                      systemPromptController.text =
                          storageService.generationSettings.systemPrompt;
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Save current prompt',
                icon: Icon(Icons.save, color: AppColors.logWarn),
                onPressed: () => showSavePromptDialog(context, storageService),
              ),
              IconButton(
                tooltip: 'Delete a saved prompt',
                icon: Icon(Icons.delete_outline, color: AppColors.logError),
                onPressed: () =>
                    showDeletePromptDialog(context, storageService),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Built-in preset chips (simplified inline for smallest; full would use PresetChip widget)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              SystemPromptPresetChip(
                label: '📡 API Default',
                prompt: defaultApiSystemPrompt,
                storage: storageService,
                systemPromptController: systemPromptController,
              ),
              SystemPromptPresetChip(
                label: '🖥️ KoboldCPP',
                prompt: defaultKoboldSystemPrompt,
                storage: storageService,
                systemPromptController: systemPromptController,
              ),
              SystemPromptPresetChip(
                label: '👥 Group Chat',
                prompt: defaultGroupSystemPrompt,
                storage: storageService,
                systemPromptController: systemPromptController,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: systemPromptController,
            maxLines: 5,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: 'Fallback system prompt',
              hintText: 'Used when a character has no system prompt...',
              hintStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
              filled: true,
              fillColor: AppColors.cardOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (val) =>
                storageService.generationSettings.setSystemPrompt(val),
          ),
          const SizedBox(height: 24),
          const GlobalPromptAdditions(),
          const SizedBox(height: 24),
          const SectionHeader('About & License'),
          const SizedBox(height: 8),
          const AboutLicenseCard(),
        ],
      ),
    );
  }
}
