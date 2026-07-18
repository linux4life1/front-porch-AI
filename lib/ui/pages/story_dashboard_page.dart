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
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/models/story_project.dart';
import 'dart:io';
import 'package:front_porch_ai/ui/pages/story_structure_page.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/services/epub_generator_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/ai_engine_status_card.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// Dashboard page — story bible overview: concept, themes, cast, threads, lore.
class StoryDashboardPage extends StatefulWidget {
  final String projectId;
  final bool autoRunStoryArchitect;

  const StoryDashboardPage({
    super.key,
    required this.projectId,
    this.autoRunStoryArchitect = false,
  });

  @override
  State<StoryDashboardPage> createState() => _StoryDashboardPageState();
}

class _StoryDashboardPageState extends State<StoryDashboardPage> {
  bool _hasAutoRun = false;
  bool _showChatPreview = false;
  List<String> _chatPreviewMessages = [];
  bool _loadingChatPreview = false;

  // Editable act controllers
  final Map<int, TextEditingController> _actTitleControllers = {};
  final Map<int, TextEditingController> _actDescControllers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoRunStoryArchitect && !_hasAutoRun) {
      _hasAutoRun = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runStoryArchitect());
    }
  }

  @override
  void dispose() {
    for (final c in _actTitleControllers.values) {
      c.dispose();
    }
    for (final c in _actDescControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  StoryProject? get _project => Provider.of<StoryRepository>(
    context,
    listen: false,
  ).getById(widget.projectId);

  Future<void> _runStoryArchitect() async {
    final pipeline = Provider.of<StoryPipelineService>(context, listen: false);
    final project = _project;
    if (project == null) return;

    try {
      // Run Chat Distiller first if chat history is enabled
      if (project.useChatHistory &&
          project.chatHistoryCharacterIds.isNotEmpty &&
          project.distilledTimeline.isEmpty) {
        await pipeline.runChatDistiller(project);
      }
      await pipeline.runStoryArchitect(project);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _runActStructurer() async {
    final pipeline = Provider.of<StoryPipelineService>(context, listen: false);
    final project = _project;
    if (project == null) return;

    try {
      await pipeline.runActStructurer(project);
      if (mounted) {
        // Reset act controllers to pick up new data
        _actTitleControllers.clear();
        _actDescControllers.clear();
        setState(() {});
      }
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _loadChatPreview(StoryProject project) async {
    if (_loadingChatPreview) return;
    setState(() => _loadingChatPreview = true);

    try {
      final pipeline = Provider.of<StoryPipelineService>(
        context,
        listen: false,
      );
      final messages = await pipeline.getChatPreviewMessages(project);

      if (mounted) {
        setState(() {
          _chatPreviewMessages = messages;
          _loadingChatPreview = false;
          _showChatPreview = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingChatPreview = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading chat preview: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
          ),
        );
      }
    }
  }

  /// Save edited act fields back to the project.
  Future<void> _saveActEdits(StoryProject project) async {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    for (int i = 0; i < project.acts.length; i++) {
      if (_actTitleControllers.containsKey(i)) {
        project.acts[i] = StoryAct(
          number: project.acts[i].number,
          title: _actTitleControllers[i]!.text,
          description: _actDescControllers[i]!.text,
          focusThreadIds: project.acts[i].focusThreadIds,
          knots: project.acts[i].knots,
        );
      }
    }
    await repo.saveProject(project);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Act edits saved!'),
          backgroundColor: AppColors.surfaceContainerOf(context),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _startAudiobookGeneration(
    StoryProject project,
    AudiobookGeneratorService service,
  ) async {
    try {
      final audiobook = await service.generateAudiobook(project);
      if (audiobook != null && mounted) {
        // Save file dialog
        final String? outputFile = await PickerPrefs.saveFile(
          category: PickerPrefs.catExport,
          dialogTitle: 'Save Audiobook',
          fileName: 'audiobook_${project.title.replaceAll(' ', '_')}.wav',
          type: FileType.custom,
          allowedExtensions: ['wav'],
        );
        if (outputFile != null) {
          await audiobook.file.copy(outputFile);
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

  Future<void> _exportEpub(StoryProject project) async {
    try {
      final epub = await EpubGeneratorService.generateEpub(project);
      if (epub != null && mounted) {
        final String? outputFile = await PickerPrefs.saveFile(
          category: PickerPrefs.catExport,
          dialogTitle: 'Save eBook',
          fileName: '${project.title.replaceAll(' ', '_')}.epub',
          type: FileType.custom,
          allowedExtensions: ['epub'],
        );
        if (outputFile != null) {
          await File(outputFile).writeAsBytes(epub.bytes);
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

  Widget _buildAudiobookProgress(AudiobookGeneratorService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.porchHoneyOf(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.porchHoneyOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.headphones, color: AppColors.porchHoneyOf(context)),
              const SizedBox(width: 12),
              Text(
                'Compiling Audiobook...',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: service.stop,
                icon: Icon(
                  Icons.stop,
                  color: AppColors.negativeAccentOf(context),
                  size: 16,
                ),
                label: Text(
                  'Abort',
                  style: TextStyle(color: AppColors.negativeAccentOf(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: service.progress,
            backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.porchHoneyOf(context),
            ),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            service.status,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, child) {
        final project = repo.getById(widget.projectId);
        if (project == null) {
          return Scaffold(
            body: Center(
              child: Text(
                'Project not found',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          appBar: AppBar(
            title: Text(project.title),
            backgroundColor: AppColors.surfaceContainerOf(context),
            foregroundColor: AppColors.textPrimary(context),
            elevation: 0,
            actions: [
              if (project.acts.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          StoryReaderPage(projectId: widget.projectId),
                    ),
                  ),
                  icon: Icon(
                    Icons.menu_book,
                    color: AppColors.porchHoneyOf(context),
                  ),
                  label: Text(
                    'Read',
                    style: TextStyle(
                      color: AppColors.porchHoneyOf(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (project.acts.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          StoryStructurePage(projectId: widget.projectId),
                    ),
                  ),
                  icon: Icon(
                    Icons.account_tree,
                    color: AppColors.textSecondary(context),
                  ),
                  label: Text(
                    'Structure',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
            ],
          ),
          body: _buildBody(project, pipeline),
        );
      },
    );
  }

  Widget _buildBody(StoryProject project, StoryPipelineService pipeline) {
    // Show loading state
    if (pipeline.isRunning) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.porchHoneyOf(context),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                pipeline.currentStep,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                pipeline.statusMessage,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (pipeline.tokenCount > 0) ...[
                const SizedBox(height: 16),
                Text(
                  '${pipeline.tokenCount} tokens generated',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Show story bible
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── AI Engine (stories can't generate without it) ──
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: AiEngineStatusCard(),
          ),

          // ── Audiobook Generator ──
          Consumer<AudiobookGeneratorService>(
            builder: (context, abService, _) {
              if (abService.isGenerating) {
                return _buildAudiobookProgress(abService);
              }
              if (project.prose.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.porchHoneyOf(context),
                            foregroundColor: AppColors.resolve(context, AppColors.onChaosAccent, AppColors.userText),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.headphones),
                          label: const Text(
                            'Export Audiobook (.wav)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () =>
                              _startAudiobookGeneration(project, abService),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.frostAccentOf(context),
                            foregroundColor: AppColors.resolve(
                              context,
                              AppColors.onChaosAccent,
                              AppColors.userText,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.book),
                          label: const Text(
                            'Export eBook (.epub)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _exportEpub(project),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox();
            },
          ),

          // ── Chat History Preview ──
          if (project.useChatHistory &&
              project.chatHistoryCharacterIds.isNotEmpty) ...[
            _buildChatHistorySection(project),
            const SizedBox(height: 16),
          ],

          // Concept
          if (project.concept.isNotEmpty) ...[
            _sectionCard(
              'Concept',
              project.concept,
              Icons.lightbulb,
              AppColors.porchHoneyOf(context),
            ),
            const SizedBox(height: 16),
          ],
          // Status Quo & Inciting Incident
          if (project.statusQuo.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _sectionCard(
                    'Status Quo',
                    project.statusQuo,
                    Icons.home,
                    AppColors.frostAccentOf(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _sectionCard(
                    'Inciting Incident',
                    project.incitingIncident,
                    Icons.bolt,
                    AppColors.negativeAccentOf(context),
                  ),
                ),
              ],
            ),
          if (project.statusQuo.isNotEmpty) const SizedBox(height: 16),

          // Themes & Style
          if (project.themes.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _sectionCard(
                    'Themes',
                    project.themes,
                    Icons.psychology,
                    AppColors.fixationAccentOf(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _sectionCard(
                    'Style',
                    '${project.style.genre} • ${project.style.mood}\n${project.style.writingGuide}',
                    Icons.palette,
                    AppColors.journalAccentOf(context),
                  ),
                ),
              ],
            ),
          if (project.themes.isNotEmpty) const SizedBox(height: 16),

          // Cast
          if (project.cast.isNotEmpty) ...[
            _sectionTitle(
              'Cast (${project.cast.length})',
              Icons.people,
              AppColors.porchTerracottaOf(context),
            ),
            const SizedBox(height: 8),
            ...project.cast.map((c) => _castCard(c)),
            const SizedBox(height: 16),
          ],

          // Threads
          if (project.threads.isNotEmpty) ...[
            _sectionTitle(
              'Narrative Threads (${project.threads.length})',
              Icons.timeline,
              AppColors.frostAccentOf(context),
            ),
            const SizedBox(height: 8),
            ...project.threads.map((t) => _threadCard(t)),
            const SizedBox(height: 16),
          ],

          // Lore
          if (project.lore.isNotEmpty) ...[
            _sectionTitle(
              'World Lore (${project.lore.length})',
              Icons.public,
              AppColors.bondHighOf(context),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: project.lore.map((l) => _loreChip(l)).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Acts — Editable
          if (project.acts.isNotEmpty) ...[
            Row(
              children: [
                _sectionTitle(
                  'Act Structure (${project.acts.length})',
                  Icons.account_tree,
                  AppColors.porchAmberOf(context),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _saveActEdits(project),
                  icon: Icon(
                    Icons.save,
                    size: 16,
                    color: AppColors.porchAmberOf(context),
                  ),
                  label: Text(
                    'Save Edits',
                    style: TextStyle(
                      color: AppColors.porchAmberOf(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Edit act titles and descriptions to guide the story, then generate scenes',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            ...project.acts.asMap().entries.map(
              (e) => _editableActCard(e.key, e.value, project),
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (project.concept.isNotEmpty && project.acts.isEmpty)
                ElevatedButton.icon(
                  onPressed: _runActStructurer,
                  icon: const Icon(Icons.account_tree),
                  label: const Text('Generate Act Structure'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchHoneyOf(context),
                    foregroundColor: AppColors.resolve(context, AppColors.onChaosAccent, AppColors.userText),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              if (project.acts.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          StoryStructurePage(projectId: widget.projectId),
                    ),
                  ),
                  icon: const Icon(Icons.view_timeline),
                  label: const Text('View Structure & Write'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchHoneyOf(context),
                    foregroundColor: AppColors.resolve(context, AppColors.onChaosAccent, AppColors.userText),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              if (project.concept.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _runStoryArchitect,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate Bible'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  CHAT HISTORY PREVIEW
  // ═══════════════════════════════════════════════════════════════
  bool _showRawMessages = false;

  Widget _buildChatHistorySection(StoryProject project) {
    final hasTimeline = project.distilledTimeline.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _showChatPreview = !_showChatPreview),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 20,
                    color: AppColors.frostAccentOf(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chat History',
                    style: TextStyle(
                      color: AppColors.frostAccentOf(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasTimeline)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bondHighOf(
                          context,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${RegExp(r'\\[EVENT \\d+\\]').allMatches(project.distilledTimeline).length} events distilled',
                        style: TextStyle(
                          color: AppColors.bondHighOf(context),
                          fontSize: 11,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.taskAccentOf(
                          context,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Not distilled yet',
                        style: TextStyle(
                          color: AppColors.taskAccentOf(context),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    _showChatPreview ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.iconSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_showChatPreview) ...[
            Divider(
              color: AppColors.borderOf(context).withValues(alpha: 0.3),
              height: 1,
            ),
            // Tab row: Timeline | Raw Messages | Redistill
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  if (hasTimeline) ...[
                    _tabButton(
                      'Timeline',
                      !_showRawMessages,
                      () => setState(() => _showRawMessages = false),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _tabButton(
                    'Raw Messages',
                    _showRawMessages || !hasTimeline,
                    () {
                      if (_chatPreviewMessages.isEmpty &&
                          !_loadingChatPreview) {
                        _loadChatPreview(project);
                      }
                      setState(() => _showRawMessages = true);
                    },
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final pipeline = Provider.of<StoryPipelineService>(
                        context,
                        listen: false,
                      );
                      project.distilledTimeline = ''; // Force re-distill
                      await pipeline.runChatDistiller(project);
                      if (mounted) setState(() => _showRawMessages = false);
                    },
                    icon: Icon(
                      Icons.refresh,
                      size: 14,
                      color: AppColors.frostAccentOf(context),
                    ),
                    label: Text(
                      hasTimeline ? 'Redistill' : 'Distill Now',
                      style: TextStyle(
                        color: AppColors.frostAccentOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Content
            if (!_showRawMessages && hasTimeline) ...[
              // Distilled timeline view
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SelectableText(
                    project.distilledTimeline,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ] else if (_loadingChatPreview) ...[
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.frostAccentOf(context),
                  ),
                ),
              ),
            ] else if (_chatPreviewMessages.isNotEmpty) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shrinkWrap: true,
                  itemCount: _chatPreviewMessages.length,
                  itemBuilder: (context, index) {
                    final msg = _chatPreviewMessages[index];
                    if (msg.startsWith('---')) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Divider(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                        ),
                      );
                    }
                    final isUser =
                        msg.startsWith('User:') ||
                        msg.startsWith('user:') ||
                        msg.startsWith('{{user}}:');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isUser ? Icons.person : Icons.smart_toy,
                            size: 14,
                            color: isUser
                                ? AppColors.bondHighOf(context)
                                : AppColors.fixationAccentOf(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              msg,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Click "Raw Messages" to load the full chat history.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.frostAccentOf(context).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? AppColors.frostAccentOf(context).withValues(alpha: 0.5)
                : AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? AppColors.frostAccentOf(context)
                : AppColors.textTertiary(context),
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  EDITABLE ACT CARDS
  // ═══════════════════════════════════════════════════════════════

  Widget _editableActCard(int index, StoryAct act, StoryProject project) {
    // Initialize controllers lazily
    if (!_actTitleControllers.containsKey(index)) {
      _actTitleControllers[index] = TextEditingController(text: act.title);
      _actDescControllers[index] = TextEditingController(text: act.description);
    }

    final sceneCount = project.scenes[act.number - 1]?.length ?? 0;

    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: AppColors.porchAmberOf(
            context,
          ).withValues(alpha: 0.2),
          radius: 18,
          child: Text(
            '${act.number}',
            style: TextStyle(
              color: AppColors.porchAmberOf(context),
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          _actTitleControllers[index]?.text ?? act.title,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          (act.description.length > 100
              ? '${act.description.substring(0, 100)}...'
              : act.description),
          style: TextStyle(
            color: AppColors.textSecondary(context).withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ),
        trailing: sceneCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.frostAccentOf(
                    context,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$sceneCount scenes',
                  style: TextStyle(
                    color: AppColors.frostAccentOf(context),
                    fontSize: 11,
                  ),
                ),
              )
            : null,
        iconColor: AppColors.iconSecondary(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Title',
                  style: TextStyle(
                    color: AppColors.porchAmberOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                AppTextField(
                  controller: _actTitleControllers[index],
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Description',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                AppTextField(
                  controller: _actDescControllers[index],
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                  maxLines: 8,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                // Knots preview
                if (act.knots.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Convergence Points',
                    style: TextStyle(
                      color: AppColors.frostAccentOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...act.knots.map(
                    (k) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.merge_type,
                            size: 14,
                            color: AppColors.frostAccentOf(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${k.description} — ${k.interaction}',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  EXISTING WIDGETS (unchanged)
  // ═══════════════════════════════════════════════════════════════

  Widget _sectionTitle(String title, IconData icon, Color color) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _sectionCard(
    String title,
    String content,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _castCard(StoryCastMember c) {
    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          c.name,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          c.role,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.porchTerracottaOf(
            context,
          ).withValues(alpha: 0.25),
          child: Text(
            c.name.isNotEmpty ? c.name[0] : '?',
            style: TextStyle(color: AppColors.porchTerracottaOf(context)),
          ),
        ),
        iconColor: AppColors.iconSecondary(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.description,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
                if (c.voiceSample != null && c.voiceSample!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Voice: "${c.voiceSample}"',
                    style: TextStyle(
                      color: AppColors.textSecondary(
                        context,
                      ).withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                  ),
                ],
                // TTS Voice picker
                const SizedBox(height: 10),
                Consumer<TtsService>(
                  builder: (context, tts, _) {
                    final voices = tts.activeVoices;
                    if (voices.isEmpty) return const SizedBox.shrink();
                    return Row(
                      children: [
                        Icon(
                          Icons.record_voice_over,
                          size: 14,
                          color: AppColors.porchHoneyOf(
                            context,
                          ).withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'TTS Voice:',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: c.voiceModel,
                            hint: Text(
                              'Default narrator',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 12,
                              ),
                            ),
                            dropdownColor: AppColors.surfaceContainerOf(
                              context,
                            ),
                            isExpanded: true,
                            underline: Container(
                              height: 1,
                              color: AppColors.borderOf(
                                context,
                              ).withValues(alpha: 0.5),
                            ),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  'Default narrator',
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              ...voices.map(
                                (v) => DropdownMenuItem<String>(
                                  value: v.id,
                                  child: Text(
                                    v.name,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              c.voiceModel = value;
                              final repo = Provider.of<StoryRepository>(
                                context,
                                listen: false,
                              );
                              final project = _project;
                              if (project != null) repo.saveProject(project);
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ...c.details.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _threadCard(StoryThread t) {
    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.timeline,
          size: 18,
          color: AppColors.frostAccentOf(context),
        ),
        title: Text(
          t.name,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          t.description,
          style: TextStyle(
            color: AppColors.textSecondary(context).withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _loreChip(StoryLoreEntry l) {
    return Tooltip(
      message: l.detail,
      child: Chip(
        label: Text(
          l.topic,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
        backgroundColor: AppColors.cardOf(context),
        side: BorderSide(
          color: AppColors.bondHighOf(context).withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
