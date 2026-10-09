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
//
// Group wizard steps 1-2: pick the members, name the group.
// Extracted verbatim from create_group_chat_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so every private member and the
// mandatory wizard step-indicator flow stay exactly as they were.

part of 'create_group_chat_page.dart';

extension _GroupWizardCastSteps on _CreateGroupChatPageState {
  Widget _buildMembersStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Build your roster. At least 2 characters required.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),

          // Current Roster
          Row(
            children: [
              Text(
                'Current Roster (${_members.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              if (_members.length < 2) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      Colors.redAccent.withValues(alpha: 0.15),
                      Colors.red.withValues(alpha: 0.15),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Minimum 2 required',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        Colors.redAccent,
                        Colors.red.shade700,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No members yet — add from the browser below'),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _members.length,
              onReorderItem: _reorderMembers,
              itemBuilder: (ctx, i) {
                final c = _members[i];
                final id = _stableId(c);
                final voice = _characterVoices[id] ?? c.ttsVoice ?? '';
                // {{char}} / {{user}} resolved, as the library grid shows it.
                final desc = c.formattedDescription;
                return Card(
                  key: ValueKey(id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _avatar(c, radius: 22),
                    title: Text(c.name),
                    subtitle: Text(
                      '${desc.isNotEmpty ? desc.substring(0, desc.length.clamp(0, 60)) : "No description"}...',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 200,
                          child: CharacterVoicePicker(
                            value: voice,
                            dense: true,
                            onChanged: (v) => _setVoice(id, v),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _removeMember(id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 24),
          Text(
            'Add Characters',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),

          // Folder-aware character browser (shared picker — the same folder
          // rules as the home grid; search reaches into every folder).
          FolderCharacterPicker(
            characters: _availableCharacters,
            folderService: Provider.of<FolderService>(context),
            onTapCharacter: _addMember,
          ),

          _buildNavButtons(currentStep: 0),
        ],
      ),
    );
  }

  Widget _avatar(CharacterCard c, {double radius = 20}) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: c.imagePath != null
          ? FileImage(File(c.imagePath!))
          : null,
      child: c.imagePath == null
          ? Icon(Icons.person, size: radius * 0.9)
          : null,
    );
  }

  Widget _buildIdentityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identity & Behavior',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Group Name',
              hintText: 'e.g. The Ember Circle',
            ),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Turn Order',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TurnOrder>(
            segments: const [
              ButtonSegment(
                value: TurnOrder.roundRobin,
                label: Text('Round Robin'),
                icon: Icon(Icons.repeat),
              ),
              ButtonSegment(
                value: TurnOrder.random,
                label: Text('Random'),
                icon: Icon(Icons.shuffle),
              ),
            ],
            selected: {_turnOrder},
            onSelectionChanged: (v) => rebuildState(() => _turnOrder = v.first),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Auto-Advance'),
            subtitle: const Text(
              'Characters respond one after another automatically',
            ),
            value: _autoAdvance,
            onChanged: (v) => rebuildState(() => _autoAdvance = v),
            activeThumbColor: AppColors.resolve(
              context,
              const Color(0xFF7C3AED),
              const Color(0xFF6D28D9),
            ),
          ),
          SwitchListTile(
            title: Row(
              children: [
                Icon(
                  Icons.movie_creation,
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text('Director Mode'),
              ],
            ),
            subtitle: const Text(
              'Characters chat autonomously — you direct the scene (no player present)',
            ),
            value: _directorMode,
            onChanged: (v) => rebuildState(() => _directorMode = v),
            activeThumbColor: AppColors.resolve(
              context,
              Colors.amberAccent,
              Colors.amber.shade700,
            ),
          ),

          _buildNavButtons(currentStep: 1),
        ],
      ),
    );
  }
}
