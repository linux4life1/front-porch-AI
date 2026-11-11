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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show EditCharacterScaffold, EditorLorebookActions, groupMemberModeOf;
import 'package:front_porch_ai/ui/pages/edit_group/edit_group.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

export 'package:front_porch_ai/ui/pages/edit_group/edit_group_lore_worlds_tab.dart'
    show kEditGroupUnreadableLoreNote;

/// The group editor page: the character editor's four tabs (Details,
/// Dialogue, Lorebook, Worlds) over a group, in the sections of
/// docs/design/group-editor.md. It replaces the Group Settings dialog; every
/// setting here is the group's default for new chats.
class EditGroupPage extends StatefulWidget {
  final GroupChat group;

  /// Update-flow mode (e.g. the Stoop group Update): label the primary action
  /// (default 'Save', pass 'Next') and, when [popWithGroupOnSave] is true, pop
  /// returning the saved [GroupChat] instead of showing a toast + plain pop, so
  /// the caller can continue to a publish step. Defaults preserve normal editing.
  final String saveLabel;
  final bool popWithGroupOnSave;

  const EditGroupPage({
    super.key,
    required this.group,
    this.saveLabel = 'Save',
    this.popWithGroupOnSave = false,
  });

  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final EditGroupDraft _draft;
  late final EditorLorebookActions _lore;

  final List<CharacterCard> _members = [];
  bool _membersLoaded = false;
  String? _startFingerprint;
  bool _saving = false;

  // The fork notice filled the editor in.
  bool _forkApplied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _draft = EditGroupDraft(widget.group);
    _lore = EditorLorebookActions(
      context: () => context,
      mounted: () => mounted,
      entries: () => _draft.loreEntries,
      changed: _rebuild,
      bookName: () => _draft.name.text,
    );
  }

  void _rebuild() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_membersLoaded) return;
    _membersLoaded = true;
    final g = widget.group;
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final worlds = Provider.of<WorldRepository>(context, listen: false);
    unawaited(() async {
      final roster = await loadEditGroupRoster(groupRepo, storage, g.id);
      if (!mounted) return;
      setState(() => _members.addAll(roster));
      unawaited(_reloadMembers());
    }());
    // Parse the stored group lorebook (the raw text is kept on failure).
    try {
      final book = parseGroupLorebookJson(g.groupLorebook);
      if (book != null) _draft.loreEntries.addAll(book.entries);
    } catch (e) {
      debugPrint('[EditGroup] group lorebook could not be read: $e');
      _draft.bookUnreadable = true;
    }
    _draft.worldChoice = _draft.worldsAsLoaded = groupWorldChoiceIn(g, worlds);
    _startFingerprint = _draft.fingerprint();
  }

  bool _isDirty() =>
      _startFingerprint != null && _draft.fingerprint() != _startFingerprint;

  @override
  void dispose() {
    _tabController.dispose();
    _draft.dispose();
    super.dispose();
  }

  void _useForkSettings(ForkedGroupSource s) {
    setState(() {
      if (s.realismMissingFrom(widget.group)) {
        final blobs = switchGroupTemplateRealism(
          defaultMemberJson: _draft.defaultMemberJson,
          baselineJson: _draft.baselineJson,
          memberIds: [for (final m in _members) m.dbId ?? m.name],
          memberCards: {
            for (final m in _members)
              (m.dbId ?? m.name): m.frontPorchExtensions,
          },
          realismOn: true,
          needsOn: s.needsOn,
        );
        _draft.defaultMemberJson = blobs.defaultMemberJson;
        _draft.baselineJson = blobs.baselineJson;
      }
      if (s.worldMissingFrom(widget.group)) _draft.worldChoice = s.worlds!;
      _forkApplied = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    var left = false;
    try {
      // An unreadable stored book is never replaced without the user saying so.
      final keepRaw = await keepUnreadableGroupLorebook(
        context,
        bookUnreadable: _draft.bookUnreadable,
        hasEntries: _draft.loreEntries.isNotEmpty,
      );
      if (keepRaw == null) return;
      final loreJson = keepRaw
          ? _draft.originalRawLorebook
          : jsonEncode(Lorebook(entries: List.of(_draft.loreEntries)).toJson());
      final worldFields = groupWorldFieldsToSave(
        storedWorldIds: widget.group.worldIds,
        storedLoreWorldIds: widget.group.loreWorldIds,
        chosen: _draft.worldChoice,
        asLoaded: _draft.worldsAsLoaded,
      );
      final updated = _draft.toGroup(
        widget.group,
        worldFields: worldFields,
        loreJson: loreJson,
      );
      await groupRepo.save(updated);
      if (!mounted) return;
      // Capture before any pop (snackbar attachment + open-chat notice).
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      left = true;
      // Update-flow mode: hand the saved group back to the caller.
      if (widget.popWithGroupOnSave) {
        nav.pop(updated);
        return;
      }
      final open = chatService.activeGroup;
      if (open?.id == updated.id) _carryToOpenGroup(open!, updated);
      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            open?.id == updated.id
                ? 'Group "${updated.name}" updated. Changes apply to new '
                      'chats; the chat you are in keeps its own.'
                : 'Group "${updated.name}" updated.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('EditGroupPage save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to save group changes. Please try again.',
            ),
            backgroundColor: AppColors.logError,
          ),
        );
      }
    } finally {
      if (!left) _saving = false;
    }
  }

  /// The open chat holds its own copy of the group: it takes the saved
  /// defaults so its next New Chat starts from them. Nothing of this chat's
  /// own state (its switches, notes, clock) is touched.
  void _carryToOpenGroup(GroupChat open, GroupChat saved) {
    open
      ..name = saved.name
      ..turnOrder = saved.turnOrder
      ..autoAdvance = saved.autoAdvance
      ..directorMode = saved.directorMode
      ..firstMessage = saved.firstMessage
      ..alternateGreetings = saved.alternateGreetings
      ..greetingSeeds = saved.greetingSeeds
      ..scenario = saved.scenario
      ..systemPrompt = saved.systemPrompt
      ..defaultMemberRealismState = saved.defaultMemberRealismState
      ..baselineRealismState = saved.baselineRealismState
      ..characterSystemPrompts = saved.characterSystemPrompts
      ..characterAuthorNotes = saved.characterAuthorNotes
      ..worldIds = saved.worldIds
      ..loreWorldIds = saved.loreWorldIds
      ..groupLorebook = saved.groupLorebook
      ..inheritCharacterLorebooks = saved.inheritCharacterLorebooks
      ..chaosModeEnabled = saved.chaosModeEnabled
      ..personality = saved.personality
      ..postHistoryInstructions = saved.postHistoryInstructions
      ..mesExample = saved.mesExample
      ..tags = saved.tags
      ..storyStartDate = saved.storyStartDate
      ..storyStartTime = saved.storyStartTime
      ..realismVerificationEnabled = saved.realismVerificationEnabled
      ..realismVerificationStrictness = saved.realismVerificationStrictness
      ..realismVerificationMaxReprocesses =
          saved.realismVerificationMaxReprocesses
      ..needsDirectorAuthority = saved.needsDirectorAuthority;
  }

  Future<void> _editMember(CharacterCard member) async {
    final mid = member.dbId ?? member.name;
    final mode = groupMemberModeOf(
      context,
      group: _draft.toGroup(widget.group, worldFields: null, loreJson: null),
      member: member,
      cast: _members,
      // The values go onto this page and are saved with its Save.
      saveValues: (v) async => setState(() => _draft.takeValues(mid, v)),
    );
    await editGroupMemberCard(context, member, mid, mode: mode);
    if (mounted) setState(() {}); // The member card was mutated in place.
  }

  late final EditGroupCast _castOps = EditGroupCast(
    context: () => context,
    group: widget.group,
    chat: Provider.of<ChatService>(context, listen: false),
    onDone: _reloadMembers,
  );
  int _removedCount = 0;

  CastActions _cast() => CastActions(
    onAdd: () => unawaited(_castOps.add()),
    onRemove: (m) => unawaited(_castOps.remove(m)),
    onBringBack: () => unawaited(_castOps.bringBack()),
    canBringBack: _removedCount > 0,
  );

  Future<void> _reloadMembers() async {
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final roster = await loadEditGroupRoster(
      groupRepo,
      storage,
      widget.group.id,
    );
    final removed = (await _castOps.editor.removedMembers(
      widget.group.id,
    )).length;
    if (!mounted) return;
    setState(() {
      _members
        ..clear()
        ..addAll(roster);
      _removedCount = removed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      isDirty: _isDirty,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _draft.name,
        builder: (context, name, _) => EditCharacterScaffold(
          characterName: widget.group.name,
          saveLabel: widget.saveLabel,
          popWithCardOnSave: widget.popWithGroupOnSave,
          onSave: name.text.trim().isEmpty ? null : _save,
          tabController: _tabController,
          banner: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: EditGroupForkNotice(
                group: widget.group,
                applied: _forkApplied,
                onUseSettings: _useForkSettings,
                inheritOn: _draft.inheritCharacterLorebooks,
                onInheritChanged: (v) =>
                    setState(() => _draft.inheritCharacterLorebooks = v),
              ),
            ),
          ),
          tabs: _tabs(),
        ),
      ),
    );
  }

  List<Widget> _tabs() {
    // A LISTENING read, as before: world changes rebuild the page.
    final worlds = Provider.of<WorldRepository>(context);
    return [
      EditGroupDetailsTab(
        groupId: widget.group.id,
        draft: _draft,
        members: _members,
        onEditMember: _editMember,
        cast: _cast(),
        onChanged: _rebuild,
      ),
      EditGroupDialogueTab(draft: _draft, onChanged: _rebuild),
      EditGroupLorebookTab(
        actions: _lore,
        entries: _draft.loreEntries,
        bookUnreadable: _draft.bookUnreadable,
        inheritCharacterLorebooks: _draft.inheritCharacterLorebooks,
        onInheritChanged: (v) =>
            setState(() => _draft.inheritCharacterLorebooks = v),
        onChanged: _rebuild,
      ),
      EditGroupWorldsTab(
        value: _draft.worldChoice,
        onChanged: (c) => setState(() => _draft.worldChoice = c),
        suggestedBy: worldsLinkedByMembers(_members, worlds),
        legacyWorldCount: groupNeedsWorldSplitNotice(widget.group)
            ? widget.group.worldIds.length
            : 0,
      ),
    ];
  }
}
