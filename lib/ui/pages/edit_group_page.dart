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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group.dart';
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

export 'package:front_porch_ai/ui/pages/edit_group/edit_group_lore_worlds_tab.dart'
    show kEditGroupUnreadableLoreNote;

/// The group editor: one page for everything a group is made of, in tabs
/// (Details, Dialogue, Lore & Worlds, Realism & Dynamics, Memory). It edits
/// the group's definition, so what it holds for Realism, Needs, Afterglow and
/// Pockets are defaults for NEW chats and never switch a chat that is open;
/// the name, prompts and turn order also apply to an open chat on Save. The
/// web twin is `GroupEditPage.tsx`, with the same sections in the same order.
class EditGroupPage extends StatefulWidget {
  final GroupChat group;

  /// Update-flow mode (e.g. the Stoop group Update): label the primary action
  /// (default 'Save', pass 'Next') and, when [popWithGroupOnSave] is true, pop
  /// returning the saved [GroupChat] instead of showing a toast + plain pop, so
  /// the caller can continue to a publish step. Defaults preserve normal editing.
  final String saveLabel;
  final bool popWithGroupOnSave;

  /// The section it opens on (see [kEditGroupSectionIds]).
  final int initialTab;

  const EditGroupPage({
    super.key,
    required this.group,
    this.saveLabel = 'Save',
    this.popWithGroupOnSave = false,
    this.initialTab = 0,
  });

  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late final TextEditingController _nameController;
  late final TextEditingController _firstMessageController;
  List<String> _altGreetings = [];
  List<GreetingRealismSeed?> _altGreetingSeeds = [];

  void _setAltGreetings(
    List<String> greetings,
    List<GreetingRealismSeed?> seeds,
  ) {
    setState(() {
      _altGreetings = greetings;
      _altGreetingSeeds = seeds;
    });
  }

  late final TextEditingController _scenarioController;
  late final TextEditingController _systemPromptController;

  // The members (cards for Details, rows for Realism with the origin ids the
  // editor recovers old seeds from) and their defaults for new chats.
  final _roster = EditGroupRoster();
  List<CharacterCard> get _members => _roster.members;
  List<GroupRealismMember> get _realismMembers => _roster.realism;
  final Map<String, TextEditingController> _charPromptControllers = {};
  bool _saving = false;

  late final EditGroupLorebook _lore;
  // Where new chats meet, and what the group stored when the page opened.
  GroupWorldChoice _worldChoice = const GroupWorldChoice();
  GroupWorldChoice _worldsAsLoaded = const GroupWorldChoice();
  bool _inheritCharacterLorebooks = false;

  // The fork notice filled the editor in. Bumping _realismGen rebuilds the
  // realism editor from the blobs it wrote.
  bool _forkApplied = false;
  int _realismGen = 0;

  void _useForkSettings(ForkedGroupSource s) {
    setState(() {
      if (s.realismMissingFrom(widget.group)) {
        final blobs = switchGroupTemplateRealism(
          defaultMemberJson: _defaultMemberRealismState,
          baselineJson: _baselineRealismState,
          memberIds: [for (final m in _realismMembers) m.mid],
          memberCards: {for (final m in _realismMembers) m.mid: m.extensions},
          realismOn: true,
          needsOn: s.needsOn,
        );
        _defaultMemberRealismState = blobs.defaultMemberJson;
        _baselineRealismState = blobs.baselineJson;
        _realismGen++;
      }
      if (s.worldMissingFrom(widget.group)) _worldChoice = s.worlds!;
      _forkApplied = true;
    });
  }

  String _baselineRealismState = '{}';
  String _defaultMemberRealismState = '{}';
  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorMode = false;

  bool _membersLoaded = false;

  /// The chat open on this group, or null: removing and adding members,
  /// Author's Notes and Memory need one.
  ChatService? get _openChat {
    final chat = Provider.of<ChatService>(context, listen: false);
    return openGroupOf(chat, widget.group.id) == null ? null : chat;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: kEditGroupTabs.length,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, kEditGroupTabs.length - 1),
    );

    final g = widget.group;
    _roster.addListener(_onRoster);
    _nameController = TextEditingController(text: g.name);
    _firstMessageController = TextEditingController(text: g.firstMessage);
    _altGreetings = List.from(g.alternateGreetings);
    _altGreetingSeeds = List.from(g.greetingSeeds);
    _scenarioController = TextEditingController(text: g.scenario);
    _systemPromptController = TextEditingController(text: g.systemPrompt);

    _inheritCharacterLorebooks = g.inheritCharacterLorebooks;
    _baselineRealismState = g.baselineRealismState;
    _defaultMemberRealismState = g.defaultMemberRealismState;
    _turnOrder = g.turnOrder;
    _autoAdvance = g.autoAdvance;
    _directorMode = g.directorMode;
    _lore = EditGroupLorebook(g.groupLorebook);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_membersLoaded) return;
    _membersLoaded = true;

    final g = widget.group;
    final worlds = Provider.of<WorldRepository>(context, listen: false);
    _loadRoster();

    // Per-char prompt controllers seeded from the stored overrides.
    for (final entry in g.characterSystemPrompts.entries) {
      _charPromptControllers[entry.key] = TextEditingController(
        text: entry.value,
      );
    }

    _worldChoice = _worldsAsLoaded = groupWorldChoiceIn(g, worlds);
    _startFingerprint = _values().fingerprint;
  }

  /// Reads the whole roster (fire-and-forget: this runs from a sync hook),
  /// then the editors seed from all of it at once. A page that was clean
  /// stays clean once the members are in.
  Future<void> _loadRoster() async {
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final clean = !_isDirty();
    await _roster.load(groupRepo, storage, widget.group.id);
    if (!mounted) return;
    // Per-char prompt controllers keyed by the member mid (matches the
    // runtime read + the fixed creator write).
    setState(() {
      for (final rm in _roster.realism) {
        _charPromptControllers.putIfAbsent(rm.mid, TextEditingController.new);
      }
    });
    if (clean) _startFingerprint = _values().fingerprint;
  }

  void _onRoster() {
    if (mounted) setState(() {});
  }

  /// Everything Save writes, so leaving can tell whether anything changed.
  /// Empty per-character prompts are dropped, as Save drops them.
  EditGroupValues _values() => EditGroupValues(
    name: _nameController.text.trim(),
    firstMessage: _firstMessageController.text.trim(),
    altGreetings: _altGreetings,
    altGreetingSeeds: _altGreetingSeeds,
    scenario: _scenarioController.text.trim(),
    systemPrompt: _systemPromptController.text.trim(),
    turnOrder: _turnOrder,
    autoAdvance: _autoAdvance,
    directorMode: _directorMode,
    worldChoice: _worldChoice,
    inheritCharacterLorebooks: _inheritCharacterLorebooks,
    charPrompts: {
      for (final e in _charPromptControllers.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    },
    loreEntries: _lore.entries,
    defaultMemberRealismState: _defaultMemberRealismState,
    baselineRealismState: _baselineRealismState,
    memberExtensions: _roster.extJson(),
  );
  String? _startFingerprint;

  bool _isDirty() =>
      _startFingerprint != null && _values().fingerprint != _startFingerprint;

  @override
  void dispose() {
    _roster
      ..removeListener(_onRoster)
      ..dispose();
    _tabController.dispose();
    _nameController.dispose();
    _firstMessageController.dispose();
    _scenarioController.dispose();
    _systemPromptController.dispose();
    for (final c in _charPromptControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveGroup() async {
    if (_saving) return;
    _saving = true;
    try {
      await _save();
    } finally {
      _saving = false;
    }
  }

  Future<void> _save() async {
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    final values = _values();

    // An unreadable stored book is never replaced without the user saying so.
    final keepRaw = await keepUnreadableGroupLorebook(
      context,
      bookUnreadable: _lore.unreadable,
      hasEntries: _lore.entries.isNotEmpty,
    );
    if (keepRaw == null) return;
    final updated = values.toGroup(
      widget.group,
      loreJson: _lore.toSave(keepRaw: keepRaw),
      worlds: groupWorldFieldsToSave(
        storedWorldIds: widget.group.worldIds,
        storedLoreWorldIds: widget.group.loreWorldIds,
        chosen: _worldChoice,
        asLoaded: _worldsAsLoaded,
      ),
    );

    try {
      await groupRepo.save(updated);
      final open = _openChat;
      await _roster.saveDefaults(liveDatabase(context), open);
      if (open != null) await applySavedGroupToOpenChat(open, updated);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);

      // Update-flow mode: hand the saved group back to the caller (which
      // continues to the Stoop publish step) instead of toasting + plain pop.
      if (widget.popWithGroupOnSave) {
        nav.pop(updated);
        return;
      }

      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            chatService.activeGroup?.id == updated.id
                ? 'Group "${updated.name}" updated. The name, prompts and turn '
                      'order apply to this chat now; the rest is for new chats.'
                : 'Group "${updated.name}" updated.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('EditGroupPage save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save group changes. Please try again.'),
            backgroundColor: AppColors.logError,
          ),
        );
      }
    }
  }

  Future<void> _addMember() async {
    final chat = _openChat;
    if (chat == null) return;
    final repo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    if (!await addMemberToOpenChat(context, chat, repo, _members)) return;
    if (!mounted) return;
    await _roster.load(repo, storage, widget.group.id);
  }

  /// Removing the second-to-last member turns the group into a 1:1 chat,
  /// which leaves nothing to edit: the page closes.
  Future<void> _removeMember(CharacterCard live) async {
    final chat = _openChat;
    if (chat == null) return;
    final repo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    if (!await removeMemberFromOpenChat(context, chat, repo, live)) return;
    if (!mounted) return;
    if (openGroupOf(chat, widget.group.id) == null) {
      Navigator.of(context).pop();
      return;
    }
    await _roster.load(repo, storage, widget.group.id);
  }

  // A start it saves is on the group's row already: a clean page stays clean.
  Future<void> _editMember(CharacterCard member, String memberId) async {
    final toRealism = await editGroupMemberFromEditGroup(
      context,
      group: widget.group,
      member: member,
      memberId: memberId,
      defaultMemberJson: _defaultMemberRealismState,
      baselineJson: _baselineRealismState,
      settingId: _worldChoice.settingId,
      inheritCharacterLorebooks: _inheritCharacterLorebooks,
      onStartSaved: (d, b) {
        final clean = !_isDirty();
        _defaultMemberRealismState = d;
        _baselineRealismState = b;
        _realismGen++;
        if (clean) _startFingerprint = _values().fingerprint;
      },
    );
    if (!mounted) return;
    // The member card was mutated in place, and the editor saved all of it:
    // what it holds is stored now.
    _roster.markStored();
    if (toRealism) _tabController.animateTo(kEditGroupRealismTab);
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      isDirty: _isDirty,
      child: Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        appBar: buildEditGroupAppBar(
          context,
          tabs: _tabController,
          name: _nameController,
          onSave: _saveGroup,
          saveLabel: widget.saveLabel,
          leadsOn: widget.popWithGroupOnSave,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                EditGroupForkNotice(
                  group: widget.group,
                  applied: _forkApplied,
                  onUseSettings: _useForkSettings,
                  inheritOn: _inheritCharacterLorebooks,
                  onInheritChanged: (v) =>
                      setState(() => _inheritCharacterLorebooks = v),
                ),
                Expanded(child: _tabs()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Details, Dialogue, Lore & Worlds, Realism and Memory are widgets under
  // edit_group/. All colors via AppColors.* only — no raw Colors.*.
  Widget _tabs() {
    // A LISTENING read, as before: world changes rebuild the page.
    final worlds = Provider.of<WorldRepository>(context);
    final chat = _openChat;
    return TabBarView(
      controller: _tabController,
      children: [
        EditGroupDetailsTab(
          nameController: _nameController,
          systemPromptController: _systemPromptController,
          scenarioController: _scenarioController,
          members: _members,
          charPromptControllers: _charPromptControllers,
          onEditMember: _editMember,
          turnOrder: _turnOrder,
          autoAdvance: _autoAdvance,
          directorMode: _directorMode,
          onTurnOrderChanged: (v) => setState(() => _turnOrder = v),
          onAutoAdvanceChanged: (v) => setState(() => _autoAdvance = v),
          onDirectorModeChanged: (v) => setState(() => _directorMode = v),
          openChat: chat,
          onRemoveMember: chat == null ? null : _removeMember,
          onAddMember: chat == null ? null : _addMember,
        ),
        EditGroupDialogueTab(
          firstMessageController: _firstMessageController,
          altGreetings: _altGreetings,
          altGreetingSeeds: _altGreetingSeeds,
          onAltGreetingsChanged: _setAltGreetings,
        ),
        EditGroupLoreWorldsTab(
          allWorlds: worlds.placeWorlds,
          weatherOf: groupWeatherLabels(worlds),
          suggestedBy: worldsLinkedByMembers(_members, worlds),
          legacyWorldCount: groupNeedsWorldSplitNotice(widget.group)
              ? widget.group.worldIds.length
              : 0,
          loreEntries: _lore.entries,
          bookUnreadable: _lore.unreadable,
          inheritCharacterLorebooks: _inheritCharacterLorebooks,
          worldChoice: _worldChoice,
          onAddEntry: (entry) {
            if (mounted) setState(() => _lore.entries.add(entry));
          },
          onReplaceEntry: (i, entry) {
            if (mounted) setState(() => _lore.entries[i] = entry);
          },
          onRemoveEntry: (i) => setState(() => _lore.entries.removeAt(i)),
          onInheritChanged: (v) =>
              setState(() => _inheritCharacterLorebooks = v),
          onWorldChoiceChanged: (c) => setState(() => _worldChoice = c),
        ),
        EditGroupRealismTab(
          key: ValueKey('group-realism-editor-$_realismGen'),
          loaded: _roster.loaded,
          members: _realismMembers,
          defaultMemberJson: _defaultMemberRealismState,
          baselineJson: _baselineRealismState,
          onEditMember: (mid) => _members
              .where((c) => c.dbId == mid)
              .forEach((c) => _editMember(c, mid)),
          memberExtras: (m) {
            final card = _members.where((c) => c.dbId == m.mid).firstOrNull;
            if (card == null) return null;
            return EditGroupMemberDefaults(
              member: card,
              onChanged: (ext) => _roster.setDefaults(m.mid, ext),
            );
          },
          onChanged: (d, b) {
            _defaultMemberRealismState = d;
            _baselineRealismState = b;
          },
        ),
        EditGroupMemoryTab(chat: chat),
      ],
    );
  }
}
