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

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/epub_generator_service.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'story_home_view.cards.dart';

/// The "Porch Stories" home view — shows all story projects with create/delete.
class StoryHomeView extends StatefulWidget {
  const StoryHomeView({super.key});

  @override
  State<StoryHomeView> createState() => _StoryHomeViewState();
}

class _StoryHomeViewState extends State<StoryHomeView> {
  @override
  Widget build(BuildContext context) {
    return Consumer<StoryRepository>(
      builder: (context, repo, child) {
        if (repo.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (repo.projects.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories,
                  size: 72,
                  color: AppColors.porchHoneyOf(context).withValues(alpha: 0.4),
                ),
                const SizedBox(height: 24),
                Text(
                  'No stories yet',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create your first AI-generated story!',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 24),
                _buildCreateButton(context, repo),
                const SizedBox(height: 20),
                const AiEngineStatusCard(compact: true),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_stories,
                    color: AppColors.porchHoneyOf(context),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Porch Stories',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.porchHoneyOf(
                        context,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.porchHoneyOf(
                          context,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${repo.projects.length}',
                      style: TextStyle(
                        color: AppColors.porchHoneyOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const AiEngineStatusCard(compact: true),
                  const SizedBox(width: 12),
                  _buildCreateButton(context, repo),
                ],
              ),
            ),

            // Audiobook generation progress banner
            Consumer<AudiobookGeneratorService>(
              builder: (context, abService, _) {
                if (!abService.isGenerating) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.porchHoneyOf(
                      context,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.porchHoneyOf(
                        context,
                      ).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: AppColors.porchHoneyOf(context),
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Generating Audiobook...',
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: abService.stop,
                            child: Text(
                              'Abort',
                              style: TextStyle(
                                color: AppColors.negativeAccentOf(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: abService.progress,
                        backgroundColor: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.porchHoneyOf(context),
                        ),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        abService.status,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Project list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: repo.projects.length,
                itemBuilder: (context, index) {
                  final project = repo.projects[index];
                  return _buildProjectCard(context, project, repo);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreateButton(BuildContext context, StoryRepository repo) {
    return ElevatedButton.icon(
      onPressed: () async {
        final project = await repo.createProject();
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StorySetupPage(projectId: project.dbId!),
            ),
          );
        }
      },
      icon: const Icon(Icons.add),
      label: const Text('New Story'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.porchHoneyOf(context),
        foregroundColor: AppColors.resolve(
          context,
          AppColors.onChaosAccent,
          AppColors.userText,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}
