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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank_dialog.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'memory_sources_list.dart';
import 'rag_engine_card.dart';
import 'rag_receipt_view.dart';
import 'memory_off_everywhere_note.dart';
import 'rag_settings_well.dart';

/// Memory (RAG) sidebar panel — enable toggle (with first-run consent flow),
/// embedding engine status, the last reply's retrieval receipt
/// (RagReceiptView — what memory just did), retrieval settings,
/// cross-character source picker, and the Data Bank. The RAG half of the old
/// MemorySection; the Character Growth half lives in GrowthPanel.
///
/// In a group the leaf speaks for the tapped [member]: the sources and Data
/// Bank are theirs (by their library identity), and the switch and the count
/// are the group's own (the gate the embed and retrieval read), where a 1:1's
/// are the global Memory setting.
class MemoryPanel extends StatefulWidget {
  final ChatService chatService;

  /// The focused participant's card (the group member, or the 1:1 host).
  /// Null falls back to the chat's active character.
  final CharacterCard? member;

  /// Journal-receipts tap-to-jump, threaded down from the chat page so a
  /// receipt line can seek the transcript to the message it quoted.
  final ValueChanged<int>? onJumpToMessage;

  /// The reorder grip when this leaf sits in the reorderable accordion body.
  final Widget? dragHandle;

  const MemoryPanel({
    super.key,
    required this.chatService,
    this.member,
    this.onJumpToMessage,
    this.dragHandle,
  });

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  bool _showSettings = false;
  bool _showSources = false;
  Set<String> _selectedSources = {};
  bool _sourcesLoaded = false;

  bool get _inGroup => widget.chatService.activeGroup != null;

  /// Whose memory the leaf shows: the tapped member, else the host.
  CharacterCard? get _owner =>
      widget.member ?? widget.chatService.activeCharacter;

  /// Whether memory runs in this chat: the global Memory setting, and in a
  /// group also the group's own switch (both must be on).
  bool _enabled(StorageService storage) =>
      storage.memorySettings.ragEnabled &&
      (!_inGroup || widget.chatService.groupRagEnabled);

  /// What the switch shows: the group's own choice in a group (kept while the
  /// global setting is off), the global setting in a 1:1.
  bool _switchValue(StorageService storage) => _inGroup
      ? widget.chatService.groupRagEnabled
      : storage.memorySettings.ragEnabled;

  /// A group's switch is unavailable while the global setting is off.
  bool _switchLocked(StorageService storage) =>
      _inGroup && !storage.memorySettings.ragEnabled;

  Future<void> _setEnabled(StorageService storage, bool on) async {
    if (_inGroup) {
      widget.chatService.setGroupRAGEnabled(on);
    } else {
      await storage.memorySettings.setRagEnabled(on);
    }
    if (mounted) setState(() {});
  }

  /// The id this character's Data Bank rows and memory windows carry: their
  /// library identity (a group member is a copy, so not their own avatar id).
  String _memoryId(CharacterCard card) => memoryIdFor(
    card,
    Provider.of<CharacterRepository>(context, listen: false).characters,
    inGroup: _inGroup,
  );

  /// The library row whose memory sources this character reads (a group
  /// member's is the character it was copied from).
  String? _libraryDbId(CharacterCard card) => memoryLibraryDbIdFor(
    card,
    Provider.of<CharacterRepository>(context, listen: false).characters,
    inGroup: _inGroup,
  );

  Set<String> _excludedSourceIds() {
    final owner = _owner;
    if (owner == null) return const {};
    return {_memoryId(owner)};
  }

  @override
  void didUpdateWidget(MemoryPanel old) {
    super.didUpdateWidget(old);
    // Another cast chip was tapped: the sources shown are theirs.
    if (!identical(old.member, widget.member)) {
      _selectedSources = {};
      _sourcesLoaded = false;
      if (_showSources) _loadSources();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If Memory is on but the engine is idle (model missing / not loaded),
    // start setup so the RagEngineCard can show a real progress bar. After
    // the frame: runSetup notifies synchronously, and this runs mid-build.
    final storage = Provider.of<StorageService>(context);
    if (!_enabled(storage)) return;
    final emb = Provider.of<EmbeddingService>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _enabled(storage)) emb.ensureReady();
    });
  }

  /// Load current memorySources from DB
  Future<void> _loadSources() async {
    final owner = _owner;
    final libraryId = owner == null ? null : _libraryDbId(owner);
    if (libraryId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final sources = await repo.getMemorySources(libraryId);
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
    final owner = _owner;
    final libraryId = owner == null ? null : _libraryDbId(owner);
    if (libraryId == null) return;
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      await repo.setMemorySources(libraryId, _selectedSources.toList());
    } catch (e) {
      debugPrint('[RAG:UI] Failed to save memorySources: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = _enabled(storage);
    final accent = AppColors.journalAccentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with enable toggle (first-run consent flow preserved)
        SidebarSubHeader(
          icon: Icons.psychology,
          label: 'Memory (RAG)',
          accent: accent,
          dragHandle: widget.dragHandle,
          trailing: SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                value: _switchValue(storage),
                onChanged: _switchLocked(storage)
                    ? null
                    : (val) async {
                        if (!val) {
                          // Turning OFF — no consent needed
                          await _setEnabled(storage, false);
                          return;
                        }
                        // Turning ON — check if consent was given before
                        final prefs = await SharedPreferences.getInstance();
                        final consented =
                            prefs.getBool('rag_setup_consented') ?? false;
                        if (consented) {
                          // Already consented — just enable
                          await _setEnabled(storage, true);
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
                          await _setEnabled(storage, true);
                          if (context.mounted) {
                            Provider.of<EmbeddingService>(
                              context,
                              listen: false,
                            ).ensureReady();
                          }
                        }
                      },
                // Switches are porch amber app-wide; the sage accent stays
                // on the section chrome.
                activeTrackColor: AppColors.porchAmberOf(context),
              ),
            ),
          ),
        ),

        if (_switchLocked(storage)) const MemoryOffEverywhereNote(),

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
                  final owner = _owner;
                  if (owner == null) return;
                  showDialog(
                    context: context,
                    builder: (_) => DataBankDialog(
                      characterId: _memoryId(owner),
                      characterName: owner.name,
                    ),
                  );
                },
              ),
            ],
          ),

          if (_showSettings) ...[
            const SizedBox(height: 8),
            RagSettingsWell(
              accent: accent,
              groupChat: _inGroup ? widget.chatService : null,
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
                    excludedIds: _excludedSourceIds(),
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
