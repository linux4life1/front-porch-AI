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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

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

  /// Member mode: this card is a member's own copy in a group. The editor is
  /// the 1:1 editor, plus the notice and "In the group", with Time & Day, the
  /// Worlds tab and Chaos Mode greyed out (docs/design/group-editor.md).
  final GroupMemberMode? member;

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
    this.member,
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

  /// The group's values for the member, as edited here; stored on the group
  /// when moved ([GroupMemberMode.saveValues]).
  late GroupMemberValues? _values = widget.member?.values;
  bool get _valuesMoved =>
      widget.member != null && _values != widget.member!.values;

  /// 1:1 mode: the groups this character is also in (the line at the top).
  List<String> _inGroups = const [];

  @override
  void initState() {
    super.initState();
    _draft = EditCharacterDraft(
      widget.character,
      porchLifeNeedsDefault: _porchLifeNeedsDefault,
      worlds: _worldsOrNull(),
    );
    _tabController = TabController(length: 4, vsync: this);
    if (widget.member == null) unawaited(_loadGroups());
  }

  Future<void> _loadGroups() async {
    final AppDatabase db;
    try {
      db = liveDatabase(context);
    } on ProviderNotFoundException {
      return; // no database above (a golden): no groups to name
    }
    final names = await groupNamesOfCharacter(db, widget.character);
    if (mounted) setState(() => _inGroups = names);
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

  late final _lore = EditorLorebookActions(
    context: () => context,
    mounted: () => mounted,
    entries: () => _loreEntries,
    changed: _rebuild,
    bookName: () => _draft.nameController.text,
    excludeCharacterName: widget.character.name,
  );

  /// A save is running: a second tap of Save before it ends writes nothing
  /// (it would write the row twice and pop the page twice).
  bool _saving = false;

  Future<void> _saveCharacter() async {
    if (_saving) return;
    _saving = true;
    var left = false;
    try {
      final writer = EditCharacterCardWriter(
        character: widget.character,
        draft: _draft,
      );
      writer.writeFields();
      await writer.embedPng(
        Provider.of<StorageService>(context, listen: false),
      );
      writer.writeLorebook();

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

      // The group's own values for the member (system prompt, note, feelings)
      // belong to the group; the card above is the member's copy.
      final values = _values;
      if (_valuesMoved && values != null) {
        await widget.member!.saveValues(values);
      }

      if (widget.onSaved != null) {
        await widget.onSaved!(widget.character);
      }

      if (mounted) {
        left = true;
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
      debugPrint('[EditCharacter] save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating character: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // A save that did not leave the page (it failed) lets Save try again.
      if (!left) _saving = false;
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
      isDirty: () => _draft.isDirty || _valuesMoved,
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    final mode = widget.member;
    return EditCharacterScaffold(
      characterName: widget.character.name,
      saveLabel: widget.saveLabel,
      popWithCardOnSave: widget.popWithCardOnSave,
      onSave: _saveCharacter,
      tabController: _tabController,
      tokenNotifier: _draft.tokenNotifier,
      worldsLockedTooltip: mode == null ? null : kWorldsLockedTooltip,
      tabs: [
        EditCharacterDetailsTab(
          character: widget.character,
          draft: _draft,
          member: mode,
          memberValues: _values,
          onMemberValuesChanged: (v) => setState(() => _values = v),
          inGroups: _inGroups,
          onChanged: _rebuild,
        ),
        EditCharacterDialogueTab(draft: _draft, onChanged: _rebuild),
        EditCharacterLorebookTab(
          entries: _loreEntries,
          onImportFile: _lore.importFile,
          onExportFile: _lore.exportFile,
          onImportFromCharacter: _lore.importFromCharacter,
          onAddEntry: _lore.add,
          onEditEntry: _lore.edit,
          onRemoveEntry: _lore.remove,
          onChanged: _rebuild,
        ),
        EditCharacterWorldsTab(
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
