// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WorldFromWikiPreviewStep extends StatelessWidget {
  const WorldFromWikiPreviewStep({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('world-preview'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preview',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Same shelves as Create World. Save drops it in Worlds.',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: state.nameController,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Name',
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: state.descController,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Description',
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Climate'),
                subtitle: const Text(
                  'Off: no biome json. Atmosphere and gravity stay silent.',
                ),
                value: state.climateEnabled,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: (v) {
                  state.climateEnabled = v;
                  state.notify();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Lorebook (${state.entries.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              if (state.entries.isEmpty)
                Text(
                  'No cards yet. Go back and Write, or save an empty place.',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                )
              else
                for (final e in state.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name.isEmpty ? '(untitled)' : e.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.content,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
