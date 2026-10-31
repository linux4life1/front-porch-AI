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
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

class EditCharacterPage extends StatefulWidget {
  final CharacterCard character;

  /// Label for the save action (default "Save"). The Stoop update flow passes
  /// "Next" so this editor reads as the first step of publishing an update.
  final String saveLabel;

  /// When true, a successful save pops this page returning the saved
  /// [CharacterCard] (instead of showing the "updated" snackbar and popping with
  /// no result), so a caller can continue a flow with the freshly-saved card.
  final bool popWithCardOnSave;

  /// When set, save persistence is DELEGATED to this callback instead of writing
  /// to the library (`CharacterRepository.updateCharacter`). Used to edit a group
  /// member: the field updates + PNG save still run on the card, but the row is
  /// written to the group (via the caller) so nothing backflows to the library.
  final Future<void> Function(CharacterCard saved)? onSaveOverride;

  /// The group this card is a member of, when editing a member's own copy:
  /// the page says so, and its Realism section shows only the member's own
  /// settings.
  final String? memberOfGroup;

  /// The member's group, when [memberOfGroup] is set: its own switches as
  /// read-only lines, and where the member starts in its new chats.
  final MemberGroupView? memberGroup;

  /// Allow changing the avatar (default true). Disabled for group members in this
  /// pass, since a member's avatar lives at a private group path.
  final bool allowAvatarChange;

  /// Called after a successful save with the freshly-saved card — a
  /// persistence-agnostic notification (fires on the library path AND the
  /// [onSaveOverride] path, though no current caller passes both). The
  /// in-chat editor (this page in a Dialog, chat_page's "Edit Character")
  /// uses it for ChatService.refreshActiveCharacterCard — the light,
  /// group-safe live refresh that replaced the deleted EditCharacterDialog's
  /// per-control persistence dance.
  final Future<void> Function(CharacterCard saved)? onSaved;

  const EditCharacterPage({
    super.key,
    required this.character,
    this.saveLabel = 'Save',
    this.popWithCardOnSave = false,
    this.onSaveOverride,
    this.memberOfGroup,
    this.memberGroup,
    this.allowAvatarChange = true,
    this.onSaved,
  });

  @override
  State<EditCharacterPage> createState() => _EditCharacterPageState();
}

class _EditCharacterPageState extends State<EditCharacterPage>
    with SingleTickerProviderStateMixin {
  late final EditCharacterDraft _draft;
  late final TabController _tabController;

  /// The member's start as edited; saved to the group's seed when it moved.
  late GroupMemberStart? _start = widget.memberGroup?.start;
  bool get _startMoved => _start != widget.memberGroup?.start;

  @override
  void initState() {
    super.initState();
    _draft = EditCharacterDraft(
      widget.character,
      porchLifeNeedsDefault: _porchLifeNeedsDefault,
      worlds: _worldsOrNull(),
    );
    _tabController = TabController(length: 4, vsync: this);
  }

  WorldRepository? _worldsOrNull() {
    try {
      return Provider.of<WorldRepository>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// A card that says nothing about Needs starts its chats with the Porch
  /// Life Needs switch, so the editor's switch shows that; Save writes a
  /// choice only if the user moves it (see
  /// [EditCharacterDraft.needsSimShownForSilent]). Without the StorageService
  /// above (widget goldens) the switch's own default, on, is the answer.
  bool _porchLifeNeedsDefault() {
    try {
      return Provider.of<StorageService>(
        context,
        listen: false,
      ).realismSettings.needsSimDefault;
    } on ProviderNotFoundException {
      return true;
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  List<LorebookEntry> get _loreEntries => _draft.loreEntries;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addLoreEntry() async {
    final result = await showLorebookEntryDialog(context: context);
    if (result != null) {
      setState(() => _loreEntries.add(result));
    }
  }

  void _removeLoreEntry(int index) {
    setState(() {
      _loreEntries.removeAt(index);
    });
  }

  Future<void> _editLoreEntry(int index) async {
    final entry = _loreEntries[index];
    final result = await showLorebookEntryDialog(
      context: context,
      existing: entry,
      showEnabled: true,
    );
    if (result != null) {
      setState(() => _loreEntries[index] = result);
    }
  }

  Future<void> _importLoreFromCharacter() async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final entries = await showImportCharacterLoreDialog(
      context: context,
      characters: repo.characters,
      excludeCharacterName: widget.character.name,
    );
    if (entries == null || entries.isEmpty) return;
    setState(() {
      _loreEntries.addAll(entries);
    });
    if (mounted) {
      _snack('Added ${entries.length} entries from character.');
    }
  }

  Future<void> _importLorebookJson() async {
    final result = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    try {
      final lorebook = parseLorebookImport(
        await result.files.single.readAsBytes(),
      );

      if (lorebook.entries.isEmpty) {
        if (mounted) _snack('No entries found in file.');
        return;
      }

      setState(() {
        _loreEntries.addAll(lorebook.entries);
      });

      if (mounted) _snack('Imported ${lorebook.entries.length} entries.');
    } on FormatException catch (e) {
      if (mounted) _snack('Invalid file format: ${e.message}');
    } on Exception catch (_) {
      if (mounted) _snack('Import failed. Please try again.');
    }
  }

  /// World-info JSON, the same shape Import file already accepts.
  Future<void> _exportLorebookJson() async {
    if (_loreEntries.isEmpty) {
      if (!mounted) return;
      _snack('No lorebook entries to export.');
      return;
    }

    final selected = await showLorebookExportPicker(
      context: context,
      entries: _loreEntries,
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final name = _draft.nameController.text.trim();
    final bytes = encodeLorebookExport(selected, name);

    try {
      final path = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        dialogTitle: 'Export lorebook',
        fileName: lorebookExportFileName(name),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (path == null || !mounted) return;
      final n = selected.length;
      _snack('Exported $n ${n == 1 ? 'entry' : 'entries'}.');
    } catch (e) {
      if (!mounted) return;
      _snack('Export failed: $e');
    }
  }

  /// A save is running: a second tap of Save before it ends writes nothing
  /// (it would write the row twice and pop the page twice).
  bool _saving = false;

  Future<void> _saveCharacter() async {
    if (_saving) return;
    _saving = true;
    final writer = EditCharacterCardWriter(
      character: widget.character,
      draft: _draft,
    );
    writer.writeFields();
    await writer.embedPng(Provider.of<StorageService>(context, listen: false));
    writer.writeLorebook();

    try {
      if (widget.onSaveOverride != null) {
        // Delegated persistence (e.g. a group member → its group row, never the
        // library). The field updates + PNG save above already ran on the card.
        await widget.onSaveOverride!(widget.character);
      } else {
        await Provider.of<CharacterRepository>(
          context,
          listen: false,
        ).updateCharacter(widget.character);

        // Refresh the "Enjoys low hygiene" flag in any active chat so that
        // toggling it on the character immediately affects existing sessions
        // (without requiring a database change). A moved Needs switch sets
        // how new chats start; chats that exist keep their own.
        ChatService? chatService;
        if (mounted) {
          try {
            chatService = Provider.of<ChatService>(context, listen: false);
          } catch (_) {
            // ChatService not available in this context — that's fine.
          }
        }
        chatService?.refreshEnjoysLowHygieneFromActiveCharacter();

        await _backfillAddedWorlds(writer.addedWorlds);
      }

      final start = _start;
      final saveStart = widget.memberGroup?.saveStart;
      if (_startMoved && start != null && saveStart != null) {
        await saveStart(start);
      }

      if (widget.onSaved != null) {
        await widget.onSaved!(widget.character);
      }

      if (mounted) {
        // Continue mode (e.g. the Stoop update flow): return the saved card so
        // the caller can proceed, instead of the standard "updated" toast + pop.
        if (widget.popWithCardOnSave) {
          Navigator.pop(context, widget.character);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            porchSnackBar(context, 'Character updated successfully!'),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _saving = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating character: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Worlds added in THIS edit back-fill the character's existing chats
  /// that have none. Creation-time seeding only covers chats made after
  /// the character already had a world, so a chat opened first and given
  /// a world later would otherwise keep its temperate default forever
  /// (climate, Setting prose and the Places panel all read the CHAT's
  /// attachments, never the character's list).
  Future<void> _backfillAddedWorlds(
    ({List<String> setting, List<String>? lore}) added,
  ) async {
    final charId = widget.character.dbId;
    if (added.setting.isEmpty && (added.lore?.isEmpty ?? true)) return;
    if (charId == null) return;
    try {
      final worlds = Provider.of<WorldRepository>(context, listen: false);
      final touched = await worlds.applyAddedCharacterWorldsToChats(
        characterId: charId,
        addedRefs: added.setting,
        addedLoreRefs: added.lore,
      );
      if (touched.isNotEmpty && mounted) {
        final chatService = Provider.of<ChatService>(context, listen: false);
        if (touched.contains(chatService.currentSessionId)) {
          await chatService.refreshChatWorlds();
        }
      }
    } catch (_) {
      // Repository/ChatService not in this context — the chat picks the
      // world up on its next open regardless.
    }
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      isDirty: () => _draft.isDirty || _startMoved,
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    final group = widget.memberOfGroup == null ? null : widget.memberGroup;
    final notes = group == null
        ? null
        : memberTabNotes(_draft.nameController.text, group.read());
    return EditCharacterScaffold(
      characterName: widget.character.name,
      saveLabel: widget.saveLabel,
      popWithCardOnSave: widget.popWithCardOnSave,
      onSave: _saveCharacter,
      tabController: _tabController,
      tokenNotifier: _draft.tokenNotifier,
      tabs: [
        EditCharacterDetailsTab(
          character: widget.character,
          draft: _draft,
          memberOfGroup: widget.memberOfGroup,
          memberGroup: group,
          start: _start,
          onStartChanged: (s) => setState(() => _start = s),
          onChanged: _rebuild,
        ),
        EditCharacterDialogueTab(
          draft: _draft,
          onChanged: _rebuild,
          greetingNote: notes?.greeting,
        ),
        EditCharacterLorebookTab(
          memberNote: notes?.lorebook,
          entries: _loreEntries,
          onImportFile: _importLorebookJson,
          onExportFile: _exportLorebookJson,
          onImportFromCharacter: _importLoreFromCharacter,
          onAddEntry: _addLoreEntry,
          onEditEntry: _editLoreEntry,
          onRemoveEntry: _removeLoreEntry,
          onChanged: _rebuild,
        ),
        EditCharacterWorldsTab(
          memberNote: notes?.worlds,
          value: _draft.worldChoice,
          onChanged: (c) => setState(() => _draft.worldChoice = c),
          characterName: _draft.nameController.text,
          legacyWorldCount: characterNeedsWorldSplitNotice(widget.character)
              ? widget.character.worldNames.length
              : 0,
        ),
      ],
    );
  }
}
