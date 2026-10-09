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

part of 'edit_group_page.dart';

/// Details tab: group name, system prompt, scenario, and per-character prompt
/// overrides — plus the single-member editor push. Split out of
/// `edit_group_page.dart` (extension on _EditGroupPageState) to keep every
/// file under the 500-LOC cap — same pattern model_settings_dialog.dart uses.
/// Verbatim except `setState` -> `rebuildState` (extensions can't call a
/// State's protected members directly).
extension _EditGroupDetailsTab on _EditGroupPageState {
  // Edit one member's card content in the reused single-character editor. Saves
  // to THIS group's member row only (never the source library character), and
  // preserves the member's group state (realism/needs, avatar) by writing just
  // the content columns.
  Future<void> _editMember(CharacterCard member, String memberId) async {
    // The live database, not the startup snapshot `Provider<AppDatabase>`
    // holds: a backup restore closes that one.
    final database = liveDatabase(context);
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
      rebuildState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${edited.name}” updated in this group.')),
      );
    }
  }

  Widget _buildDetailsTab() {
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
                      color: AppColors.porchAmberOf(context),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Personality & World',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.porchAmberOf(context),
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
}
