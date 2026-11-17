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
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';
import 'package:front_porch_ai/ui/settings/existing_chats_offer_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'porch_life_pointer_card.dart';

/// Settings → General → Application & System.
///
/// Houses app-level settings: software update checks, spell-check language,
/// and the 18+ themes master switch.
class AppSystemSection extends StatelessWidget {
  const AppSystemSection({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Application & System'),
        const SizedBox(height: 12),
        SettingsGroupCard(
          children: [
            if (UpdateService.isSupported) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Auto-check for Updates',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Consumer<UpdateService>(
                          builder: (context, updateService, _) => Switch(
                            value: updateService.autoCheckEnabled,
                            onChanged: (val) =>
                                updateService.setAutoCheckEnabled(val),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                              side: BorderSide(
                                color: AppColors.textTertiary(context),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SpellCheckLanguageRow(),
            // The 18+ master switch lives here rather than in the Porch Life
            // tab so users can re-enable adult features after disabling them.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '18+ themes',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Shows the adult features — the After Dark group in Porch Life, '
                'and intimate preferences in the character editor. Off means '
                'they are simply not there. Turning this off never erases what '
                'you already set; it only hides the switches.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  height: 1.45,
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
          ],
        ),
        const SizedBox(height: 12),
        const PorchLifePointerCard(),
      ],
    );
  }
}
