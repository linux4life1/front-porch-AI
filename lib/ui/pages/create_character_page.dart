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

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/providers/app_state.dart';

/// Manual character creator — 6-step wizard.
///
/// Step 0: Identity (avatar, name, tags)
/// Step 1: Personality (description, personality, scenario, advanced prompts)
/// Step 2: Dialogue (first message, alt greetings, example dialogues)
/// Step 3: Lorebook (CRUD)
/// Step 4: Realism Engine (initial state)
/// Step 5: Review & Save
class CreateCharacterPage extends StatefulWidget {
  const CreateCharacterPage({super.key});

  @override
  State<CreateCharacterPage> createState() => _CreateCharacterPageState();
}

class _CreateCharacterPageState extends State<CreateCharacterPage> {
  int _currentStep = 0;

  // ── Identity (Step 0) ──
  final _nameController = TextEditingController();
  Uint8List? _avatarBytes;
  final List<String> _tags = [];
  final _tagController = TextEditingController();

  // ── Personality (Step 1) ──
  final _descriptionController = TextEditingController();
  final _personalityController = TextEditingController();
  final _scenarioController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _postHistoryController = TextEditingController();

  // ── Dialogue (Step 2) ──
  final _firstMessageController = TextEditingController();
  final _exampleDialogueController = TextEditingController();
  final List<TextEditingController> _altGreetingControllers = [];

  // ── Lorebook (Step 3) ──
  final List<LorebookEntry> _lorebookEntries = [];

  // ── Expression Images (Step 5) ──
  final List<_ExpressionImageEntry> _expressionImages = [];
  Uint8List? _pendingExpressionBytes;
  bool _showingExpressionPicker = false;

  // ── Realism Engine (Step 4) ──
  bool _realismEnabled = false;
  String _realismTimeOfDay = 'morning';
  int _realismDayCount = 1;
  int _realismShortTermBond = 0;
  int _realismLongTermBond = 0;
  int _realismTrustLevel = 0;
  String _realismEmotion = '';
  String _realismEmotionIntensity = 'mild';
  bool _realismNsfwCooldown = false;
  bool _realismChaosMode = false;
  String _realismCurrentTask = '';

  // ── Token counter ──
  int _totalTokenEstimate = 0;

  @override
  void initState() {
    super.initState();
    // Listen to all text controllers for token counting
    for (final c in _allControllers) {
      c.addListener(_updateTokenEstimate);
    }
  }

  List<TextEditingController> get _allControllers => [
    _nameController,
    _descriptionController,
    _personalityController,
    _scenarioController,
    _systemPromptController,
    _postHistoryController,
    _firstMessageController,
    _exampleDialogueController,
    ..._altGreetingControllers,
  ];

  void _updateTokenEstimate() {
    int total = 0;
    for (final c in _allControllers) {
      // Rough estimate: ~4 chars per token
      total += (c.text.length / 4).ceil();
    }
    // Add lorebook entries
    for (final entry in _lorebookEntries) {
      total += ((entry.name.length + entry.key.length + entry.content.length) / 4).ceil();
    }
    if (mounted && total != _totalTokenEstimate) {
      setState(() => _totalTokenEstimate = total);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _systemPromptController.dispose();
    _postHistoryController.dispose();
    _firstMessageController.dispose();
    _exampleDialogueController.dispose();
    for (final c in _altGreetingControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Provider.of<AppState>(context, listen: false).setIndex(0),
        ),
        title: Row(
          children: [
            const Icon(Icons.person_add, color: Colors.blueAccent, size: 22),
            const SizedBox(width: 8),
            const Text('Create Character'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _currentStep == 0
                ? _buildIdentityStep()
                : _currentStep == 1
                    ? _buildPersonalityStep()
                    : _currentStep == 2
                        ? _buildDialogueStep()
                        : _currentStep == 3
                            ? _buildLorebookStep()
                            : _currentStep == 4
                                ? _buildRealismStep()
                                : _currentStep == 5
                                    ? _buildExpressionImagesStep()
                                    : _buildReviewStep(),
          ),
          // Floating token counter
          Positioned(
            right: 24,
            bottom: 24,
            child: _buildTokenBadge(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP INDICATOR
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(0, 'Identity'),
        _stepLine(),
        _stepDot(1, 'Personality'),
        _stepLine(),
        _stepDot(2, 'Dialogue'),
        _stepLine(),
        _stepDot(3, 'Lorebook'),
        _stepLine(),
        _stepDot(4, 'Realism'),
        _stepLine(),
        _stepDot(5, 'Expressions'),
        _stepLine(),
        _stepDot(6, 'Review'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.blueAccent : Colors.white12,
            border: isCurrent ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text('${step + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? Colors.white : Colors.white38,
                    )),
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
              fontSize: 10,
              color: isActive ? Colors.white70 : Colors.white30,
            )),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: Colors.white12,
    );
  }

  Widget _buildTokenBadge() {
    final color = _totalTokenEstimate > 4000
        ? Colors.redAccent
        : _totalTokenEstimate > 2000
            ? Colors.orangeAccent
            : Colors.blueAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.token, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '~$_totalTokenEstimate tokens',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  NAVIGATION BUTTONS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavButtons({
    required int currentStep,
    String? nextLabel,
    VoidCallback? onNext,
    bool showBack = true,
  }) {
    final labels = ['Personality', 'Dialogue', 'Lorebook', 'Realism Engine', 'Expression Images', 'Review & Save'];
    final nextText = nextLabel ?? (currentStep < labels.length ? 'Next: ${labels[currentStep]}' : 'Save');

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack && currentStep > 0)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep = currentStep - 1),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (showBack && currentStep > 0) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onNext ?? () {
                  // Validate on step 0 (name required)
                  if (currentStep == 0) {
                    if (_nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Character name is required'),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                  }
                  setState(() => _currentStep = currentStep + 1);
                },
                icon: Icon(currentStep >= 4 ? Icons.check : Icons.arrow_forward, size: 20),
                label: Text(nextText, style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 0: IDENTITY
  // ═══════════════════════════════════════════════════════════════

  Widget _buildIdentityStep() {
    return Center(
      key: const ValueKey('identity'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Character Identity',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set your character\'s name, avatar, and tags.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Avatar
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF1E293B),
                      border: Border.all(color: Colors.white12),
                      image: _avatarBytes != null
                          ? DecorationImage(
                              image: MemoryImage(_avatarBytes!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _avatarBytes == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                              const SizedBox(height: 8),
                              const Text('Click to add avatar',
                                  style: TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          )
                        : Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.camera_alt, size: 18, color: Colors.white70),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Name field
              _inputLabel('Character Name', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: _inputDecoration('Enter character name'),
              ),
              const SizedBox(height: 24),

              // Tags
              _inputLabel('Tags', required: false),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._tags.map((tag) => Chip(
                    label: Text(tag, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    backgroundColor: const Color(0xFF374151),
                    side: BorderSide.none,
                    deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white38),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                    visualDensity: VisualDensity.compact,
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDecoration('Add a tag...'),
                      onSubmitted: _addTag,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _addTag(_tagController.text),
                    icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                    tooltip: 'Add tag',
                  ),
                ],
              ),

              _buildNavButtons(currentStep: 0),
            ],
          ),
        ),
      ),
    );
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;

    final bytes = await File(result.files.single.path!).readAsBytes();
    if (!mounted) return;

    final cropped = await ImageCropDialog.show(context, imageBytes: bytes);
    if (cropped != null && mounted) {
      setState(() {
        _avatarBytes = cropped;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 1: PERSONALITY
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPersonalityStep() {
    return Center(
      key: const ValueKey('personality'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personality & World',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Define who your character is and the world they inhabit.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              _expandableField('Description', _descriptionController,
                  hint: 'Physical appearance, backstory, key traits...', maxLines: 4),
              const SizedBox(height: 20),

              _expandableField('Personality', _personalityController,
                  hint: 'How they act, speak, think...', maxLines: 3),
              const SizedBox(height: 20),

              _expandableField('Scenario', _scenarioController,
                  hint: 'The setting, situation, or context...', maxLines: 3),
              const SizedBox(height: 24),

              // Advanced Prompts (collapsed)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Row(
                    children: [
                      Icon(Icons.settings_suggest, size: 18, color: Colors.white38),
                      SizedBox(width: 8),
                      Text('Advanced Prompts (optional)',
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                  children: [
                    const SizedBox(height: 8),
                    _expandableField('System Prompt', _systemPromptController,
                        hint: 'Instructions for the AI about how to play this character...', maxLines: 4),
                    const SizedBox(height: 16),
                    _expandableField('Post-History Instructions', _postHistoryController,
                        hint: 'Injected after chat history, before AI response...', maxLines: 3),
                  ],
                ),
              ),

              _buildNavButtons(currentStep: 1),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2: DIALOGUE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDialogueStep() {
    return Center(
      key: const ValueKey('dialogue'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dialogue & Greetings',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configure the character\'s opening message and example dialogue.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              _expandableField('First Message', _firstMessageController,
                  hint: 'The character\'s opening message when a conversation starts...', maxLines: 6),
              const SizedBox(height: 24),

              // Alternate Greetings
              Row(
                children: [
                  _inputLabel('Alternate Greetings', required: false),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        final ctrl = TextEditingController();
                        ctrl.addListener(_updateTokenEstimate);
                        _altGreetingControllers.add(ctrl);
                      });
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Greeting'),
                    style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._altGreetingControllers.asMap().entries.map((entry) {
                final idx = entry.key;
                final ctrl = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _expandableField('Greeting ${idx + 1}', ctrl,
                            hint: 'Alternative opening message...', maxLines: 4),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _altGreetingControllers[idx].dispose();
                            _altGreetingControllers.removeAt(idx);
                          });
                        },
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                        tooltip: 'Remove greeting',
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              _expandableField('Example Dialogue', _exampleDialogueController,
                  hint: '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*', maxLines: 6),

              _buildNavButtons(currentStep: 2),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 3: LOREBOOK
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLorebookStep() {
    return Center(
      key: const ValueKey('lorebook'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lorebook',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Add world lore entries that inject context into conversations when keywords are detected.',
                          style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _addLorebookEntry,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_lorebookEntries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.menu_book_outlined, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        const Text('No lorebook entries yet',
                            style: TextStyle(color: Colors.white38, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text('Add entries to inject context-aware world lore into conversations.',
                            style: TextStyle(color: Colors.white24, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                ..._lorebookEntries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final lore = entry.value;
                  return _buildLorebookEntryCard(idx, lore);
                }),

              _buildNavButtons(currentStep: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLorebookEntryCard(int index, LorebookEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.constant
              ? Colors.amberAccent.withValues(alpha: 0.3)
              : Colors.blueAccent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.menu_book, size: 16,
                  color: entry.constant ? Colors.amberAccent : Colors.blueAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              if (entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Always Active',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _editLorebookEntry(index),
                icon: const Icon(Icons.edit, size: 16, color: Colors.white38),
                tooltip: 'Edit entry',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () => _deleteLorebookEntry(index),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                tooltip: 'Delete entry',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (!entry.constant && entry.key.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Keys: ${entry.key}',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
          ],
          if (entry.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.content.length > 120 ? '${entry.content.substring(0, 120)}...' : entry.content,
              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  void _addLorebookEntry() {
    _showLorebookEntryDialog(null);
  }

  void _editLorebookEntry(int index) {
    _showLorebookEntryDialog(index);
  }

  void _deleteLorebookEntry(int index) {
    setState(() {
      _lorebookEntries.removeAt(index);
      _updateTokenEstimate();
    });
  }

  void _showLorebookEntryDialog(int? editIndex) {
    final isEditing = editIndex != null;
    final entry = isEditing ? _lorebookEntries[editIndex] : LorebookEntry(key: '', content: '');

    final nameCtrl = TextEditingController(text: entry.name);
    final keyCtrl = TextEditingController(text: entry.key);
    final contentCtrl = TextEditingController(text: entry.content);
    bool constant = entry.constant;
    int stickyDepth = entry.stickyDepth;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isEditing ? 'Edit Lorebook Entry' : 'Add Lorebook Entry',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _inputDecoration('Entry name (display label)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyCtrl,
                    enabled: !constant,
                    style: TextStyle(color: constant ? Colors.white38 : Colors.white, fontSize: 14),
                    decoration: _inputDecoration('Keywords (comma-separated)'),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: TextField(
                      controller: contentCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: _inputDecoration('Lore content...'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: constant,
                        activeColor: Colors.amberAccent,
                        onChanged: (v) => setDialogState(() => constant = v ?? false),
                      ),
                      const Text('Always Active', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      if (!constant) ...[
                        const Text('Depth: ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        SizedBox(
                          width: 50,
                          child: TextField(
                            controller: TextEditingController(text: stickyDepth.toString()),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n >= 1) stickyDepth = n;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final newEntry = LorebookEntry(
                            name: nameCtrl.text.trim(),
                            key: keyCtrl.text.trim(),
                            content: contentCtrl.text.trim(),
                            constant: constant,
                            stickyDepth: stickyDepth,
                          );
                          setState(() {
                            if (isEditing) {
                              _lorebookEntries[editIndex] = newEntry;
                            } else {
                              _lorebookEntries.add(newEntry);
                            }
                            _updateTokenEstimate();
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        child: Text(isEditing ? 'Save' : 'Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 4: REALISM ENGINE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRealismStep() {
    return Center(
      key: const ValueKey('realism'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Realism Engine',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set the initial state for the Realism Engine when a new conversation starts. '
                'These values will seed the relationship, emotion, and time-of-day systems.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              RealismFormSection(
                enabled: _realismEnabled,
                onEnabledChanged: (v) => setState(() => _realismEnabled = v),
                timeOfDay: _realismTimeOfDay,
                onTimeOfDayChanged: (v) => setState(() => _realismTimeOfDay = v),
                dayCount: _realismDayCount,
                onDayCountChanged: (v) => setState(() => _realismDayCount = v),
                shortTermBond: _realismShortTermBond,
                onShortTermBondChanged: (v) => setState(() => _realismShortTermBond = v),
                longTermBond: _realismLongTermBond,
                onLongTermBondChanged: (v) => setState(() => _realismLongTermBond = v),
                trustLevel: _realismTrustLevel,
                onTrustLevelChanged: (v) => setState(() => _realismTrustLevel = v),
                emotion: _realismEmotion,
                onEmotionChanged: (v) => setState(() => _realismEmotion = v),
                emotionIntensity: _realismEmotionIntensity,
                onEmotionIntensityChanged: (v) => setState(() => _realismEmotionIntensity = v),
                nsfwCooldownEnabled: _realismNsfwCooldown,
                onNsfwCooldownChanged: (v) => setState(() => _realismNsfwCooldown = v),
                chaosModeEnabled: _realismChaosMode,
                onChaosModeChanged: (v) => setState(() => _realismChaosMode = v),
                currentTask: _realismCurrentTask,
                onCurrentTaskChanged: (v) => setState(() => _realismCurrentTask = v),
              ),

              _buildNavButtons(currentStep: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 5: EXPRESSION IMAGES
  // ═══════════════════════════════════════════════════════════════

  Widget _buildExpressionImagesStep() {
    return Center(
      key: const ValueKey('expressions'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Expression Images',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add sprite images for different emotions. These will be displayed during chat '
                'to reflect your character\'s mood. Optional — you can always add them later.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Add buttons
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickExpressionImage,
                      icon: const Icon(Icons.add_photo_alternate, size: 18),
                      label: const Text('Add Image'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
                        side: BorderSide(color: Colors.blueAccent, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _importExpressionZip,
                      icon: const Icon(Icons.folder_zip, size: 18),
                      label: const Text('Import ZIP'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purpleAccent,
                        side: BorderSide(color: Colors.purpleAccent, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Emotion picker (shown when user picked a file but hasn't assigned emotion)
              if (_showingExpressionPicker && _pendingExpressionBytes != null)
                _buildExpressionEmotionPicker(),

              // Expression grid
              if (_expressionImages.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _expressionImages.length,
                  itemBuilder: (context, index) {
                    final entry = _expressionImages[index];
                    final emoji = EmotionLabels.emoji[entry.emotion] ?? '';
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          children: [
                            SizedBox.expand(
                              child: Image.memory(
                                entry.bytes,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                  stops: const [0.4, 1.0],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _expressionImages.removeAt(index));
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              left: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      entry.emotion,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              // Empty state
              if (_expressionImages.isEmpty && !_showingExpressionPicker)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.mood, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text(
                          'No expression images added yet',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),

              _buildNavButtons(currentStep: 5),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick a file for expression image.
  Future<void> _pickExpressionImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    Uint8List bytes;
    if (result.files.first.bytes != null) {
      bytes = result.files.first.bytes!;
    } else if (result.files.first.path != null) {
      bytes = await File(result.files.first.path!).readAsBytes();
    } else {
      return;
    }

    if (mounted) {
      setState(() {
        _pendingExpressionBytes = bytes;
        _showingExpressionPicker = true;
      });
    }
  }

  /// Import a ZIP file containing expression images.
  Future<void> _importExpressionZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    Uint8List zipBytes;
    if (result.files.first.bytes != null) {
      zipBytes = result.files.first.bytes!;
    } else if (result.files.first.path != null) {
      zipBytes = await File(result.files.first.path!).readAsBytes();
    } else {
      return;
    }

    try {
      final zipDecoder = ZipDecoder();
      final archiveData = zipDecoder.decodeBytes(zipBytes);

      final imageExtensions = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};
      int imported = 0;
      int unrecognized = 0;

      for (final entry in archiveData) {
        if (!entry.isFile) continue;

        final ext = entry.name.split('.').last.toLowerCase();
        if (!imageExtensions.contains('.$ext')) continue;

        final nameWithoutExt = entry.name.replaceAll(RegExp(r'\.\w+$'), '');
        String? emotionLabel;

        for (final label in EmotionLabels.all) {
          if (nameWithoutExt.toLowerCase() == label ||
              nameWithoutExt.toLowerCase().startsWith('$label-') ||
              nameWithoutExt.toLowerCase().startsWith('$label.') ||
              nameWithoutExt.toLowerCase().startsWith('${label}_')) {
            emotionLabel = label;
            break;
          }
        }

        if (emotionLabel == null) {
          unrecognized++;
          continue;
        }

        final Uint8List? data = entry.content as Uint8List?;
        if (data == null) continue;

        _expressionImages.add(_ExpressionImageEntry(
          bytes: data,
          emotion: emotionLabel,
        ));
        imported++;
      }

      if (mounted) {
        setState(() {});
        String message = 'Imported $imported expression image(s).';
        if (unrecognized > 0) {
          message += ' $unrecognized unrecognized.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: imported > 0 ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import ZIP: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Inline emotion picker for the pending expression image.
  Widget _buildExpressionEmotionPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.memory(
                  _pendingExpressionBytes!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose emotion for this image',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          // Emotion grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: EmotionLabels.all.map((emotion) {
              final emoji = EmotionLabels.emoji[emotion] ?? '';
              return InkWell(
                onTap: () {
                  setState(() {
                    _expressionImages.add(_ExpressionImageEntry(
                      bytes: _pendingExpressionBytes!,
                      emotion: emotion,
                    ));
                    _pendingExpressionBytes = null;
                    _showingExpressionPicker = false;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        emotion,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _pendingExpressionBytes = null;
                  _showingExpressionPicker = false;
                });
              },
              style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.4)),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 6: REVIEW & SAVE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column — Avatar + quick info
          SizedBox(
            width: 280,
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF1E293B),
                    border: Border.all(color: Colors.white12),
                    image: _avatarBytes != null
                        ? DecorationImage(
                            image: MemoryImage(_avatarBytes!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _avatarBytes == null
                      ? Center(
                          child: Icon(Icons.person, size: 64, color: Colors.white.withValues(alpha: 0.15)),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  _nameController.text.isEmpty ? 'Unnamed' : _nameController.text,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Tags
                if (_tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: _tags.map((tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      backgroundColor: const Color(0xFF374151),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                const SizedBox(height: 16),
                // Realism Engine summary
                if (_realismEnabled)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.psychology, size: 14, color: Colors.blueAccent),
                            SizedBox(width: 6),
                            Text('Realism Engine', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Day $_realismDayCount · ${_realismTimeOfDay.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        if (_realismEmotion.isNotEmpty)
                          Text('Emotion: $_realismEmotion ($_realismEmotionIntensity)',
                              style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        Text('Bond: $_realismShortTermBond / $_realismLongTermBond · Trust: $_realismTrustLevel',
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveCharacter,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Character'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _currentStep = 0),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back to Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),

          // Right column — editable fields review
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review & Edit',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Review your character card. All fields are still editable before saving.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 24),
                _reviewField('Description', _descriptionController, maxLines: 4),
                _reviewField('Personality', _personalityController, maxLines: 3),
                _reviewField('Scenario', _scenarioController, maxLines: 3),
                _reviewField('First Message', _firstMessageController, maxLines: 5),
                if (_exampleDialogueController.text.isNotEmpty)
                  _reviewField('Example Dialogue', _exampleDialogueController, maxLines: 4),
                if (_systemPromptController.text.isNotEmpty)
                  _reviewField('System Prompt', _systemPromptController, maxLines: 3),
                if (_postHistoryController.text.isNotEmpty)
                  _reviewField('Post-History Instructions', _postHistoryController, maxLines: 3),

                // Alt greetings
                ..._altGreetingControllers.asMap().entries.map((entry) {
                  return _reviewField('Alt Greeting ${entry.key + 1}', entry.value, maxLines: 3);
                }),

                // Lorebook
                if (_lorebookEntries.isNotEmpty) ...[
                  const Divider(color: Colors.white12, height: 32),
                  Row(
                    children: [
                      const Icon(Icons.menu_book, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text('Lorebook Entries',
                          style: TextStyle(color: Colors.blueAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${_lorebookEntries.length} entries',
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._lorebookEntries.map((entry) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.displayName,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        if (entry.key.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Keys: ${entry.key}',
                              style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
                        ],
                        if (entry.content.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(entry.content,
                              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                        ],
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewField(String label, TextEditingController controller, {int maxLines = 3}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          AppTextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blueAccent),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SAVE
  // ═══════════════════════════════════════════════════════════════

  Future<void> _saveCharacter() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Character name is required'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    try {
      // Always build extensions — even when realism is disabled — so that
      // any configured values survive a round-trip through PNG save/load.
      // The realismEnabled flag controls whether the engine *uses* them at
      // runtime, not whether they are persisted.
      final fpExt = FrontPorchExtensions(
        realismEnabled: _realismEnabled,
        shortTermBond: _realismShortTermBond,
        longTermBond: _realismLongTermBond,
        trustLevel: _realismTrustLevel,
        dayCount: _realismDayCount,
        timeOfDay: _realismTimeOfDay,
        characterEmotion: _realismEmotion,
        emotionIntensity: _realismEmotionIntensity,
        nsfwCooldownEnabled: _realismNsfwCooldown,
        passageOfTimeEnabled: true, // default on; user can toggle later
        chaosModeEnabled: _realismChaosMode,
        currentTask: _realismCurrentTask,
      );

      final card = CharacterCard(
        name: name,
        description: _descriptionController.text,
        personality: _personalityController.text,
        scenario: _scenarioController.text,
        firstMessage: _firstMessageController.text,
        mesExample: _exampleDialogueController.text,
        systemPrompt: _systemPromptController.text,
        postHistoryInstructions: _postHistoryController.text,
        alternateGreetings: _altGreetingControllers
            .map((c) => c.text)
            .where((t) => t.trim().isNotEmpty)
            .toList(),
        tags: List.from(_tags),
        lorebook: _lorebookEntries.isNotEmpty
            ? Lorebook(entries: List.from(_lorebookEntries))
            : null,
        frontPorchExtensions: fpExt,
      );

      // Determine PNG path — always write a PNG so card data (including
      // Realism Engine extensions) can be embedded and survive app restarts.
      final charDir = storage.charactersDir;
      if (!charDir.existsSync()) charDir.createSync(recursive: true);
      final epoch = DateTime.now().millisecondsSinceEpoch;
      final safeName = name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');

      if (_avatarBytes != null) {
        // Write user-chosen avatar then overwrite tEXt chunk with card data
        await File(imagePath).writeAsBytes(_avatarBytes!);
      }
      // Always embed V2 card data (creates placeholder image if no avatar)
      card.imagePath = imagePath;
      final v2Service = V2CardService();
      await v2Service.saveCardAsPng(card, imagePath, _avatarBytes != null ? imagePath : null);
      debugPrint(
        '[CreateCharacter] Saved PNG with extensions: '
        'realism=${fpExt.realismEnabled}, bond=${fpExt.shortTermBond}, '
        'trust=${fpExt.trustLevel}, emotion=${fpExt.characterEmotion}',
      );

      // Add to repository
      await repo.addCharacter(card);

      // Save expression images
      if (_expressionImages.isNotEmpty) {
        final avatarDir = storage.characterAvatarDir(name);
        if (!await avatarDir.exists()) {
          await avatarDir.create(recursive: true);
        }
        for (final entry in _expressionImages) {
          final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}_${entry.emotion}.png';
          await File(p.join(avatarDir.path, filename)).writeAsBytes(entry.bytes);
          await repo.addAvatar(card.dbId!, name, entry.bytes, entry.emotion);
        }
        debugPrint('[CreateCharacter] Saved ${_expressionImages.length} expression images');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text('${card.name} created successfully!'),
              ],
            ),
            backgroundColor: const Color(0xFF2A2A2A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // CreateCharacterPage lives as a tab in MainLayout (not pushed as a
        // route), so Navigator.pop() would pop the entire scaffold → black
        // screen. Instead navigate back to the home tab and reset the form.
        Provider.of<AppState>(context, listen: false).setIndex(0);
        setState(() {
          _currentStep = 0;
          _nameController.clear();
          _descriptionController.clear();
          _personalityController.clear();
          _scenarioController.clear();
          _firstMessageController.clear();
          _exampleDialogueController.clear();
          _systemPromptController.clear();
          _postHistoryController.clear();
          for (final c in _altGreetingControllers) { c.dispose(); }
          _altGreetingControllers.clear();
          _lorebookEntries.clear();
          _avatarBytes = null;
          _tags.clear();
          _realismEnabled = false;
          _realismTimeOfDay = 'morning';
          _realismDayCount = 1;
          _realismShortTermBond = 0;
          _realismLongTermBond = 0;
          _realismTrustLevel = 0;
          _realismEmotion = '';
          _realismEmotionIntensity = 'mild';
          _realismNsfwCooldown = false;
          _realismChaosMode = false;
          _realismCurrentTask = '';
          _totalTokenEstimate = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save character: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════

  Widget _inputLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        if (required) const Text(' *', style: TextStyle(color: Colors.redAccent)),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }

  Widget _expandableField(String label, TextEditingController controller,
      {String hint = '', int maxLines = 3}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _inputLabel(label),
            const Spacer(),
            IconButton(
              onPressed: () => _openExpandedEditor(label, controller),
              icon: const Icon(Icons.open_in_full, size: 16, color: Colors.white38),
              tooltip: 'Expand editor',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
          spellCheckConfiguration: AppTextField.platformSpellCheck(),
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  Future<void> _openExpandedEditor(String label, TextEditingController controller) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final editController = TextEditingController(text: controller.text);
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 700,
            height: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AppTextField(
                    controller: editController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    spellCheckConfiguration: AppTextField.platformSpellCheck(),
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
                    decoration: _inputDecoration(''),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, editController.text),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null) {
      controller.text = result;
    }
  }
}

/// Holds a pending expression image with its assigned emotion label.
class _ExpressionImageEntry {
  final Uint8List bytes;
  final String emotion;

  _ExpressionImageEntry({
    required this.bytes,
    required this.emotion,
  });
}
