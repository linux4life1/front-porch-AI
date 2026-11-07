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
import 'package:front_porch_ai/ui/settings/existing_chats_offer_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
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
            onChanged: (v) async {
              final was = storageService.realismSettings.afterglowEnabled;
              await storageService.realismSettings.setAdultThemesEnabled(v);
              if (!context.mounted) return;
              await offerAfterglowInExistingChats(context, wasAllowed: was);
            },
          ),
          const SizedBox(height: 8),
          const PorchLifePointerCard(),
          const SizedBox(height: 24),
          PromptSlotCard(
            slot: PromptSlot.oneToOne,
            controller: systemPromptController,
            title: 'Fallback system prompt',
            fieldLabel: 'Fallback system prompt',
            helper:
                'Used in one-to-one chats whose character card has no system '
                'prompt of its own. Group chats use the Group system prompt '
                'further down instead.',
          ),
          const SizedBox(height: 24),
          const GroupSystemPromptField(),
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
