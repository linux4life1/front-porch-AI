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

part of 'story_dashboard_page.dart';

/// Pipeline-triggering actions for [_StoryDashboardPageState]: running the
/// Story Architect / Act Structurer, loading the chat preview, saving act
/// edits, and audiobook/ePub export. Extracted verbatim from the inline
/// methods; `setState` calls become `rebuildState` since extensions cannot
/// touch a State's protected members directly.
extension _StoryDashboardActions on _StoryDashboardPageState {
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
      if (mounted) rebuildState(() {});
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
        rebuildState(() {});
      }
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _loadChatPreview(StoryProject project) async {
    if (_loadingChatPreview) return;
    rebuildState(() => _loadingChatPreview = true);

    try {
      final pipeline = Provider.of<StoryPipelineService>(
        context,
        listen: false,
      );
      final messages = await pipeline.getChatPreviewMessages(project);

      if (mounted) {
        rebuildState(() {
          _chatPreviewMessages = messages;
          _loadingChatPreview = false;
          _showChatPreview = true;
        });
      }
    } catch (e) {
      if (mounted) {
        rebuildState(() => _loadingChatPreview = false);
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

  Future<void> _exportEpub(StoryProject project) async {
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
}
