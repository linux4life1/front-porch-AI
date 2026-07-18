// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// World-lore ingestion: a comma-separated URL field plus attach/remove of
/// local lore files (.txt/.md/.pdf/.json/.csv). Restored from the god file's
/// `_buildLoreInputSection`. Writes directly into [CreatorState] so the engine
/// can pick the URLs and files up at generation time.
class LoreInputSection extends StatelessWidget {
  final CreatorState state;
  final Color accentColor;

  const LoreInputSection({
    super.key,
    required this.state,
    required this.accentColor,
  });

  Future<void> _attach() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'pdf', 'json', 'csv'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final newFile in result.files) {
      if (!state.loreFiles.any((f) => f.name == newFile.name)) {
        state.loreFiles.add(newFile);
      }
    }
    state.saveState();
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'World Lore / Wiki URLs (optional)',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Paste one or more wiki/lore URLs separated by commas. You can also attach local files below.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: state.loreUrlsController,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
          maxLines: 4,
          minLines: 2,
          onChanged: (_) => state.saveState(),
          decoration: InputDecoration(
            hintText:
                'https://wowpedia.fandom.com/wiki/Demon_hunter, https://wowpedia.fandom.com/wiki/Illidan_Stormrage',
            hintStyle: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (state.loreFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: state.loreFiles
                  .map(
                    (f) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.description, size: 14, color: accentColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              state.loreFiles.remove(f);
                              state.saveState();
                              state.notify();
                            },
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _attach,
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Attach Lore File (.txt, .md, .pdf)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary(context),
            side: BorderSide(color: AppColors.textTertiary(context)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
