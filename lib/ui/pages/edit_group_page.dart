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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

// The Details, Dialogue, and Lore & Worlds tab builders live in these
// `part of` files (extensions on _EditGroupPageState) to keep every file
// under the 500-LOC cap — same pattern model_settings_dialog.dart uses. They
// share this library's imports and access the page's private state directly,
// so behavior is unchanged. The Realism & Dynamics tab builder stays inline
// in build() below — it's 22 lines and reads 4 state fields, simplest left
// as-is.
part 'edit_group_page.details.dart';
part 'edit_group_page.dialogue.dart';
part 'edit_group_page.lore_worlds.dart';

/// Tabbed group editor (edit-only flow).
/// Matches the visual tabbed style, section cards, and field treatment of EditCharacterPage
/// while using ONLY AppColors helpers (no hard-coded Color literals or raw Colors.*).
/// Pruned per spec:
/// - Personality & World: no Description/Personality fields; includes explanatory note,
///   Group System Prompt, Scenario, and Per-Character Overrides.
/// - Dialogue: First Message + alternate greetings with opening seeds;
///   Example Dialogue / mes_example completely omitted (GroupChat has no such field).
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

  final List<CharacterCard> _members = [];
  // Members as the realism editor needs them (mid + name + origin + avatar). The
  // origin lets the editor recover realism seeds from groups made before the
  // id-keying fix. Populated together with _members.
  final List<GroupRealismMember> _realismMembers = [];
  bool _realismLoaded = false;
  final Map<String, TextEditingController> _charPromptControllers = {};

  final List<LorebookEntry> _groupLoreEntries = [];
  final List<String> _worldIds = [];
  bool _inheritCharacterLorebooks = false;

  // Preserved on edit (baseline is immutable per spec; default seeds passed through)
  String _baselineRealismState = '{}';
  String _defaultMemberRealismState = '{}';
  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorMode = false;

  // Guards + data-loss protection (smallest possible additions)
  bool _membersLoaded = false;
  String _originalRawLorebook = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final g = widget.group;
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
    _worldIds.addAll(g.worldIds);
    _originalRawLorebook = g.groupLorebook;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_membersLoaded) return;
    _membersLoaded = true;

    final g = widget.group;
    // Load members (tolerate missing chars) — now in didChangeDependencies per standard pattern
    // Wire member loading for edit surfaces (extends existing load in didChangeDependencies).
    // groupRepo + private paths + toCharacterCard. Functional for pre-existing and new groups.
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    // Fire-and-forget async load (didChangeDependencies is sync). Collect the
    // full roster once, then a single setState — the Realism tab needs the whole
    // member list (with origin ids) before it initializes its seeds.
    () async {
      final memberRows = await groupRepo.getMembersForGroup(g.id);
      final cards = <CharacterCard>[];
      final realismMembers = <GroupRealismMember>[];
      for (final m in memberRows) {
        final fn = m.avatarFilename;
        if (fn == null) continue;
        final avatarPath = p.join(storage.groupsDir.path, g.id, 'avatars', fn);
        if (!await File(avatarPath).exists()) continue;
        cards.add(m.toCharacterCard(resolvedImagePath: avatarPath));
        realismMembers.add(
          GroupRealismMember(
            mid: m.id,
            name: m.name,
            originStableId: m.originStableId,
            avatarPath: avatarPath,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _members.addAll(cards);
          _realismMembers.addAll(realismMembers);
          _realismLoaded = true;
          // Per-char prompt controllers keyed by the member mid (matches the
          // runtime read + the fixed creator write).
          for (final rm in realismMembers) {
            _charPromptControllers.putIfAbsent(
              rm.mid,
              () => TextEditingController(),
            );
          }
        });
      }
    }();

    // Per-char prompt controllers seeded from the stored overrides (member-level
    // empty controllers are added in the async roster load above).
    for (final entry in g.characterSystemPrompts.entries) {
      _charPromptControllers[entry.key] = TextEditingController(
        text: entry.value,
      );
    }

    // Parse existing group lorebook (preserve raw on failure for data safety)
    if (g.groupLorebook.isNotEmpty &&
        g.groupLorebook != '{}' &&
        g.groupLorebook != '[]') {
      try {
        final decoded = jsonDecode(g.groupLorebook);
        if (decoded is Map<String, dynamic>) {
          _groupLoreEntries.addAll(Lorebook.fromJson(decoded).entries);
        }
      } catch (_) {
        // Keep _originalRawLorebook; do not clear on bad parse
      }
    }
  }

  @override
  void dispose() {
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
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    final charPrompts = <String, String>{};
    for (final entry in _charPromptControllers.entries) {
      final t = entry.value.text.trim();
      if (t.isNotEmpty) charPrompts[entry.key] = t;
    }

    // Lore JSON: protect against silent loss from parse failure in init (use original raw if user made no edits to lore)
    String groupLoreJson;
    if (_groupLoreEntries.isEmpty && _originalRawLorebook.isNotEmpty) {
      groupLoreJson = _originalRawLorebook;
    } else {
      final lb = Lorebook(entries: List.from(_groupLoreEntries));
      groupLoreJson = jsonEncode(lb.toJson());
    }

    final updated = GroupChat(
      id: widget.group.id,
      // Preserve the portable stable id (used for in-place Stoop updates +
      // cross-device). Rebuilding the GroupChat from scratch would otherwise
      // silently drop it.
      stableId: widget.group.stableId,
      name: _nameController.text.trim().isEmpty
          ? widget.group.name
          : _nameController.text.trim(),
      // characterIds removed (decoupled group members).
      turnOrder: _turnOrder,
      autoAdvance: _autoAdvance,
      directorMode: _directorMode,
      firstMessage: _firstMessageController.text.trim(),
      alternateGreetings: List.from(_altGreetings),
      greetingSeeds: List.from(_altGreetingSeeds),
      scenario: _scenarioController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      defaultMemberRealismState: withGroupOpeningAlts(
        _defaultMemberRealismState,
        alternateGreetings: _altGreetings,
        greetingSeeds: _altGreetingSeeds,
      ),
      baselineRealismState: _baselineRealismState,
      characterSystemPrompts: charPrompts,
      worldIds: List.from(_worldIds),
      groupLorebook: groupLoreJson,
      inheritCharacterLorebooks: _inheritCharacterLorebooks,
      // Chaos flags are runtime/session settings (controlled in Group Settings dialog).
      // Preserve whatever was on the original definition.
      chaosModeEnabled: widget.group.chaosModeEnabled,
      chaosNsfwEnabled: widget.group.chaosNsfwEnabled,
    );

    try {
      await groupRepo.save(updated);

      if (!mounted) return;
      // Capture *before* any pop (fixes snackbar attachment + supports active-chat desync notice)
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);

      // Update-flow mode: hand the saved group back to the caller (which
      // continues to the Stoop publish step) instead of toasting + plain pop.
      if (widget.popWithGroupOnSave) {
        nav.pop(updated);
        return;
      }

      final wasActive = chatService.activeGroup?.id == updated.id;
      nav.pop();
      final msg = wasActive
          ? 'Group "${updated.name}" updated. Changes apply on next New Chat / re-entry.'
          : 'Group "${updated.name}" updated.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
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

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`edit_group_page.*.dart`), which hold the Details, Dialogue, and Lore &
  /// Worlds tab builders but can't call a State's protected members directly.
  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    // Only the Realism & Dynamics tab builder stays local here; Details,
    // Dialogue, and Lore & Worlds moved to `part of` extension methods
    // (_buildDetailsTab / _buildDialogueTab / _buildLoreWorldsTab below).
    // All colors via AppColors.* only — no 0xFF, no raw Colors.* introduced.

    Widget buildRealismTab() {
      if (!_realismLoaded) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      }
      // Edits flow straight into the two blobs the Save button already persists.
      // No setState needed — the editor owns its own display state.
      return GroupRealismDynamicsEditor(
        key: const ValueKey('group-realism-editor'),
        members: _realismMembers,
        initialDefaultMemberJson: _defaultMemberRealismState,
        initialBaselineJson: _baselineRealismState,
        onChanged: (d, b) {
          _defaultMemberRealismState = d;
          _baselineRealismState = b;
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Edit Group'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.formMasterAccent,
          unselectedLabelColor: AppColors.textTertiary(context),
          indicatorColor: AppColors.formMasterAccent,
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
            Tab(
              icon: Icon(Icons.chat_bubble_outline, size: 18),
              text: 'Dialogue',
            ),
            Tab(
              icon: Icon(Icons.auto_stories_outlined, size: 18),
              text: 'Lore & Worlds',
            ),
            Tab(
              icon: Icon(Icons.favorite_outline, size: 18),
              text: 'Realism & Dynamics',
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameController,
              builder: (context, value, _) {
                final hasName = value.text.trim().isNotEmpty;
                return ElevatedButton.icon(
                  onPressed: hasName ? _saveGroup : null,
                  icon: Icon(
                    widget.popWithGroupOnSave
                        ? Icons.arrow_forward
                        : Icons.save_outlined,
                    size: 18,
                  ),
                  label: Text(widget.saveLabel),
                );
              },
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDetailsTab(),
              _buildDialogueTab(),
              _buildLoreWorldsTab(),
              buildRealismTab(),
            ],
          ),
        ),
      ),
    );
  }
}
