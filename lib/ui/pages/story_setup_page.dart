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
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';
import 'package:path/path.dart' as p;

/// Setup page for a new Porch Story with comprehensive customization options.
class StorySetupPage extends StatefulWidget {
  final String projectId;
  const StorySetupPage({super.key, required this.projectId});

  @override
  State<StorySetupPage> createState() => _StorySetupPageState();
}

class _StorySetupPageState extends State<StorySetupPage> {
  // ── Basic Info ──
  final _titleController = TextEditingController();
  final _conceptController = TextEditingController();
  List<Map<String, String>> _archetypes = [];

  // ── Story Customization ──
  String _pov = 'Third Person Limited';
  int _actCount = 3;
  final Set<String> _selectedGenres = {};
  final Set<String> _selectedMoods = {};
  String _writingStyle = '';
  String _proseLength = 'Standard';
  String _narrativePace = 'Balanced';
  String _dialogueDensity = 'Balanced';
  String _maturityRating = 'Mature';

  // ── AI Config ──
  PromptTier _selectedTier = PromptTier.frontier;
  bool _useChatHistory = false;
  bool _parallelGeneration = false;
  final Set<String> _selectedCharacterIds = {};
  final Map<String, String> _characterRoles = {}; // charDbId -> role
  bool _includeUserPersona = false;
  String _userPersonaRole = 'Protagonist';

  static const _roleOptions = [
    'Protagonist',
    'Antagonist',
    'Supporting',
    'Love Interest',
    'Mentor',
  ];

  // ── Option Lists ──
  static const _povOptions = [
    'First Person',
    'Third Person Limited',
    'Third Person Omniscient',
  ];

  static const _genreOptions = [
    'Fantasy', 'Sci-Fi', 'Romance', 'Thriller', 'Horror',
    'Literary Fiction', 'Mystery', 'Historical', 'Comedy', 'Drama',
    'Adventure', 'Dystopian', 'Paranormal', 'Western', 'Slice of Life',
  ];

  static const _moodOptions = [
    'Dark', 'Light', 'Gritty', 'Whimsical', 'Melancholy',
    'Tense', 'Hopeful', 'Bittersweet', 'Eerie', 'Nostalgic',
    'Epic', 'Intimate', 'Satirical',
  ];

  static const _writingStyles = [
    'Minimalist', 'Lyrical/Poetic', 'Pulpy/Action', 'Literary',
    'Conversational', 'Gothic', 'Hardboiled', 'Philosophical',
    'Cinematic', 'Fairy-Tale',
  ];

  static const _proseLengths = {
    'Short': 'Novella (~20K words)',
    'Standard': 'Novel (~50K words)',
    'Epic': 'Long novel (~80K+ words)',
  };

  static const _paceOptions = {
    'Slow Burn': 'Atmospheric, detailed worldbuilding',
    'Balanced': 'Mix of action and reflection',
    'Fast-Paced': 'Tight scenes, rapid plot movement',
  };

  static const _dialogueOptions = {
    'Sparse': 'Mostly narrative prose',
    'Balanced': 'Even mix of dialogue and prose',
    'Dialogue-Heavy': 'Character-driven, lots of conversation',
  };

  static const _maturityOptions = {
    'Clean': 'All ages, no violence or language',
    'Mature': 'Adult themes, moderate violence',
    'Explicit': 'Graphic content, no restrictions',
  };

  // ── Color palette ──
  static const _bgDark = Color(0xFF0F172A);
  static const _bgCard = Color(0xFF1E293B);
  static const _accentAmber = Colors.amber;

  @override
  void initState() {
    super.initState();
    _archetypes = StoryPipelineService.generateArchetypes(count: 6);
    _loadProject();
  }

  void _loadProject() {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project != null) {
      _titleController.text = project.title;
      _conceptController.text = project.concept;
      _selectedTier = project.promptTier;
      _useChatHistory = project.useChatHistory;
      _parallelGeneration = project.parallelGeneration;
      _selectedCharacterIds.addAll(project.chatHistoryCharacterIds);
      _includeUserPersona = project.includeUserPersona;
      _userPersonaRole = project.userPersonaRole;
      // Restore roles from snapshots
      for (final snap in project.characterCardSnapshots) {
        final name = snap['name'] ?? '';
        final role = snap['role'] ?? 'Supporting';
        // Find the character ID by name
        final charRepo = Provider.of<CharacterRepository>(context, listen: false);
        for (final c in charRepo.characters) {
          if (c.dbId != null && c.name == name && _selectedCharacterIds.contains(c.dbId)) {
            _characterRoles[c.dbId!] = role;
          }
        }
      }
      _pov = project.pov;
      _actCount = project.actCount;
      _selectedGenres.addAll(project.selectedGenres);
      _selectedMoods.addAll(project.selectedMoods);
      _writingStyle = project.writingStyle;
      _proseLength = project.proseLength;
      _narrativePace = project.narrativePace;
      _dialogueDensity = project.dialogueDensity;
      _maturityRating = project.maturityRating;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _conceptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Colors.amberAccent, size: 22),
            SizedBox(width: 8),
            Text('New Porch Story'),
          ],
        ),
        backgroundColor: _bgCard,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════
                //  SECTION 1: Story Identity
                // ═══════════════════════════════════════
                _sectionHeader('Story Identity', Icons.edit_note),
                const SizedBox(height: 12),
                _buildTextField(_titleController, 'Story title...'),
                const SizedBox(height: 12),
                _buildTextField(
                  _conceptController,
                  'What is the story about? Be as detailed as you want...\n\n'
                  'Examples:\n'
                  '\u2022 A cyberpunk heist gone wrong in neon-drenched Tokyo\n'
                  '\u2022 A slow-burn romance between rival guild leaders\n'
                  '\u2022 An ancient war told from both sides',
                  maxLines: 5,
                ),
                const SizedBox(height: 8),
                Text('Quick concepts:', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._archetypes.map((a) => _chipButton(
                      a['label']!,
                      isSelected: false,
                      onTap: () => setState(() => _conceptController.text = a['value']!),
                      color: Colors.amber,
                    )),
                    ActionChip(
                      avatar: const Icon(Icons.refresh, size: 14, color: Colors.white54),
                      label: const Text('Refresh', style: TextStyle(fontSize: 11, color: Colors.white54)),
                      backgroundColor: Colors.transparent,
                      side: BorderSide.none,
                      onPressed: () => setState(() => _archetypes = StoryPipelineService.generateArchetypes(count: 6)),
                    ),
                  ],
                ),
                _sectionDivider(),

                // ═══════════════════════════════════════
                //  SECTION 2: Point of View
                // ═══════════════════════════════════════
                _sectionHeader('Point of View', Icons.visibility),
                const SizedBox(height: 8),
                Text(
                  'Choose who narrates the story',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _povOptions.map((pov) => _radioChip(
                    pov,
                    isSelected: _pov == pov,
                    onTap: () => setState(() => _pov = pov),
                    color: Colors.cyan,
                  )).toList(),
                ),
                _sectionDivider(),

                // ═══════════════════════════════════════
                //  SECTION 3: Genre & Mood
                // ═══════════════════════════════════════
                _sectionHeader('Genre', Icons.category),
                const SizedBox(height: 8),
                Text(
                  'Select one or more genres to blend',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _genreOptions.map((g) => _chipButton(
                    g,
                    isSelected: _selectedGenres.contains(g),
                    onTap: () => setState(() {
                      if (_selectedGenres.contains(g)) {
                        _selectedGenres.remove(g);
                      } else {
                        _selectedGenres.add(g);
                      }
                    }),
                    color: Colors.purple,
                  )).toList(),
                ),
                const SizedBox(height: 20),
                _sectionHeader('Mood', Icons.palette),
                const SizedBox(height: 8),
                Text(
                  'Set the emotional atmosphere',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _moodOptions.map((m) => _chipButton(
                    m,
                    isSelected: _selectedMoods.contains(m),
                    onTap: () => setState(() {
                      if (_selectedMoods.contains(m)) {
                        _selectedMoods.remove(m);
                      } else {
                        _selectedMoods.add(m);
                      }
                    }),
                    color: Colors.teal,
                  )).toList(),
                ),
                _sectionDivider(),

                // ═══════════════════════════════════════
                //  SECTION 4: Writing Preferences
                // ═══════════════════════════════════════
                _sectionHeader('Writing Style', Icons.brush),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _writingStyles.map((s) => _radioChip(
                    s,
                    isSelected: _writingStyle == s,
                    onTap: () => setState(() => _writingStyle = _writingStyle == s ? '' : s),
                    color: Colors.deepOrange,
                  )).toList(),
                ),
                const SizedBox(height: 20),
                _sectionHeader('Prose Length', Icons.format_size),
                const SizedBox(height: 10),
                ..._proseLengths.entries.map((e) => _radioTile(
                  e.key, e.value,
                  isSelected: _proseLength == e.key,
                  onTap: () => setState(() => _proseLength = e.key),
                  color: Colors.indigo,
                )),
                const SizedBox(height: 20),
                _sectionHeader('Narrative Pace', Icons.speed),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _paceOptions.entries.map((e) => _radioChip(
                    e.key,
                    isSelected: _narrativePace == e.key,
                    onTap: () => setState(() => _narrativePace = e.key),
                    color: Colors.amber,
                    subtitle: e.value,
                  )).toList(),
                ),
                const SizedBox(height: 20),
                _sectionHeader('Dialogue Density', Icons.chat_bubble_outline),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _dialogueOptions.entries.map((e) => _radioChip(
                    e.key,
                    isSelected: _dialogueDensity == e.key,
                    onTap: () => setState(() => _dialogueDensity = e.key),
                    color: Colors.lightBlue,
                    subtitle: e.value,
                  )).toList(),
                ),
                _sectionDivider(),

                // ═══════════════════════════════════════
                //  SECTION 5: Story Structure
                // ═══════════════════════════════════════
                _sectionHeader('Story Structure', Icons.account_tree),
                const SizedBox(height: 12),
                _buildActCountSlider(),
                const SizedBox(height: 20),
                _sectionHeader('Maturity Rating', Icons.shield_outlined),
                const SizedBox(height: 10),
                ..._maturityOptions.entries.map((e) => _radioTile(
                  e.key, e.value,
                  isSelected: _maturityRating == e.key,
                  onTap: () => setState(() => _maturityRating = e.key),
                  color: e.key == 'Clean' ? Colors.green
                       : e.key == 'Mature' ? Colors.orange
                       : Colors.red,
                )),
                _sectionDivider(),

                // ═══════════════════════════════════════
                //  SECTION 6: AI Configuration
                // ═══════════════════════════════════════
                _sectionHeader('AI Configuration', Icons.settings_suggest),
                const SizedBox(height: 12),
                _buildTierSelector(),
                const SizedBox(height: 16),
                _buildToggleTile(
                  'Chat History Integration',
                  'Weave past character conversations into the story via RAG',
                  Icons.history,
                  _useChatHistory,
                  Colors.blueAccent,
                  (v) => setState(() => _useChatHistory = v),
                ),
                if (_useChatHistory) ...[
                  const SizedBox(height: 12),
                  _buildCharacterPicker(),
                  if (_selectedCharacterIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildRoleAssignment(),
                  ],
                  const SizedBox(height: 12),
                  _buildUserPersonaToggle(),
                ],
                const SizedBox(height: 12),
                const SizedBox(height: 32),

                // ═══════════════════════════════════════
                //  ACTIONS
                // ═══════════════════════════════════════
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white54),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _conceptController.text.trim().isEmpty ? null : _startGeneration,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate Story Bible'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentAmber.shade800,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white10,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  REUSABLE WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.amberAccent, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _sectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(color: Colors.white.withValues(alpha: 0.06)),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return AppTextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: _bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  /// A selectable chip for multi-select options (genre, mood, features).
  Widget _chipButton(String label, {required bool isSelected, required VoidCallback onTap, required MaterialColor color}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.shade800.withValues(alpha: 0.3) : _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color.shade400 : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color.shade200 : Colors.white60,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// A radio-style chip for single-select options (POV, pace, dialogue, style).
  Widget _radioChip(String label, {
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
    String? subtitle,
  }) {
    final chipColor = color is MaterialColor ? color.shade400 : color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.15) : _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 16,
                  color: isSelected ? chipColor : Colors.white30,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A radio-style tile for single-select options with descriptions (prose length, maturity).
  Widget _radioTile(String label, String description, {
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
  }) {
    final tileColor = color is MaterialColor ? color.shade600 : color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? tileColor.withValues(alpha: 0.12) : _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? tileColor : Colors.white10,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isSelected ? tileColor : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActCountSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Number of Acts',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_actCount',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.amber.shade700,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.amber.shade600,
              overlayColor: Colors.amber.shade200.withValues(alpha: 0.2),
              valueIndicatorColor: Colors.amber.shade800,
              valueIndicatorTextStyle: const TextStyle(color: Colors.white),
            ),
            child: Slider(
              value: _actCount.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_actCount acts',
              onChanged: (v) => setState(() => _actCount = v.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1 (Short story)', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
              Text('3 (Classic)', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
              Text('5 (Epic)', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTierSelector() {
    return Column(
      children: PromptTier.values.map((tier) {
        final isSelected = _selectedTier == tier;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selectedTier = tier),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.amber.shade800.withValues(alpha: 0.15)
                    : _bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.amber.shade700 : Colors.white10,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.amber.shade600 : Colors.white38,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tierName(tier),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _tierDescription(tier),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (tier == PromptTier.smallLocal)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade400),
                          const SizedBox(width: 4),
                          Text('Low quality', style: TextStyle(color: Colors.orange.shade400, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _tierName(PromptTier tier) {
    switch (tier) {
      case PromptTier.frontier: return 'Frontier API Models';
      case PromptTier.largLocal: return 'Large Local Models (70B+)';
      case PromptTier.smallLocal: return 'Small/Mid Local Models (7-34B)';
    }
  }

  String _tierDescription(PromptTier tier) {
    switch (tier) {
      case PromptTier.frontier: return 'GPT-4, Claude, Gemini -- best quality, requires internet';
      case PromptTier.largLocal: return 'Locally run large models -- good quality, fully offline';
      case PromptTier.smallLocal: return 'Locally run small/mid models -- fast but output may vary';
    }
  }

  Widget _buildToggleTile(String title, String subtitle, IconData icon, bool value, Color color, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? color.withValues(alpha: 0.5) : Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? color : Colors.white38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: color,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterPicker() {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select characters whose chat history to include:',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: charRepo.characters.where((c) => c.dbId != null).map((char) {
              final charDbId = char.dbId!;
              final isSelected = _selectedCharacterIds.contains(charDbId);
              return FilterChip(
                selected: isSelected,
                label: Text(char.name),
                selectedColor: Colors.blueAccent.withValues(alpha: 0.3),
                checkmarkColor: Colors.blueAccent,
                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12),
                backgroundColor: _bgDark,
                side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedCharacterIds.add(charDbId);
                      // Default first character to Protagonist
                      if (_selectedCharacterIds.length == 1) {
                        _characterRoles[charDbId] = 'Protagonist';
                      } else {
                        _characterRoles.putIfAbsent(charDbId, () => 'Supporting');
                      }
                    } else {
                      _selectedCharacterIds.remove(charDbId);
                      _characterRoles.remove(charDbId);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleAssignment() {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.theater_comedy, size: 16, color: Colors.purple.shade300),
              const SizedBox(width: 8),
              Text('Assign Roles', style: TextStyle(color: Colors.purple.shade200, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          ...charRepo.characters.where((c) => c.dbId != null && _selectedCharacterIds.contains(c.dbId)).map((char) {
            final charDbId = char.dbId!;
            final currentRole = _characterRoles[charDbId] ?? 'Supporting';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.purple.shade900.withValues(alpha: 0.4),
                    child: Text(char.name[0], style: TextStyle(color: Colors.purple.shade200, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(char.name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                  DropdownButton<String>(
                    value: currentRole,
                    dropdownColor: const Color(0xFF1E293B),
                    underline: Container(height: 1, color: Colors.white12),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    items: _roleOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) => setState(() => _characterRoles[charDbId] = v ?? 'Supporting'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUserPersonaToggle() {
    final personaService = Provider.of<UserPersonaService>(context, listen: false);
    final persona = personaService.persona;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _includeUserPersona ? Colors.amber.withValues(alpha: 0.4) : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_pin, size: 18, color: _includeUserPersona ? Colors.amber : Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Play as a character?',
                  style: TextStyle(color: _includeUserPersona ? Colors.amber : Colors.white60, fontSize: 13),
                ),
              ),
              Switch(
                value: _includeUserPersona,
                activeColor: Colors.amber,
                onChanged: (v) => setState(() => _includeUserPersona = v),
              ),
            ],
          ),
          if (_includeUserPersona) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.amber.shade900.withValues(alpha: 0.4),
                  child: Text(persona.name[0], style: TextStyle(color: Colors.amber.shade200, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(persona.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          if (persona.persona.isNotEmpty)
              Text(persona.persona, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: _userPersonaRole,
                  dropdownColor: const Color(0xFF1E293B),
                  underline: Container(height: 1, color: Colors.white12),
                  style: const TextStyle(color: Colors.amber, fontSize: 12),
                  items: _roleOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _userPersonaRole = v ?? 'Protagonist'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Match the same character ID format used by ChatService for RAG embeddings.
  String _getCharacterEmbedId(CharacterCard card) {
    if (card.imagePath != null) {
      return p.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  Future<void> _startGeneration() async {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) return;

    // Save all fields
    project.title = _titleController.text.trim().isEmpty ? 'Untitled Story' : _titleController.text.trim();
    project.concept = _conceptController.text.trim();
    project.promptTier = _selectedTier;
    project.useChatHistory = _useChatHistory;
    project.parallelGeneration = _parallelGeneration;
    project.chatHistoryCharacterIds = _selectedCharacterIds.toList();
    project.includeUserPersona = _includeUserPersona;
    project.userPersonaRole = _userPersonaRole;

    // Story customization
    project.pov = _pov;
    project.actCount = _actCount;
    project.selectedGenres = _selectedGenres.toList();
    project.selectedMoods = _selectedMoods.toList();
    project.writingStyle = _writingStyle;
    project.proseLength = _proseLength;
    project.narrativePace = _narrativePace;
    project.dialogueDensity = _dialogueDensity;
    project.maturityRating = _maturityRating;

    // Snapshot selected character card data with roles
    final snapshots = <Map<String, String>>[];
    if (_useChatHistory && _selectedCharacterIds.isNotEmpty) {
      for (final char in charRepo.characters) {
        if (char.dbId != null && _selectedCharacterIds.contains(char.dbId)) {
          snapshots.add({
            'name': char.name,
            'description': char.description,
            'personality': char.personality,
            'scenario': char.scenario,
            'first_message': char.firstMessage,
            'system_prompt': char.systemPrompt,
            'role': _characterRoles[char.dbId!] ?? 'Supporting',
          });
        }
      }
    }

    // Add user persona as a character snapshot if enabled
    if (_includeUserPersona) {
      final personaService = Provider.of<UserPersonaService>(context, listen: false);
      final persona = personaService.persona;
      snapshots.add({
        'name': persona.name,
          'personality': persona.persona,
        'scenario': '',
        'first_message': '',
        'system_prompt': '',
        'role': _userPersonaRole,
        'self_insert': 'true',
      });
    }

    project.characterCardSnapshots = snapshots;

    await repo.saveProject(project);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StoryDashboardPage(
            projectId: widget.projectId,
            autoRunStoryArchitect: true,
          ),
        ),
      );
    }
  }
}
