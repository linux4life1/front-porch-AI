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
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'memory_sources_list.dart';
import 'rag_engine_card.dart';
import 'rag_receipt_view.dart';
import 'rag_settings_well.dart';

/// Memory (RAG) sidebar panel — enable toggle (with first-run consent flow),
/// embedding engine status, the last reply's retrieval receipt
/// (RagReceiptView — what memory just did), retrieval settings,
/// cross-character source picker, and the Data Bank. The RAG half of the old
/// MemorySection; the Character Growth half lives in GrowthPanel.
class MemoryPanel extends StatefulWidget {
  final ChatService chatService;

  /// Journal-receipts tap-to-jump, threaded down from the chat page so a
  /// receipt line can seek the transcript to the message it quoted.
  final ValueChanged<int>? onJumpToMessage;

  const MemoryPanel({
    super.key,
    required this.chatService,
    this.onJumpToMessage,
  });

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  bool _showSettings = false;
  bool _showSources = false;
  Set<String> _selectedSources = {};
  bool _sourcesLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If Memory is on but the engine is idle (model missing / not loaded),
    // start setup so the RagEngineCard can show a real progress bar.
    final storage = Provider.of<StorageService>(context);
    if (storage.memorySettings.ragEnabled) {
      Provider.of<EmbeddingService>(context, listen: false).ensureReady();
    }
  }

  /// Load current memorySources from DB
  Future<void> _loadSources() async {
    final activeChar = widget.chatService.activeCharacter;
    if (activeChar == null || activeChar.dbId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final sources = await repo.getMemorySources(activeChar.dbId!);
      // The read crosses the DB isolate, and the panel dies on an accordion
      // collapse or a chat switch — setState on a defunct State throws.
      if (!mounted) return;
      setState(() {
        _selectedSources = sources.toSet();
        _sourcesLoaded = true;
      });
    } catch (e) {
      debugPrint('[RAG:UI] Failed to load memorySources: $e');
      if (!mounted) return;
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
    final enabled = storage.memorySettings.ragEnabled;
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
                    storage.memorySettings.setRagEnabled(false);
                    return;
                  }
                  // Turning ON — check if consent was given before
                  final prefs = await SharedPreferences.getInstance();
                  final consented =
                      prefs.getBool('rag_setup_consented') ?? false;
                  if (consented) {
                    // Already consented — just enable
                    storage.memorySettings.setRagEnabled(true);
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
                    storage.memorySettings.setRagEnabled(true);
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
          // Engine status — progress bar / download / retry (not a dead dot).
          RagEngineCard(accent: accent),
          // What memory just did — the last reply's retrieval receipt.
          RagReceiptView(
            receipt: widget.chatService.lastRagReceipt,
            onJumpToMessage: widget.onJumpToMessage,
            accent: accent,
          ),
          const SizedBox(height: 6),
          // Sidebar width is whatever the user dragged it to — wrap rather
          // than assume the three chips fit on one line (225px overflowed).
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _link(
                icon: Icons.tune,
                label: 'Settings',
                color: _showSettings ? accent : AppColors.textTertiary(context),
                iconColor: _showSettings
                    ? accent
                    : AppColors.iconSecondary(context),
                onTap: () => setState(() => _showSettings = !_showSettings),
              ),
              _link(
                icon: Icons.people,
                label:
                    'Sources${_selectedSources.isNotEmpty ? ' (${_selectedSources.length})' : ''}',
                color: _showSources ? accent : AppColors.textTertiary(context),
                iconColor: _showSources
                    ? accent
                    : AppColors.iconSecondary(context),
                onTap: () {
                  setState(() => _showSources = !_showSources);
                  if (_showSources && !_sourcesLoaded) _loadSources();
                },
              ),
              _link(
                icon: Icons.library_books,
                label: 'Data Bank',
                color: AppColors.textTertiary(context),
                iconColor: AppColors.iconSecondary(context),
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
              ),
            ],
          ),

          if (_showSettings) ...[
            const SizedBox(height: 8),
            RagSettingsWell(accent: accent),
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

  Widget _link({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}
