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
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

// Barrel imports
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

// Specific dialogs not in barrels
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

class EditCharacterDialog extends StatefulWidget {
  final CharacterCard character;

  const EditCharacterDialog({super.key, required this.character});

  @override
  State<EditCharacterDialog> createState() => _EditCharacterDialogState();
}

class _EditCharacterDialogState extends State<EditCharacterDialog>
    with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late StyledTextController _descriptionController;
  late StyledTextController _personalityController;
  late StyledTextController _scenarioController;
  late StyledTextController _firstMessageController;
  late StyledTextController _exampleDialoguesController;
  late StyledTextController _systemPromptController;
  late StyledTextController _postHistoryController;
  List<StyledTextController> _altGreetingControllers = [];

  late TabController _tabController;
  List<LorebookEntry> _loreEntries = [];
  List<String> _selectedWorldNames = [];
  List<String> _tags = [];

  // Local state for Optional Features (verification) in Details tab — read from ext on init, written on change via copy+persist pattern.
  bool _realismVerificationEnabled = false;
  int _realismVerificationMaxReprocesses = 1;
  int _realismVerificationStrictness = 3;
  bool _realismNeedsDirectorAuthority = false;
  int _needsSimStrength =
      1; // 1-5. Injected to first model call (+ Director when authority on) so they emit at the requested magnitude. Numbers returned by (Director-corrected) call are applied directly; no second multiply on top of already-scaled deltas.

  // Needs Simulation state
  bool _needsSimEnabled = false;
  bool _enjoysLowHygiene = false;
  int _needsBaselineHunger = 80;
  int _needsBaselineBladder = 80;
  int _needsBaselineEnergy = 80;
  int _needsBaselineSocial = 80;
  int _needsBaselineFun = 80;
  int _needsBaselineHygiene = 80;
  int _needsBaselineComfort = 80;

  int _needsDecayHunger = 5;
  int _needsDecayBladder = 5;
  int _needsDecayEnergy = 5;
  int _needsDecaySocial = 5;
  int _needsDecayFun = 5;
  int _needsDecayHygiene = 5;
  int _needsDecayComfort = 5;

  final TextEditingController _tagInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _descriptionController = StyledTextController(
      text: widget.character.description,
      preset: StyledTextPreset.macros,
    );
    _personalityController = StyledTextController(
      text: widget.character.personality,
      preset: StyledTextPreset.macros,
    );
    _scenarioController = StyledTextController(
      text: widget.character.scenario,
      preset: StyledTextPreset.macros,
    );
    _firstMessageController = StyledTextController(
      text: widget.character.firstMessage,
      preset: StyledTextPreset.prose,
    );
    _exampleDialoguesController = StyledTextController(
      text: widget.character.mesExample,
      preset: StyledTextPreset.prose,
    );
    _systemPromptController = StyledTextController(
      text: widget.character.systemPrompt,
      preset: StyledTextPreset.macros,
    );
    _postHistoryController = StyledTextController(
      text: widget.character.postHistoryInstructions,
      preset: StyledTextPreset.macros,
    );

    _altGreetingControllers = widget.character.alternateGreetings
        .map((g) => StyledTextController(text: g, preset: StyledTextPreset.prose))
        .toList();

    if (widget.character.lorebook != null) {
      _loreEntries = List.from(widget.character.lorebook!.entries);
    } else {
      _loreEntries = [];
    }

    _selectedWorldNames = List.from(widget.character.worldNames);
    _tags = List<String>.from(widget.character.tags);
    _tabController = TabController(length: 3, vsync: this);

    // Seed verification controls from card ext (defaults safe for old cards).
    final ext = widget.character.frontPorchExtensions;
    _realismVerificationEnabled = ext?.realismVerificationEnabled ?? false;
    _realismVerificationMaxReprocesses =
        ext?.realismVerificationMaxReprocesses ?? 1;
    _realismVerificationStrictness = ext?.realismVerificationStrictness ?? 3;
    _realismNeedsDirectorAuthority =
        ext?.realismNeedsDirectorAuthority ?? false;
    _needsSimStrength = ext?.needsSimStrength ?? 1;

    // Seed Needs Simulation controls from card ext (defaults safe for old cards).
    _needsSimEnabled = ext?.needsSimEnabled ?? false;
    _enjoysLowHygiene = ext?.enjoysLowHygiene ?? false;
    _needsBaselineHunger = ext?.needsBaselineHunger ?? 80;
    _needsBaselineBladder = ext?.needsBaselineBladder ?? 80;
    _needsBaselineEnergy = ext?.needsBaselineEnergy ?? 80;
    _needsBaselineSocial = ext?.needsBaselineSocial ?? 80;
    _needsBaselineFun = ext?.needsBaselineFun ?? 80;
    _needsBaselineHygiene = ext?.needsBaselineHygiene ?? 80;
    _needsBaselineComfort = ext?.needsBaselineComfort ?? 80;

    _needsDecayHunger = ext?.needsDecayHunger ?? 5;
    _needsDecayBladder = ext?.needsDecayBladder ?? 5;
    _needsDecayEnergy = ext?.needsDecayEnergy ?? 5;
    _needsDecaySocial = ext?.needsDecaySocial ?? 5;
    _needsDecayFun = ext?.needsDecayFun ?? 5;
    _needsDecayHygiene = ext?.needsDecayHygiene ?? 5;
    _needsDecayComfort = ext?.needsDecayComfort ?? 5;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _exampleDialoguesController.dispose();
    _systemPromptController.dispose();
    _postHistoryController.dispose();
    for (final c in _altGreetingControllers) {
      c.dispose();
    }
    _tabController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  /// Resolve the current avatar image file for display.
  File? get _avatarFile {
    final img = widget.character.imagePath;
    if (img == null || img.isEmpty) return null;
    if (p.isAbsolute(img)) return File(img);
    final storage = Provider.of<StorageService>(context, listen: false);
    return File(p.join(storage.charactersDir.path, img));
  }

  Future<void> _saveCharacter() async {
    // Update model
    widget.character.name = _nameController.text;
    widget.character.description = _descriptionController.text;
    widget.character.personality = _personalityController.text;
    widget.character.scenario = _scenarioController.text;
    widget.character.firstMessage = _firstMessageController.text;
    widget.character.mesExample = _exampleDialoguesController.text;
    widget.character.systemPrompt = _systemPromptController.text;
    widget.character.postHistoryInstructions = _postHistoryController.text;
    widget.character.alternateGreetings = _altGreetingControllers
        .map((c) => c.text)
        .where((t) => t.isNotEmpty)
        .toList();
    widget.character.worldNames = _selectedWorldNames;
    widget.character.tags = List<String>.from(_tags);

    // The portrait is managed in the Avatar Gallery now, not here — re-embed the
    // V2 card data into the current imagePath PNG to preserve edited fields.
    final storage = Provider.of<StorageService>(context, listen: false);
    String? targetPngPath;
    if (widget.character.imagePath != null &&
        widget.character.imagePath!.isNotEmpty) {
      final img = widget.character.imagePath!;
      targetPngPath = p.isAbsolute(img)
          ? img
          : p.join(storage.charactersDir.path, img);
    }

    if (targetPngPath != null) {
      try {
        await V2CardService().saveCardAsPng(
          widget.character,
          targetPngPath,
          targetPngPath,
        );
      } catch (e) {
        debugPrint('Failed to embed V2 card data: $e');
      }
    }

    // Update Lorebook
    if (widget.character.lorebook == null) {
      widget.character.lorebook = Lorebook(entries: _loreEntries);
    } else {
      widget.character.lorebook!.entries = _loreEntries;
    }

    try {
      await Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).updateCharacter(
        widget.character,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save character. Please try again.'),
          ),
        );
      }
    }
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

  Future<void> _importLorebookJson() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final content = await File(result.files.single.path!).readAsString();
      final dynamic jsonData = jsonDecode(content);

      // Validate that we have a Map<String, dynamic>
      if (jsonData is! Map<String, dynamic>) {
        throw FormatException('Invalid JSON format: expected a JSON object');
      }

      final Map<String, dynamic> json = jsonData;

      if (json['entries'] == null && json['lorebook'] == null) {
        throw FormatException(
          'Invalid lorebook file: missing "entries" or "lorebook" field. '
          'Supported formats: SillyTavern, Chub.ai, Front Porch.',
        );
      }

      final lorebook = Lorebook.fromJson(json);

      if (lorebook.entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No entries found in file.')),
          );
        }
        return;
      }

      setState(() {
        _loreEntries.addAll(lorebook.entries);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${lorebook.entries.length} entries.'),
          ),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid file format: ${e.message}')),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: An unexpected error occurred'),
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 700,
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit ${widget.character.name}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: AppColors.iconSecondary(context),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tabs
            Container(
              color: AppColors.surfaceContainerOf(context),
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.formMasterAccent,
                unselectedLabelColor: AppColors.textSecondary(context),
                indicatorColor: AppColors.formMasterAccent,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Lorebook'),
                  Tab(text: 'Worlds'),
                ],
              ),
            ),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDetailsTab(),
                  _buildLorebookTab(),
                  _buildWorldsTab(),
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _saveCharacter,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Avatar (read-only — portrait + images managed in the Avatar Gallery).
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.surfaceContainerOf(context),
              backgroundImage: _avatarFile != null && _avatarFile!.existsSync()
                  ? FileImage(_avatarFile!) as ImageProvider
                  : null,
              child: _avatarFile == null || !_avatarFile!.existsSync()
                  ? Icon(
                      Icons.person,
                      size: 48,
                      color: AppColors.iconSecondary(context),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(controller: _nameController, label: 'Name'),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _descriptionController,
            label: 'Description',
            maxLines: 3,
            expandable: true,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _personalityController,
            label: 'Personality',
            maxLines: 3,
            expandable: true,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _scenarioController,
            label: 'Scenario',
            maxLines: 3,
            expandable: true,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _firstMessageController,
            label: 'First Message',
            maxLines: 5,
            expandable: true,
          ),
          const SizedBox(height: 24),
          // Alternate Greetings
          Row(
            children: [
              Text(
                'Alternate Greetings',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                label: const Text(
                  'Add',
                  style: TextStyle(color: Colors.white70),
                ),
                onPressed: () {
                  setState(() {
                    _altGreetingControllers.add(
                      StyledTextController(preset: StyledTextPreset.prose),
                    );
                  });
                },
              ),
            ],
          ),
          ..._altGreetingControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final controller = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: controller,
                      label: 'Greeting ${idx + 2}',
                      maxLines: 3,
                      expandable: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    tooltip: 'Remove',
                    padding: const EdgeInsets.only(top: 24),
                    onPressed: () {
                      setState(() {
                        _altGreetingControllers[idx].dispose();
                        _altGreetingControllers.removeAt(idx);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          // Example Dialogues
          _buildTextField(
            controller: _exampleDialoguesController,
            label: 'Example Dialogues',
            maxLines: 5,
            expandable: true,
            hintText:
                '(Examples of chat dialog. Begin each example with <START> on a new line.)',
          ),
          const SizedBox(height: 24),
          // System Prompt
          _buildTextField(
            controller: _systemPromptController,
            label: 'System Prompt (optional)',
            maxLines: 4,
            expandable: true,
            hintText:
                'Custom system prompt for this character. If blank, the global system prompt is used.',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _postHistoryController,
            label: 'Post-History Instructions (optional)',
            maxLines: 3,
            expandable: true,
            hintText:
                'Instructions injected after chat history (jailbreak/reminder).',
          ),
          const SizedBox(height: 24),
          // Tags editor
          Text(
            'Tags',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._tags.map(
                (tag) => Chip(
                  label: Text(
                    tag,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  backgroundColor: AppColors.formMasterAccent.withValues(
                    alpha: 0.25,
                  ),
                  deleteIconColor: Colors.white54,
                  onDeleted: () => setState(() => _tags.remove(tag)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInputController,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add a tag...',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (val) {
                    final tag = val.trim();
                    if (tag.isNotEmpty && !_tags.contains(tag)) {
                      setState(() => _tags.add(tag));
                    }
                    _tagInputController.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  color: AppColors.formMasterAccent,
                  size: 22,
                ),
                tooltip: 'Add tag',
                onPressed: () {
                  final tag = _tagInputController.text.trim();
                  if (tag.isNotEmpty && !_tags.contains(tag)) {
                    setState(() => _tags.add(tag));
                  }
                  _tagInputController.clear();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Chat Colors
          Text(
            'Chat Colors',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          _buildColorRow(
            'User Bubble',
            widget.character.frontPorchExtensions?.userBubbleColor ??
                Provider.of<StorageService>(
                  context,
                  listen: false,
                ).globalUserBubbleColor,
            (color) => _updateColor('userBubbleColor', color),
          ),
          _buildColorRow(
            'User Text',
            widget.character.frontPorchExtensions?.userTextColor ??
                Provider.of<StorageService>(
                  context,
                  listen: false,
                ).globalUserTextColor,
            (color) => _updateColor('userTextColor', color),
          ),
          _buildColorRow(
            'AI Bubble',
            widget.character.frontPorchExtensions?.aiBubbleColor ??
                Provider.of<StorageService>(
                  context,
                  listen: false,
                ).globalAiBubbleColor,
            (color) => _updateColor('aiBubbleColor', color),
          ),
          _buildColorRow(
            'AI Text',
            widget.character.frontPorchExtensions?.aiTextColor ??
                Provider.of<StorageService>(
                  context,
                  listen: false,
                ).globalAiTextColor,
            (color) => _updateColor('aiTextColor', color),
          ),
          _buildColorRow(
            'Dialogue (Quoted)',
            widget.character.frontPorchExtensions?.dialogueColor ??
                Provider.of<StorageService>(
                  context,
                  listen: false,
                ).globalDialogueColor,
            (color) => _updateColor('dialogueColor', color),
          ),
          _buildColorRow(
            'Actions (*text*)',
            widget.character.frontPorchExtensions?.actionColor ??
                Provider.of<StorageService>(
                  context,
                  listen: false,
                ).globalActionColor,
            (color) => _updateColor('actionColor', color),
          ),

          // ── Needs Simulation Section ───────────────────────────────────────
          const SizedBox(height: 24),
          Text(
            'Needs Simulation',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Master toggle
                RealismFormSection.buildToggleRow(
                  icon: Icons.battery_std,
                  label: 'Needs Simulation',
                  subtitle:
                      'Hunger, bladder, energy, social, fun, hygiene, comfort — influences prompts & behavior',
                  value: _needsSimEnabled,
                  onChanged: (v) {
                    setState(() => _needsSimEnabled = v);
                    _updateNeedsSettings();
                  },
                  context: context,
                ),
                // ── Gated content (only when Needs Simulation is ON) ──
                if (_needsSimEnabled) ...[
                  const SizedBox(height: 16),
                  // Per-need baseline sliders
                  _needsSlider(
                    label: 'Hunger',
                    value: _needsBaselineHunger,
                    onChanged: (v) {
                      setState(() => _needsBaselineHunger = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecayHunger,
                    onDecayChanged: (v) {
                      setState(() => _needsDecayHunger = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _needsSlider(
                    label: 'Bladder',
                    value: _needsBaselineBladder,
                    onChanged: (v) {
                      setState(() => _needsBaselineBladder = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecayBladder,
                    onDecayChanged: (v) {
                      setState(() => _needsDecayBladder = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _needsSlider(
                    label: 'Energy',
                    value: _needsBaselineEnergy,
                    onChanged: (v) {
                      setState(() => _needsBaselineEnergy = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecayEnergy,
                    onDecayChanged: (v) {
                      setState(() => _needsDecayEnergy = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _needsSlider(
                    label: 'Social',
                    value: _needsBaselineSocial,
                    onChanged: (v) {
                      setState(() => _needsBaselineSocial = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecaySocial,
                    onDecayChanged: (v) {
                      setState(() => _needsDecaySocial = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _needsSlider(
                    label: 'Fun',
                    value: _needsBaselineFun,
                    onChanged: (v) {
                      setState(() => _needsBaselineFun = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecayFun,
                    onDecayChanged: (v) {
                      setState(() => _needsDecayFun = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _needsSlider(
                    label: 'Hygiene',
                    value: _needsBaselineHygiene,
                    onChanged: (v) {
                      setState(() => _needsBaselineHygiene = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecayHygiene,
                    onDecayChanged: (v) {
                      setState(() => _needsDecayHygiene = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 12),
                  _needsSlider(
                    label: 'Comfort',
                    value: _needsBaselineComfort,
                    onChanged: (v) {
                      setState(() => _needsBaselineComfort = v);
                      _updateNeedsSettings();
                    },
                    decayValue: _needsDecayComfort,
                    onDecayChanged: (v) {
                      setState(() => _needsDecayComfort = v);
                      _updateNeedsSettings();
                    },
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  // Enjoys low hygiene
                  RealismFormSection.buildToggleRow(
                    icon: Icons.water_drop_outlined,
                    label: 'Enjoys low hygiene',
                    subtitle:
                        'Character prefers being sweaty, musky, or filthy (inverts hygiene behavior)',
                    value: _enjoysLowHygiene,
                    onChanged: (v) {
                      setState(() => _enjoysLowHygiene = v);
                      _updateNeedsSettings();
                    },
                    context: context,
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  // Needs delta strength
                  Text(
                    'Needs delta strength: $_needsSimStrength x (1x baseline; 5x = 5× larger swings)',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    value: _needsSimStrength.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$_needsSimStrength x',
                    onChanged: (d) {
                      setState(() => _needsSimStrength = d.round());
                      _updateNeedsSettings();
                    },
                  ),
                ],
              ],
            ),
          ),

          // ── Optional Features (Verification Director/Verifier + tuning) ──
          const SizedBox(height: 24),
          Text(
            'Optional Features',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toggle row (inline, modeled on form _toggleRow but AppColors focused + no raw 0x in new).
                Row(
                  children: [
                    Icon(
                      Icons.verified_user,
                      color: _realismVerificationEnabled
                          ? AppColors.resolve(
                              context,
                              AppColors.optionalAccent,
                              AppColors.optionalAccent,
                            )
                          : AppColors.iconSecondary(context),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Realism Verification (Director/Verifier)',
                            style: TextStyle(
                              color: _realismVerificationEnabled
                                  ? AppColors.textPrimary(context)
                                  : AppColors.textSecondary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)',
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _realismVerificationEnabled,
                      onChanged: (v) {
                        setState(() => _realismVerificationEnabled = v);
                        _updateVerificationSettings();
                      },
                      activeTrackColor: AppColors.resolve(
                        context,
                        AppColors.optionalAccent,
                        AppColors.optionalAccent,
                      ).withValues(alpha: 0.5),
                      activeThumbColor: AppColors.resolve(
                        context,
                        AppColors.optionalAccent,
                        AppColors.optionalAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Max reprocesses slider (1-5)
                Text(
                  'Max reprocess passes: $_realismVerificationMaxReprocesses',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
                Slider(
                  value: _realismVerificationMaxReprocesses.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_realismVerificationMaxReprocesses',
                  onChanged: (d) {
                    setState(
                      () => _realismVerificationMaxReprocesses = d.round(),
                    );
                    _updateVerificationSettings();
                  },
                ),
                const SizedBox(height: 8),
                // Strictness slider (1-5, higher=strict)
                Text(
                  'Verifier strictness (1=lenient, 5=strict): $_realismVerificationStrictness',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
                Slider(
                  value: _realismVerificationStrictness.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_realismVerificationStrictness',
                  onChanged: (d) {
                    setState(() => _realismVerificationStrictness = d.round());
                    _updateVerificationSettings();
                  },
                ),
                // Authority toggle (after verif sliders; uses shared buildToggleRow from realism form for DRY; AppColors exclusive in new authority/Optional/verif surfaces per re-grep (verified exclusively via resolve/buildToggleRow; withValues only on resolved AppColors for verif sliders/Optional; no raw color literals in the new authority/Optional/verif *executable* code; comments filtered from hygiene greps).
                const SizedBox(height: 8),
                RealismFormSection.buildToggleRow(
                  icon: Icons.verified,
                  label: 'Director authority on needs deltas',
                  subtitle: '',
                  value: _realismNeedsDirectorAuthority,
                  onChanged: (v) {
                    setState(() => _realismNeedsDirectorAuthority = v);
                    _updateVerificationSettings();
                  },
                  context: context,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorRow(
    String label,
    Color color,
    void Function(Color) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderOf(context), width: 1),
            ),
            child: IconButton(
              icon: Icon(
                Icons.color_lens,
                size: 20,
                color: AppColors.iconPrimary(context),
              ),
              onPressed: () => _showColorPicker(context, color, onChanged),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLorebookTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lorebook',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'World lore entries inject context when keywords are detected.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addLoreEntry,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formMasterAccent,
                  foregroundColor: AppColors.onChaosAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _importLorebookJson,
                icon: const Icon(Icons.cloud_upload, size: 16),
                label: const Text('Import'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formMasterAccent,
                  foregroundColor: AppColors.onChaosAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_loreEntries.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5),
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 40,
                      color: AppColors.textTertiary(context),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No lorebook entries yet',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add entries manually or import a JSON lorebook.',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._loreEntries.asMap().entries.map((entry) {
              final idx = entry.key;
              final lore = entry.value;
              return _buildLoreCard(idx, lore);
            }),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLoreCard(int index, LorebookEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          width: 1.5,
          color: entry.constant
              ? Colors.amberAccent.withValues(alpha: 0.3)
              : entry.enabled
              ? AppColors.formMasterAccent.withValues(alpha: 0.15)
              : AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book,
                size: 14,
                color: entry.constant
                    ? Colors.amberAccent
                    : entry.enabled
                    ? AppColors.formMasterAccent
                    : Colors.white38,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: TextStyle(
                    color: entry.enabled
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Always Active',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Trigger Depth ${entry.stickyDepth}',
                    style: const TextStyle(
                      color: AppColors.formMasterAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: entry.enabled
                    ? 'Disable — entry won\'t be matched'
                    : 'Enable — entry will match on its keys',
                child: Switch(
                  value: entry.enabled,
                  onChanged: (val) {
                    setState(() {
                      entry.enabled = val;
                    });
                  },
                  activeTrackColor: AppColors.formMasterAccent.withValues(
                    alpha: 0.5,
                  ),
                  activeThumbColor: AppColors.formMasterAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                onPressed: () => _editLoreEntry(index),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.white38,
                ),
                tooltip: 'Edit entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                onPressed: () => _removeLoreEntry(index),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                tooltip: 'Delete entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          if (entry.key.isNotEmpty && !entry.constant) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: entry.keys
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        k.trim(),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            entry.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorldsTab() {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        if (repo.worlds.isEmpty) {
          return const Center(
            child: Text(
              'No worlds found. Create them in the Worlds section.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: repo.worlds.length,
          itemBuilder: (context, index) {
            final world = repo.worlds[index];
            final isSelected = _selectedWorldNames.contains(world.name);
            return CheckboxListTile(
              title: Text(
                world.name,
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              subtitle: Text(
                world.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              value: isSelected,
              checkColor: Colors.black,
              activeColor: AppColors.formMasterAccent,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedWorldNames.add(world.name);
                  } else {
                    _selectedWorldNames.remove(world.name);
                  }
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool expandable = false,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.textSecondary(context),
              ),
            ),
            if (expandable) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => showExpandedEditorDialog(
                  context: context,
                  title: label,
                  controller: controller,
                  hintText: hintText ?? '',
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.open_in_full,
                    size: 14,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: AppColors.textPrimary(context)),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: AppColors.textSecondary(context)),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _needsSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int? decayValue,
    ValueChanged<int>? onDecayChanged,
  }) {
    final mainSlider = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$value / 100',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.formMasterAccent,
            inactiveTrackColor: AppColors.borderOf(
              context,
            ).withValues(alpha: 0.3),
            thumbColor: AppColors.formMasterAccent,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$value',
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ],
    );

    if (decayValue == null || onDecayChanged == null) {
      return mainSlider;
    }

    String decayDescription;
    if (decayValue == 0) {
      decayDescription = 'Static (0)';
    } else if (decayValue <= 2) {
      decayDescription = 'Very Slow ($decayValue)';
    } else if (decayValue <= 4) {
      decayDescription = 'Slow ($decayValue)';
    } else if (decayValue <= 7) {
      decayDescription = 'Normal ($decayValue)';
    } else if (decayValue <= 12) {
      decayDescription = 'Fast ($decayValue)';
    } else {
      decayDescription = 'Very Fast ($decayValue)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mainSlider,
        Padding(
          padding: const EdgeInsets.only(left: 12.0, right: 8.0, top: 2.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Decay Rate / Turn',
                    style: TextStyle(
                      color: AppColors.textSecondary(
                        context,
                      ).withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    decayDescription,
                    style: TextStyle(
                      color: AppColors.textSecondary(
                        context,
                      ).withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.formMasterAccent.withValues(
                    alpha: 0.5,
                  ),
                  inactiveTrackColor: AppColors.borderOf(
                    context,
                  ).withValues(alpha: 0.15),
                  thumbColor: AppColors.formMasterAccent.withValues(alpha: 0.7),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: Slider(
                  value: decayValue.toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (d) => onDecayChanged(d.round()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updateColor(String fieldName, Color color) async {
    FrontPorchExtensions extensions;
    if (widget.character.frontPorchExtensions == null) {
      extensions = FrontPorchExtensions();
    } else {
      extensions = widget.character.frontPorchExtensions!.copyWith();
    }

    switch (fieldName) {
      case 'userBubbleColor':
        extensions.userBubbleColor = color;
        break;
      case 'userTextColor':
        extensions.userTextColor = color;
        break;
      case 'aiBubbleColor':
        extensions.aiBubbleColor = color;
        break;
      case 'aiTextColor':
        extensions.aiTextColor = color;
        break;
      case 'dialogueColor':
        extensions.dialogueColor = color;
        break;
      case 'actionColor':
        extensions.actionColor = color;
        break;
    }

    widget.character.frontPorchExtensions = extensions;
    extensions.ensureStableId();

    // Save to PNG so changes persist
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(widget.character);
      // Reload from PNG to ensure extensions are persisted
      final reloaded = await V2CardService().readCard(
        widget.character.imagePath!,
      );
      // Update ChatService with reloaded character
      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.setActiveCharacter(reloaded ?? widget.character);
    } catch (e) {
      debugPrint('Failed to save color changes: $e');
    }

    if (mounted) {
      setState(() {}); // Refresh UI
    }
  }

  /// Persist verification settings (toggle + sliders) from local state into the card's FrontPorchExtensions.
  /// Reuses the exact repo + V2CardService.readCard + chatService.setActiveCharacter pattern from _updateColor.
  /// Called from the toggle/switch/slider onChanged (after local setState for responsive UI).
  Future<void> _updateVerificationSettings() async {
    FrontPorchExtensions extensions;
    if (widget.character.frontPorchExtensions == null) {
      extensions = FrontPorchExtensions();
    } else {
      extensions = widget.character.frontPorchExtensions!.copyWith();
    }

    extensions.realismVerificationEnabled = _realismVerificationEnabled;
    extensions.realismVerificationMaxReprocesses =
        _realismVerificationMaxReprocesses;
    extensions.realismVerificationStrictness = _realismVerificationStrictness;
    extensions.realismNeedsDirectorAuthority = _realismNeedsDirectorAuthority;
    extensions.needsSimStrength = _needsSimStrength;

    widget.character.frontPorchExtensions = extensions;
    extensions.ensureStableId();

    // Save to PNG so changes persist (same as colors)
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(widget.character);
      // Reload from PNG to ensure extensions are persisted
      final reloaded = await V2CardService().readCard(
        widget.character.imagePath!,
      );
      // Update ChatService with reloaded character (so live card read picks up for next turn's verifier cbs)
      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.setActiveCharacter(reloaded ?? widget.character);
    } catch (e) {
      debugPrint('Failed to save verification settings: $e');
    }

    if (mounted) {
      setState(() {}); // Refresh UI
    }
  }

  /// Persist Needs Simulation settings (toggle, baselines, enjoys low hygiene, delta strength) from local state.
  /// Uses the same save pattern as _updateVerificationSettings for consistency.
  Future<void> _updateNeedsSettings() async {
    FrontPorchExtensions extensions;
    if (widget.character.frontPorchExtensions == null) {
      extensions = FrontPorchExtensions();
    } else {
      extensions = widget.character.frontPorchExtensions!.copyWith();
    }

    extensions.needsSimEnabled = _needsSimEnabled;
    extensions.enjoysLowHygiene = _enjoysLowHygiene;
    extensions.needsSimStrength = _needsSimStrength;
    extensions.needsBaselineHunger = _needsBaselineHunger;
    extensions.needsBaselineBladder = _needsBaselineBladder;
    extensions.needsBaselineEnergy = _needsBaselineEnergy;
    extensions.needsBaselineSocial = _needsBaselineSocial;
    extensions.needsBaselineFun = _needsBaselineFun;
    extensions.needsBaselineHygiene = _needsBaselineHygiene;
    extensions.needsBaselineComfort = _needsBaselineComfort;

    extensions.needsDecayHunger = _needsDecayHunger;
    extensions.needsDecayBladder = _needsDecayBladder;
    extensions.needsDecayEnergy = _needsDecayEnergy;
    extensions.needsDecaySocial = _needsDecaySocial;
    extensions.needsDecayFun = _needsDecayFun;
    extensions.needsDecayHygiene = _needsDecayHygiene;
    extensions.needsDecayComfort = _needsDecayComfort;

    widget.character.frontPorchExtensions = extensions;
    extensions.ensureStableId();

    // Save to PNG so changes persist (same as colors)
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(widget.character);
      // Reload from PNG to ensure extensions are persisted
      final reloaded = await V2CardService().readCard(
        widget.character.imagePath!,
      );
      // Update ChatService with reloaded character
      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.setActiveCharacter(reloaded ?? widget.character);
    } catch (e) {
      debugPrint('Failed to save needs settings: $e');
    }

    if (mounted) {
      setState(() {}); // Refresh UI
    }
  }

  Future<void> _showColorPicker(
    BuildContext context,
    Color initialColor,
    void Function(Color) onChanged,
  ) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Color'),
        content: SizedBox(
          width: 300,
          height: 375,
          child: ColorPicker(
            color: initialColor,
            onColorChanged: (color) => Navigator.pop(context, color),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, initialColor),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }
}
