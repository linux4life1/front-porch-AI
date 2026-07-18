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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank_dialog.dart';
import 'package:front_porch_ai/ui/chat_components/overlays/rag_setup_dialog.dart';
import '../sidebar_tokens.dart';
import 'memory_sources_list.dart';

/// Memory (RAG) sidebar panel — enable toggle (with first-run consent flow),
/// embedding engine status, retrieval settings, cross-character source picker,
/// and the Data Bank. The RAG half of the old MemorySection; the Character
/// Growth half lives in GrowthPanel.
class MemoryPanel extends StatefulWidget {
  final ChatService chatService;
  const MemoryPanel({super.key, required this.chatService});

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  bool _showSettings = false;
  bool _showSources = false;
  Set<String> _selectedSources = {};
  bool _sourcesLoaded = false;
  double? _dragRagRetrievalCount;
  double? _dragRagWindowSize;

  /// Load current memorySources from DB
  Future<void> _loadSources() async {
    final activeChar = widget.chatService.activeCharacter;
    if (activeChar == null || activeChar.dbId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final sources = await repo.getMemorySources(activeChar.dbId!);
      setState(() {
        _selectedSources = sources.toSet();
        _sourcesLoaded = true;
      });
    } catch (_) {
      setState(() => _sourcesLoaded = true);
    }
  }

  /// Save selected sources to DB
  Future<void> _saveSources() async {
    final activeChar = widget.chatService.activeCharacter;
    if (activeChar == null || activeChar.dbId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      await repo.setMemorySources(activeChar.dbId!, _selectedSources.toList());
    } catch (e) {
      debugPrint('[RAG:UI] Failed to save memorySources: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.ragEnabled;
    final accent = AppColors.journalAccentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with enable toggle (first-run consent flow preserved)
        SidebarSubHeader(
          icon: Icons.psychology,
          label: 'Memory (RAG)',
          accent: accent,
          trailing: SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                value: enabled,
                onChanged: (val) async {
                  if (!val) {
                    // Turning OFF — no consent needed
                    storage.setRagEnabled(false);
                    return;
                  }
                  // Turning ON — check if consent was given before
                  final prefs = await SharedPreferences.getInstance();
                  final consented =
                      prefs.getBool('rag_setup_consented') ?? false;
                  if (consented) {
                    // Already consented — just enable
                    storage.setRagEnabled(true);
                    Provider.of<EmbeddingService>(
                      context,
                      listen: false,
                    ).ensureReady();
                    return;
                  }
                  // First time — show consent + setup dialog
                  if (!context.mounted) return;
                  final result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const RagSetupDialog(),
                  );
                  if (result == true) {
                    await prefs.setBool('rag_setup_consented', true);
                    storage.setRagEnabled(true);
                    if (context.mounted) {
                      Provider.of<EmbeddingService>(
                        context,
                        listen: false,
                      ).ensureReady();
                    }
                  }
                },
                activeTrackColor: accent,
              ),
            ),
          ),
        ),

        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Retrieve relevant past messages that have fallen out of context, including from other characters\' conversations.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),

        if (enabled) ...[
          const SizedBox(height: 6),
          // Status indicator
          Builder(
            builder: (context) {
              final embeddings = Provider.of<EmbeddingService>(context);
              final statusColor = embeddings.isAvailable
                  ? AppColors.bondHighOf(context)
                  : AppColors.porchAmberOf(context);
              final statusText = embeddings.isAvailable
                  ? 'Memory engine ready'
                  : embeddings.modelOnDisk
                  ? 'Starting...'
                  : 'Model not downloaded';
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          // Controls row
          Row(
            children: [
              // Settings gear toggle
              InkWell(
                onTap: () => setState(() => _showSettings = !_showSettings),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune,
                        size: 14,
                        color: _showSettings
                            ? accent
                            : AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 10,
                          color: _showSettings
                              ? accent
                              : AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Sources toggle
              InkWell(
                onTap: () {
                  setState(() => _showSources = !_showSources);
                  if (_showSources && !_sourcesLoaded) _loadSources();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people,
                        size: 14,
                        color: _showSources
                            ? accent
                            : AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sources${_selectedSources.isNotEmpty ? ' (${_selectedSources.length})' : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          color: _showSources
                              ? accent
                              : AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Data Bank button
              InkWell(
                onTap: () {
                  final activeChar = widget.chatService.activeCharacter;
                  if (activeChar == null) return;
                  showDialog(
                    context: context,
                    builder: (_) => DataBankDialog(
                      characterId: characterEmbeddingId(activeChar),
                      characterName: activeChar.name,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.library_books,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Data Bank',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Expandable settings
          if (_showSettings) ...[
            const SizedBox(height: 8),
            Container(
              padding: SidebarTokens.wellPadding,
              decoration: BoxDecoration(
                color: AppColors.sunkenSurfaceOf(context),
                borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Memories per turn
                  Row(
                    children: [
                      Text(
                        'Memories per turn',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        (_dragRagRetrievalCount ??
                                        storage.ragRetrievalCount.toDouble())
                                    .round() ==
                                0
                            ? 'All'
                            : '${(_dragRagRetrievalCount ?? storage.ragRetrievalCount.toDouble()).round()}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value:
                          _dragRagRetrievalCount ??
                          storage.ragRetrievalCount.toDouble(),
                      min: 0,
                      max: 50,
                      divisions: 50,
                      activeColor: accent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: (val) =>
                          setState(() => _dragRagRetrievalCount = val),
                      onChangeEnd: (val) {
                        _dragRagRetrievalCount = null;
                        storage.setRagRetrievalCount(val.round());
                      },
                    ),
                  ),
                  // Window size
                  Row(
                    children: [
                      Text(
                        'Window size',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_dragRagWindowSize ?? storage.ragWindowSize.toDouble()).round()}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value:
                          _dragRagWindowSize ??
                          storage.ragWindowSize.toDouble(),
                      min: 3,
                      max: 10,
                      divisions: 7,
                      activeColor: accent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: (val) =>
                          setState(() => _dragRagWindowSize = val),
                      onChangeEnd: (val) {
                        _dragRagWindowSize = null;
                        storage.setRagWindowSize(val.round());
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Uses local nomic-embed-text model — no data leaves your machine.',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Expandable memory sources (cross-character picker)
          if (_showSources) ...[
            const SizedBox(height: 8),
            Container(
              padding: SidebarTokens.wellPadding,
              decoration: BoxDecoration(
                color: AppColors.sunkenSurfaceOf(context),
                borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Include memories from other characters:',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  MemorySourcesList(
                    chatService: widget.chatService,
                    selectedSources: _selectedSources,
                    onToggleSource: (embedId) {
                      setState(() {
                        if (_selectedSources.contains(embedId)) {
                          _selectedSources.remove(embedId);
                        } else {
                          _selectedSources.add(embedId);
                        }
                      });
                      _saveSources();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
