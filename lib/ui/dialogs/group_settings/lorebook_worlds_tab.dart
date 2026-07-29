// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/ui/dialogs/import_character_lore_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';

class GroupLorebookWorldsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;

  const GroupLorebookWorldsTab({super.key, required this.chatService, this.groupRepo});

  @override
  State<GroupLorebookWorldsTab> createState() => _GroupLorebookWorldsTabState();
}

class _GroupLorebookWorldsTabState extends State<GroupLorebookWorldsTab> {
  bool _inheritCharacterLorebooks = true;
  List<String> _worldIds = [];
  List<LorebookEntry> _groupLoreEntries = [];

  List<World> _allWorlds = [];

  @override
  void initState() {
    super.initState();
    _loadFromActiveGroup();
    _loadWorlds();
  }

  void _loadFromActiveGroup() {
    final g = widget.chatService.activeGroup;

    if (g == null) {
      _inheritCharacterLorebooks = true;
      _worldIds = [];
      _groupLoreEntries = [];
      return;
    }

    _inheritCharacterLorebooks = g.inheritCharacterLorebooks;
    _worldIds = List<String>.from(g.worldIds);

    _groupLoreEntries = [];
    if (g.groupLorebook.isNotEmpty) {
      try {
        final decoded = jsonDecode(g.groupLorebook);
        if (decoded is Map<String, dynamic>) {
          final lb = Lorebook.fromJson(decoded);
          _groupLoreEntries = List<LorebookEntry>.from(lb.entries);
        }
      } catch (_) {
        // Corrupt or legacy plain-text — start fresh
        _groupLoreEntries = [];
      }
    }
  }

  void _loadWorlds() {
    try {
      final repo = Provider.of<WorldRepository>(context, listen: false);
      // Places only — character lore clones are purged / not shown.
      _allWorlds = List<World>.from(repo.placeWorlds);
    } catch (_) {
      _allWorlds = [];
    }
    setState(() {});
  }

  /// Write the tab's state back onto the LIVE group object after every
  /// mutation. Without this, the dialog-level Save persisted a group this
  /// tab never touched — lorebook/world edits made here were silently lost.
  void _syncToGroup() {
    final g = widget.chatService.activeGroup;
    if (g == null) return;
    g.inheritCharacterLorebooks = _inheritCharacterLorebooks;
    g.worldIds = List<String>.from(_worldIds);
    g.groupLorebook = _groupLoreEntries.isEmpty
        ? ''
        : jsonEncode(Lorebook(entries: _groupLoreEntries).toJson());
  }

  Future<void> _showEntryEditor({LorebookEntry? existing, int? index}) async {
    // The shared Simple/Advanced editor (clone-preserving). The old bespoke
    // 5-field dialog here rebuilt entries from scratch, destroying imported
    // ST metadata (secondary keys, probability, timers, ...) on every edit.
    final result = await showLorebookEntryDialog(
      context: context,
      existing: existing,
      showEnabled: true,
    );
    if (result == null) return;

    setState(() {
      if (index != null && index >= 0 && index < _groupLoreEntries.length) {
        _groupLoreEntries[index] = result;
      } else {
        _groupLoreEntries.add(result);
      }
    });
    _syncToGroup();
  }

  Future<void> _importGroupLorebookJson() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final jsonStr = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(jsonStr);

      final Map<String, dynamic> source = (json['lorebook'] is Map)
          ? json['lorebook'] as Map<String, dynamic>
          : (json['entries'] != null ? json : {});

      final imported = Lorebook.fromJson(source.isNotEmpty ? source : json);

      if (imported.entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No entries found in file.')),
          );
        }
        return;
      }

      setState(() {
        _groupLoreEntries.addAll(imported.entries);
      });
      _syncToGroup();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${imported.entries.length} entries.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import: $e')));
      }
    }
  }

  void _deleteEntry(int index) {
    setState(() {
      _groupLoreEntries.removeAt(index);
    });
    _syncToGroup();
  }

  Future<void> _importGroupLoreFromCharacter() async {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final entries = await showImportCharacterLoreDialog(
      context: context,
      characters: charRepo.characters,
    );
    if (entries == null || entries.isEmpty) return;
    setState(() {
      _groupLoreEntries.addAll(entries);
    });
    _syncToGroup();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${entries.length} entries from character.'),
        ),
      );
    }
  }

  void _toggleWorld(World w) {
    setState(() {
      final byId = _worldIds.contains(w.id);
      final byName = _worldIds.contains(w.name);
      if (byId || byName) {
        _worldIds.remove(w.id);
        _worldIds.remove(w.name);
      } else {
        _worldIds.add(w.id);
      }
    });
    _syncToGroup();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;
    if (group == null) {
      return const Center(child: Text('No active group.'));
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inherit toggle
                SwitchListTile(
                  title: const Text('Inherit character lorebooks'),
                  subtitle: const Text(
                    'When enabled, lorebooks from all group members (and their attached worlds) are included in addition to the group lorebook.',
                  ),
                  value: _inheritCharacterLorebooks,
                  onChanged: (v) {
                    setState(() {
                      _inheritCharacterLorebooks = v;
                    });
                    _syncToGroup();
                  },
                  activeThumbColor: Colors.orangeAccent,
                ),
                const SizedBox(height: 16),

                // Places (Living Worlds)
                GroupSectionHeader(
                  'Places',
                  Icons.public,
                  AppColors.formMasterAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  'Attach places for climate + place lore on this group '
                  '(template for new chats; this session also has Places under Story Tools).',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 8),
                if (_allWorlds.isEmpty)
                  const Text(
                    'No places available. Create places in the Worlds tab to attach them here.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allWorlds.map((w) {
                      final selected = _worldIds.contains(w.id) ||
                          _worldIds.contains(w.name);
                      final label = w.biomeId != null &&
                              w.biomeId!.isNotEmpty &&
                              w.biomeId != 'temperate'
                          ? '${w.name} · ${w.biomeId}'
                          : w.name;
                      return FilterChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: (_) => _toggleWorld(w),
                        selectedColor: AppColors.formMasterAccent.withValues(
                          alpha: 0.3,
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),

                // Group lorebook entries
                GroupSectionHeader(
                  'Group Lorebook',
                  Icons.menu_book,
                  Colors.orangeAccent,
                ),
                const SizedBox(height: 6),
                Text(
                  'Highest priority lore. These entries are always available to the whole group.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _importGroupLorebookJson,
                      icon: const Icon(Icons.upload, size: 16),
                      label: const Text('Import JSON'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _importGroupLoreFromCharacter,
                      icon: const Icon(Icons.person_search, size: 16),
                      label: const Text('From character'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _showEntryEditor(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Entry'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_groupLoreEntries.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'No group-level lorebook entries yet.\nAdd entries or import a JSON file.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  ..._groupLoreEntries.asMap().entries.map((entry) {
                    final i = entry.key;
                    final e = entry.value;
                    final keyPreview = e.key.isEmpty
                        ? '(no trigger keys)'
                        : e.key;
                    final contentPreview = e.content.length > 140
                        ? '${e.content.substring(0, 137)}...'
                        : e.content;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          keyPreview,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            contentPreview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () =>
                                  _showEntryEditor(existing: e, index: i),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteEntry(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
