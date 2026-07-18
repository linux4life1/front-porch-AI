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
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Tabbed group editor (edit-only flow).
/// Matches the visual tabbed style, section cards, and field treatment of EditCharacterPage
/// while using ONLY AppColors helpers (no hard-coded Color literals or raw Colors.*).
/// Pruned per spec:
/// - Personality & World: no Description/Personality fields; includes explanatory note,
///   Group System Prompt, Scenario, and Per-Character Overrides.
/// - Dialogue: First Message kept; Alternate Greetings is a disabled "Coming soon" stub;
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
  bool _inheritCharacterLorebooks = true;

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
      scenario: _scenarioController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      defaultMemberRealismState: _defaultMemberRealismState,
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
            backgroundColor: AppColors.resolve(
              context,
              AppColors.logError,
              AppColors.logError,
            ),
          ),
        );
      }
    }
  }

  // Edit one member's card content in the reused single-character editor. Saves
  // to THIS group's member row only (never the source library character), and
  // preserves the member's group state (realism/needs, avatar) by writing just
  // the content columns.
  Future<void> _editMember(CharacterCard member, String memberId) async {
    final database = Provider.of<db.AppDatabase>(context, listen: false);
    final edited = await Navigator.of(context).push<CharacterCard>(
      MaterialPageRoute(
        builder: (_) => EditCharacterPage(
          character: member,
          showRealismTab: false,
          allowAvatarChange: false,
          popWithCardOnSave: true,
          onSaveOverride: (card) async {
            await database.updateGroupMember(
              db.GroupMembersCompanion(
                id: Value(memberId),
                name: Value(card.name),
                description: Value(card.description),
                personality: Value(card.personality),
                scenario: Value(card.scenario),
                firstMessage: Value(card.firstMessage),
                mesExample: Value(card.mesExample),
                systemPrompt: Value(card.systemPrompt),
                postHistoryInstructions: Value(card.postHistoryInstructions),
                alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
                tags: Value(jsonEncode(card.tags)),
                lorebook: Value(
                  card.lorebook != null
                      ? jsonEncode(card.lorebook!.toJson())
                      : null,
                ),
                worldNames: Value(jsonEncode(card.worldNames)),
              ),
            );
          },
        ),
      ),
    );
    if (edited != null && mounted) {
      // The member card was mutated in place, so a rebuild reflects the edits.
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${edited.name}” updated in this group.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Local (non-class) helpers keep total class-level private methods at 1 (_saveGroup).
    // All colors via AppColors.* only — no 0xFF, no raw Colors.* introduced.

    Widget buildDetailsTab() {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group Name',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            AppTextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'My Group'),
            ),
            const SizedBox(height: 20),

            // Personality & World — strictly pruned (no Description, no Personality).
            // Matches create wizard grouping + explanatory note.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        color: AppColors.resolve(
                          context,
                          AppColors.logLoading,
                          AppColors.userBubble,
                        ),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Personality & World',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.resolve(
                            context,
                            AppColors.logLoading,
                            AppColors.userBubble,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Group-level equivalents to character personality live in the system prompt and scenario.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary(context),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Group System Prompt',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: _systemPromptController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Global instructions for this group...',
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Scenario (optional)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: _scenarioController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'The group is...',
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Per-Character Overrides (optional)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_members.isEmpty)
                    Text(
                      'No members in this group.',
                      style: TextStyle(color: AppColors.textTertiary(context)),
                    )
                  else
                    ..._members.map((c) {
                      final id =
                          c.dbId ??
                          (c.imagePath != null
                              ? p.basenameWithoutExtension(c.imagePath!)
                              : c.name);
                      final ctrl =
                          _charPromptControllers[id] ?? TextEditingController();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.borderOf(
                              context,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _editMember(c, id),
                                  icon: const Icon(Icons.edit_outlined, size: 15),
                                  label: const Text('Edit'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textSecondary(
                                      context,
                                    ),
                                    side: BorderSide(
                                      color: AppColors.borderOf(context),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            AppTextField(
                              controller: ctrl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText:
                                    'Extra instructions only for this character in this group',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildDialogueTab() {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: AppColors.resolve(
                          context,
                          AppColors.action,
                          AppColors.userBubble,
                        ),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Dialogue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.resolve(
                            context,
                            AppColors.action,
                            AppColors.userBubble,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'First Message (optional)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: _firstMessageController,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'The scene opens with...',
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Alternate Greetings stub — disabled, exact text per spec.
                  // No Example Dialogue section at all (GroupChat has none).
                  Opacity(
                    opacity: 0.6,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.swap_horiz,
                                color: AppColors.iconSecondary(context),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Alternate Greetings',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.resolve(
                                    context,
                                    AppColors.surfaceContainer,
                                    AppColors.surfaceContainerLight,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Coming soon',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textTertiary(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Alternate greetings for groups are coming in a future update. The opening message above is used for new sessions today.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildLoreWorldsTab() {
      final worldRepo = Provider.of<WorldRepository>(context);
      final allWorlds = worldRepo.worlds;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Group Lorebook',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final nameCtrl = TextEditingController();
                    final keyCtrl = TextEditingController();
                    final contentCtrl = TextEditingController();
                    bool enabled = true;
                    bool constant = false;

                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surfaceOf(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text('Add Group Lore Entry'),
                        content: StatefulBuilder(
                          builder: (inner, setInner) => SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppTextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Name',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                AppTextField(
                                  controller: keyCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Key / Trigger',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                AppTextField(
                                  controller: contentCtrl,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: 'Content',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SwitchListTile(
                                  title: const Text('Enabled'),
                                  value: enabled,
                                  onChanged: (v) => setInner(() => enabled = v),
                                  dense: true,
                                ),
                                SwitchListTile(
                                  title: const Text('Constant'),
                                  value: constant,
                                  onChanged: (v) =>
                                      setInner(() => constant = v),
                                  dense: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary(context),
                            ),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && mounted) {
                      setState(() {
                        _groupLoreEntries.add(
                          LorebookEntry(
                            name: nameCtrl.text.trim(),
                            key: keyCtrl.text.trim(),
                            content: contentCtrl.text.trim(),
                            enabled: enabled,
                            constant: constant,
                          ),
                        );
                      });
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Entry'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_groupLoreEntries.isEmpty)
              Text(
                'No group lore entries yet. These take highest priority in prompts.',
                style: TextStyle(color: AppColors.textSecondary(context)),
              )
            else
              ..._groupLoreEntries.asMap().entries.map((e) {
                final i = e.key;
                final entry = e.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    entry.name.isNotEmpty ? entry.name : entry.key,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  subtitle: Text(
                    entry.content.length > 80
                        ? '${entry.content.substring(0, 80)}...'
                        : entry.content,
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () async {
                          final nameCtrl = TextEditingController(
                            text: entry.name,
                          );
                          final keyCtrl = TextEditingController(
                            text: entry.key,
                          );
                          final contentCtrl = TextEditingController(
                            text: entry.content,
                          );
                          bool enabled = entry.enabled;
                          bool constant = entry.constant;

                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surfaceOf(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text('Edit Group Lore Entry'),
                              content: StatefulBuilder(
                                builder: (inner, setInner) =>
                                    SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AppTextField(
                                            controller: nameCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Name',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          AppTextField(
                                            controller: keyCtrl,
                                            decoration: const InputDecoration(
                                              labelText: 'Key / Trigger',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          AppTextField(
                                            controller: contentCtrl,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                              labelText: 'Content',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SwitchListTile(
                                            title: const Text('Enabled'),
                                            value: enabled,
                                            onChanged: (v) =>
                                                setInner(() => enabled = v),
                                            dense: true,
                                          ),
                                          SwitchListTile(
                                            title: const Text('Constant'),
                                            value: constant,
                                            onChanged: (v) =>
                                                setInner(() => constant = v),
                                            dense: true,
                                          ),
                                        ],
                                      ),
                                    ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true && mounted) {
                            setState(() {
                              _groupLoreEntries[i] = LorebookEntry(
                                name: nameCtrl.text.trim(),
                                key: keyCtrl.text.trim(),
                                content: contentCtrl.text.trim(),
                                enabled: enabled,
                                constant: constant,
                              );
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () =>
                            setState(() => _groupLoreEntries.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Inherit character & world lorebooks'),
              subtitle: const Text(
                'When on, member cards and their attached worlds contribute lore in addition to the group lorebook above.',
              ),
              value: _inheritCharacterLorebooks,
              onChanged: (v) => setState(() => _inheritCharacterLorebooks = v),
            ),

            const SizedBox(height: 20),
            Text(
              'Linked Worlds',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ..._worldIds.map((wid) {
                  final w = allWorlds.firstWhere(
                    (ww) => ww.name == wid,
                    orElse: () => World(
                      name: wid,
                      lorebook: Lorebook(entries: const []),
                    ),
                  );
                  final isMissing = !allWorlds.any((ww) => ww.name == wid);
                  return Chip(
                    label: Text(
                      isMissing ? '$wid (missing)' : w.name,
                      style: TextStyle(
                        color: isMissing
                            ? AppColors.textTertiary(context)
                            : null,
                      ),
                    ),
                    onDeleted: () => setState(() => _worldIds.remove(wid)),
                  );
                }),
                OutlinedButton.icon(
                  onPressed: () async {
                    final chosen = await showDialog<World>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        backgroundColor: AppColors.surfaceOf(context),
                        title: const Text('Link a World'),
                        children: allWorlds
                            .map(
                              (w) => SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, w),
                                child: Text(w.name),
                              ),
                            )
                            .toList(),
                      ),
                    );
                    if (chosen != null && !_worldIds.contains(chosen.name)) {
                      setState(() => _worldIds.add(chosen.name));
                    }
                  },
                  icon: const Icon(Icons.public, size: 18),
                  label: const Text('Link World'),
                ),
              ],
            ),

            const SizedBox(height: 24),
            // Chaos Mode flags are intentionally not editable here.
            // They are live runtime/session settings controlled exclusively
            // via the in-chat Group Settings dialog ("Realism & Needs" tab).
            // We preserve existing values on the GroupChat definition (see save logic).
          ],
        ),
      );
    }

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
          labelColor: AppColors.resolve(
            context,
            AppColors.userBubble,
            AppColors.userBubbleLight,
          ),
          unselectedLabelColor: AppColors.textTertiary(context),
          indicatorColor: AppColors.resolve(
            context,
            AppColors.userBubble,
            AppColors.userBubbleLight,
          ),
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
              buildDetailsTab(),
              buildDialogueTab(),
              buildLoreWorldsTab(),
              buildRealismTab(),
            ],
          ),
        ),
      ),
    );
  }
}
