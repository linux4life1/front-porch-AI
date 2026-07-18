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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/settings/widgets/color_row.dart';
import 'package:front_porch_ai/ui/settings/widgets/slider_setting.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_save_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_delete_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';

/// General tab extracted from settings_page (Stage 5).
/// Lift of _buildGeneralTab with shared state passed via ctor, AppColors exclusive in the file, use of extracted widgets and dialogs.
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

  /// The global Realism defaults block: master toggle + (when on) the NSFW
  /// cooldown and passage-of-time sub-toggles. Each writes the per-app default
  /// AND applies to the live chat immediately (chatService). The realism/NSFW
  /// defaults are OR-overrides on new chats (force the feature ON for imported
  /// cards with no realism setup — see chat_service_chat_entry seed); passage
  /// of time is a gate (default on, turn off to disable globally). Restored
  /// after a refactor left a placeholder.
  Widget _buildRealismModeSection(
    BuildContext context,
    StorageService storageService,
    ThemeData theme,
  ) {
    final chatService = Provider.of<ChatService>(context, listen: false);

    Widget subToggle({
      required IconData icon,
      required String label,
      required String blurb,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.iconSecondary(context)),
                  const SizedBox(width: 8),
                  Text(label, style: theme.textTheme.bodyLarge),
                ],
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            blurb,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.theater_comedy,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Enable Realism Mode',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              Switch(
                value: storageService.realismDefault,
                onChanged: (val) {
                  storageService.setRealismDefault(val);
                  chatService.setRealismEnabled(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Adds relationship tracking, emotional state, and physical realism '
            'to roleplay.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
          if (storageService.realismDefault) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            subToggle(
              icon: Icons.local_fire_department,
              label: 'NSFW Cooldown',
              blurb:
                  'Tracks arousal level and enforces refractory periods '
                  'after intimate scenes.',
              value: storageService.nsfwCooldownDefault,
              onChanged: (val) {
                storageService.setNsfwCooldownDefault(val);
                chatService.setNsfwCooldownEnabled(val);
              },
            ),
            subToggle(
              icon: Icons.access_time,
              label: 'Automatic Passage of Time',
              blurb:
                  'Time automatically advances '
                  '(dawn→morning→afternoon→evening→night) as you chat.',
              value: storageService.passageOfTimeDefault,
              onChanged: (val) {
                storageService.setPassageOfTimeDefault(val);
                chatService.setPassageOfTimeEnabled(val);
              },
            ),
          ],
        ],
      ),
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
                value: Provider.of<StorageService>(context).isDark,
                onChanged: (v) {
                  Provider.of<StorageService>(
                    context,
                    listen: false,
                  ).setIsDark(v);
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
            label: 'Font Size Scale',
            value: storageService.textScale,
            min: 0.7,
            max: 2.0,
            onChanged: (val) => storageService.setTextScale(val),
            divisions: 13,
          ),
          const SizedBox(height: 24),
          const SectionHeader('Chat Appearance'),
          const SizedBox(height: 8),
          ColorRow(
            label: 'User Bubble',
            color: storageService.globalUserBubbleColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalUserBubbleColor,
              (color) => storageService.setGlobalUserBubbleColor(color),
            ),
          ),
          ColorRow(
            label: 'User Text',
            color: storageService.globalUserTextColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalUserTextColor,
              (color) => storageService.setGlobalUserTextColor(color),
            ),
          ),
          ColorRow(
            label: 'AI Bubble',
            color: storageService.globalAiBubbleColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalAiBubbleColor,
              (color) => storageService.setGlobalAiBubbleColor(color),
            ),
          ),
          ColorRow(
            label: 'AI Text',
            color: storageService.globalAiTextColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalAiTextColor,
              (color) => storageService.setGlobalAiTextColor(color),
            ),
          ),
          ColorRow(
            label: 'Dialogue (Quoted)',
            color: storageService.globalDialogueColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalDialogueColor,
              (color) => storageService.setGlobalDialogueColor(color),
            ),
          ),
          ColorRow(
            label: 'Actions (*text*)',
            color: storageService.globalActionColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalActionColor,
              (color) => storageService.setGlobalActionColor(color),
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
                        (f) => f.$2 == storageService.globalChatFontFamily,
                      )
                      ? storageService.globalChatFontFamily
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
                  onChanged: (value) =>
                      storageService.setGlobalChatFontFamily(value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader('Realism Mode'),
          const SizedBox(height: 8),
          _buildRealismModeSection(context, storageService, theme),
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
                  items: storageService.savedPrompts
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
                      storageService.loadSavedPrompt(name);
                      systemPromptController.text = storageService.systemPrompt;
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
              ActionChip(
                label: const Text('📡 API Default'),
                onPressed: () => storageService.setSystemPrompt(
                  ChatService.defaultApiSystemPrompt,
                ),
              ),
              ActionChip(
                label: const Text('🖥️ KoboldCPP'),
                onPressed: () => storageService.setSystemPrompt(
                  ChatService.defaultKoboldSystemPrompt,
                ),
              ),
              ActionChip(
                label: const Text('👥 Group Chat'),
                onPressed: () => storageService.setSystemPrompt(
                  ChatService.defaultGroupSystemPrompt,
                ),
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
            onChanged: (val) => storageService.setSystemPrompt(val),
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
