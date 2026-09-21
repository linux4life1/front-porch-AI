// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

class WorldFromWikiBookStep extends StatelessWidget {
  const WorldFromWikiBookStep({super.key, required this.state});

  final WorldFromWikiState state;

  Future<void> _attach() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'pdf', 'json', 'csv'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (!state.loreFiles.any((e) => e.name == f.name)) {
        state.loreFiles.add(f);
      }
    }
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final saved = storage.webSearchSettings.savedWikiUrls;
    return Center(
      key: const ValueKey('world-book'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The book',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Name the place, pick a saved wiki, then Scout. Climate stays off '
                'unless you turn it on. They will propose a shelf of cards from '
                'the index — not one card per page.',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: state.nameController,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'World name',
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: state.premiseController,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'One-line premise',
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Wiki',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (saved.isEmpty)
                Text(
                  'Save a Fandom or Tiddly URL in Porch Life first.',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                )
              else
                for (final url in saved)
                  InkWell(
                    onTap: () {
                      state.wikiUrl = url;
                      state.notify();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            state.wikiUrl == url
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: state.wikiUrl == url
                                ? AppColors.porchAmberOf(context)
                                : AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              wikiHostLabel(url),
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              SwitchListTile(
                title: const Text('Lorebooks'),
                subtitle: const Text(
                  'On: they scout a shelf of cards; you sign which ones to write.',
                ),
                value: state.lorebooksOn,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: (v) {
                  state.lorebooksOn = v;
                  state.notify();
                },
              ),
              SwitchListTile(
                title: const Text('Climate'),
                subtitle: const Text(
                  'Off by default. Atmosphere and gravity stay silent.',
                ),
                value: state.climateEnabled,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: (v) {
                  state.climateEnabled = v;
                  state.notify();
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _attach,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(
                  state.loreFiles.isEmpty
                      ? 'Attach lore files (optional)'
                      : '${state.loreFiles.length} file(s) attached',
                ),
              ),
              if (state.scouting) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.porchAmberOf(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.status.isEmpty ? 'Scouting…' : state.status,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: TextStyle(color: AppColors.taskAccentOf(context)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
