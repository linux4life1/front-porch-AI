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
        foregroundColor: AppColors.resolve(context, AppColors.onChaosAccent, AppColors.userText),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  Widget _buildProjectCard(
    BuildContext context,
    StoryProject project,
    StoryRepository repo,
  ) {
    final hasActs = project.acts.isNotEmpty;
    final totalScenes = project.scenes.values.fold<int>(
      0,
      (sum, s) => sum + s.length,
    );
    final totalProse = project.prose.values
        .where((p) => p.final_ != null)
        .length;

    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (totalProse > 0) {
      statusLabel = '$totalProse beats written';
      statusColor = AppColors.bondHighOf(context);
      statusIcon = Icons.edit_note;
    } else if (totalScenes > 0) {
      statusLabel = '$totalScenes scenes planned';
      statusColor = AppColors.frostAccentOf(context);
      statusIcon = Icons.view_timeline;
    } else if (hasActs) {
      statusLabel = '${project.acts.length} acts structured';
      statusColor = AppColors.fixationAccentOf(context);
      statusIcon = Icons.account_tree;
    } else if (project.concept.isNotEmpty) {
      statusLabel = 'Bible created';
      statusColor = AppColors.taskAccentOf(context);
      statusIcon = Icons.menu_book;
    } else {
      statusLabel = 'New — needs concept';
      statusColor = AppColors.textTertiary(context);
      statusIcon = Icons.lightbulb_outline;
    }

    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => project.concept.isEmpty
                  ? StorySetupPage(projectId: project.dbId!)
                  : StoryDashboardPage(projectId: project.dbId!),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Story icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.porchHoneyOf(
                    context,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_stories,
                  color: AppColors.porchHoneyOf(context),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (project.style.genre.isNotEmpty)
                      Text(
                        '${project.style.genre} • ${project.style.mood}',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Tier badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _tierColor(
                    context,
                    project.promptTier,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _tierLabel(project.promptTier),
                  style: TextStyle(
                    color: _tierColor(context, project.promptTier),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Read Button
              if (hasActs)
                IconButton(
                  icon: Icon(
                    Icons.menu_book,
                    color: AppColors.porchHoneyOf(context),
                    size: 20,
                  ),
                  tooltip: 'Read Story',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoryReaderPage(projectId: project.dbId!),
                    ),
                  ),
                ),
              // Export menu (only for stories with prose)
              if (totalProse > 0)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.download,
                    color: AppColors.iconSecondary(context),
                    size: 20,
                  ),
                  tooltip: 'Export',
                  color: AppColors.surfaceContainerOf(context),
                  onSelected: (value) {
                    if (value == 'audiobook') _startAudiobookExport(project);
                    if (value == 'epub') _startEpubExport(project);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'audiobook',
                      child: Row(
                        children: [
                          Icon(
                            Icons.headphones,
                            color: AppColors.porchHoneyOf(context),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Export Audiobook (.wav)',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'epub',
                      child: Row(
                        children: [
                          Icon(
                            Icons.book,
                            color: AppColors.frostAccentOf(context),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Export eBook (.epub)',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              // Delete
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: AppColors.negativeAccentOf(
                    context,
                  ).withValues(alpha: 0.6),
                  size: 20,
                ),
                tooltip: 'Delete story',
                onPressed: () => _confirmDelete(context, project, repo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startAudiobookExport(StoryProject project) async {
    final service = Provider.of<AudiobookGeneratorService>(
      context,
      listen: false,
    );
    try {
      final audiobook = await service.generateAudiobook(project);
      if (audiobook != null && mounted) {
        final wav = await audiobook.file.readAsBytes();
        final String? outputFile = await PickerPrefs.saveFile(
          category: PickerPrefs.catExport,
          bytes: wav,
          dialogTitle: 'Save Audiobook',
          fileName: 'audiobook_${project.title.replaceAll(' ', '_')}.wav',
          type: FileType.custom,
          allowedExtensions: ['wav'],
        );
        if (outputFile != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Audiobook saved to $outputFile'),
                backgroundColor: AppColors.surfaceContainerOf(context),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audiobook failed: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
          ),
        );
      }
    }
  }

  Future<void> _startEpubExport(StoryProject project) async {
    try {
      final epub = await EpubGeneratorService.generateEpub(project);
      if (epub != null && mounted) {
        final String? outputFile = await PickerPrefs.saveFile(
          category: PickerPrefs.catExport,
          bytes: Uint8List.fromList(epub.bytes),
          dialogTitle: 'Save eBook',
          fileName: '${project.title.replaceAll(' ', '_')}.epub',
          type: FileType.custom,
          allowedExtensions: ['epub'],
        );
        if (outputFile != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('eBook saved to $outputFile'),
                backgroundColor: AppColors.surfaceContainerOf(context),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('eBook export failed: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
          ),
        );
      }
    }
  }

  String _tierLabel(PromptTier tier) {
    switch (tier) {
      case PromptTier.frontier:
        return 'Frontier';
      case PromptTier.largLocal:
        return '70B+';
      case PromptTier.smallLocal:
        return '7-34B';
    }
  }

  Color _tierColor(BuildContext context, PromptTier tier) {
    switch (tier) {
      case PromptTier.frontier:
        return AppColors.frostAccentOf(context);
      case PromptTier.largLocal:
        return AppColors.bondHighOf(context);
      case PromptTier.smallLocal:
        return AppColors.taskAccentOf(context);
    }
  }

  void _confirmDelete(
    BuildContext context,
    StoryProject project,
    StoryRepository repo,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(
          'Delete Story?',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: Text(
          'Delete "${project.title}" and all its content? This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              repo.deleteProject(project.dbId!);
              Navigator.pop(ctx);
            },
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.negativeAccentOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
