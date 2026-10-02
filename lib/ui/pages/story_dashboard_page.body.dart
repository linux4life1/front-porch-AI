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

/// The main story-bible body composition for [_StoryDashboardPageState]:
/// pipeline-running overlay, audiobook/ePub export row, chat-history section,
/// concept/themes/style cards, cast/threads/lore lists, editable acts, and
/// the action-button row. Extracted verbatim from the inline `_buildBody`;
/// pure composition — no `setState` here, so no `rebuildState` bridge needed.
extension _StoryDashboardBody on _StoryDashboardPageState {
  Widget _buildBody(StoryProject project, StoryPipelineService pipeline) {
    // Show loading state
    if (pipeline.isRunning) return StudioRunningOverlay(pipeline);

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
                    foregroundColor: AppColors.resolve(
                      context,
                      AppColors.onChaosAccent,
                      AppColors.userText,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              if (project.acts.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _openSection(StudioSection.structure),
                  icon: const Icon(Icons.view_timeline),
                  label: const Text('View Structure & Write'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchHoneyOf(context),
                    foregroundColor: AppColors.resolve(
                      context,
                      AppColors.onChaosAccent,
                      AppColors.userText,
                    ),
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
}
