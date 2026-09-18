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
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_save_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_delete_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';

/// Settings → General.
class GeneralTab extends StatelessWidget {
  const GeneralTab({super.key, required this.systemPromptController});

  final TextEditingController systemPromptController;

  /// Curated chat-suitable Google Fonts. ('' == app default, Inter.)
  static const List<(String, String)> _chatFonts = [
    ('Default (Inter)', ''),
    ('Roboto', 'Roboto'),
    ('Open Sans', 'Open Sans'),
    ('Lato', 'Lato'),
    ('Source Sans 3', 'Source Sans 3'),
    ('Nunito', 'Nunito'),
    ('Poppins', 'Poppins'),
    ('Montserrat', 'Montserrat'),
    ('Raleway', 'Raleway'),
    ('Work Sans', 'Work Sans'),
    ('DM Sans', 'DM Sans'),
    ('Quicksand', 'Quicksand'),
    ('Rubik', 'Rubik'),
    ('Karla', 'Karla'),
    ('Merriweather', 'Merriweather'),
    ('Playfair Display', 'Playfair Display'),
    ('Roboto Mono', 'Roboto Mono'),
    ('Fira Code', 'Fira Code'),
  ];

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

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dark Mode', style: theme.textTheme.titleMedium),
              Switch(
                value: Provider.of<StorageService>(context).uiSettings.isDark,
                onChanged: (v) {
                  Provider.of<StorageService>(
                    context,
                    listen: false,
                  ).uiSettings.setIsDark(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (UpdateService.isSupported) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Auto-check for Updates',
                  style: theme.textTheme.titleMedium,
                ),
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
                            if (hasUpdate && context.mounted) {
                              await UpdateDialog.show(context);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('You are up to date.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                    icon: isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      isBusy ? 'Checking...' : 'Check for Updates Now',
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
          SliderSetting(
            label: 'Reading Size',
            value: storageService.uiSettings.textScale,
            min: 0.7,
            max: 2.0,
            onChanged: (val) => storageService.uiSettings.setTextScale(val),
            divisions: 13,
          ),
          const SizedBox(height: 16),
          const SpellCheckLanguageRow(),
          const SizedBox(height: 24),
          const SectionHeader('Chat Appearance'),
          const SizedBox(height: 8),
          ColorRow(
            label: 'User Bubble',
            color: storageService.uiSettings.globalUserBubbleColor,
            onPressed: () => showColorPicker(
              context,
              storageService.uiSettings.globalUserBubbleColor,
              (color) =>
                  storageService.uiSettings.setGlobalUserBubbleColor(color),
            ),
          ),
          ColorRow(
            label: 'User Text',
            color: storageService.uiSettings.globalUserTextColor,
            onPressed: () => showColorPicker(
              context,
              storageService.uiSettings.globalUserTextColor,
              (color) =>
                  storageService.uiSettings.setGlobalUserTextColor(color),
            ),
          ),
          ColorRow(
            label: 'AI Bubble',
            color: storageService.uiSettings.globalAiBubbleColor,
            onPressed: () => showColorPicker(
              context,
              storageService.uiSettings.globalAiBubbleColor,
              (color) =>
                  storageService.uiSettings.setGlobalAiBubbleColor(color),
            ),
          ),
          ColorRow(
            label: 'AI Text',
            color: storageService.uiSettings.globalAiTextColor,
            onPressed: () => showColorPicker(
              context,
              storageService.uiSettings.globalAiTextColor,
              (color) => storageService.uiSettings.setGlobalAiTextColor(color),
            ),
          ),
          ColorRow(
            label: 'Dialogue (Quoted)',
            color: storageService.uiSettings.globalDialogueColor,
            onPressed: () => showColorPicker(
              context,
              storageService.uiSettings.globalDialogueColor,
              (color) =>
                  storageService.uiSettings.setGlobalDialogueColor(color),
            ),
          ),
          ColorRow(
            label: 'Actions (*text*)',
            color: storageService.uiSettings.globalActionColor,
            onPressed: () => showColorPicker(
              context,
              storageService.uiSettings.globalActionColor,
              (color) => storageService.uiSettings.setGlobalActionColor(color),
            ),
          ),
          const SizedBox(height: 12),
          // Global chat font — per-character overrides still win at render time
          // (UiSettings.getChatFontFamily). Restored after a refactor left only
          // a placeholder here; the setter had no other UI caller.
          Row(
            children: [
              Text(
                'Chat Font',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: DropdownButton<String>(
                  // Clamp to a known item — a stored family not in the list
                  // (older build / manual pref edit) would otherwise assert.
                  value:
                      _chatFonts.any(
                        (f) =>
                            f.$2 ==
                            storageService.uiSettings.globalChatFontFamily,
                      )
                      ? storageService.uiSettings.globalChatFontFamily
                      : '',
                  isExpanded: true,
                  dropdownColor: AppColors.cardOf(context),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                  underline: const SizedBox.shrink(),
                  items: _chatFonts.map((font) {
                    return DropdownMenuItem<String>(
                      value: font.$2,
                      child: Text(
                        font.$1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: font.$2.isEmpty ? null : font.$2,
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => storageService.uiSettings
                      .setGlobalChatFontFamily(value ?? ''),
                ),
              ),
            ],
          ),
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
          _buildPorchLifePointer(context),
          const SizedBox(height: 24),
          const SectionHeader('Model Instructions'),
          const SizedBox(height: 8),
          // Prompt library row simplified for smallest (full chips/load/save use the extracted dialogs)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: null,
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
              _presetChip(
                '📡 API Default',
                defaultApiSystemPrompt,
                storageService,
              ),
              _presetChip(
                '🖥️ KoboldCPP',
                defaultKoboldSystemPrompt,
                storageService,
              ),
              _presetChip(
                '👥 Group Chat',
                defaultGroupSystemPrompt,
                storageService,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: systemPromptController,
            maxLines: 5,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'System Prompt...',
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

          const SectionHeader('About & License'),
          _buildAboutSection(context),
        ],
      ),
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
