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
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

class EditCharacterDialog extends StatefulWidget {
  final CharacterCard character;

  const EditCharacterDialog({super.key, required this.character});

  @override
  State<EditCharacterDialog> createState() => _EditCharacterDialogState();
}

class _EditCharacterDialogState extends State<EditCharacterDialog> with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _personalityController;
  late TextEditingController _scenarioController;
  late TextEditingController _firstMessageController;
  late TextEditingController _exampleDialoguesController;
  late TextEditingController _systemPromptController;
  late TextEditingController _postHistoryController;
  List<TextEditingController> _altGreetingControllers = [];

  late TabController _tabController;
  List<LorebookEntry> _loreEntries = [];
  List<String> _selectedWorldNames = [];
  List<String> _tags = [];
  final TextEditingController _tagInputController = TextEditingController();
  String? _newAvatarPath; // full path of newly picked avatar (null = no change)

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _descriptionController = TextEditingController(text: widget.character.description);
    _personalityController = TextEditingController(text: widget.character.personality);
    _scenarioController = TextEditingController(text: widget.character.scenario);
  _firstMessageController = TextEditingController(text: widget.character.firstMessage);
  _exampleDialoguesController = TextEditingController(text: widget.character.mesExample);
  _systemPromptController = TextEditingController(text: widget.character.systemPrompt);
  _postHistoryController = TextEditingController(text: widget.character.postHistoryInstructions);

    _altGreetingControllers = widget.character.alternateGreetings
        .map((g) => TextEditingController(text: g))
        .toList();

    if (widget.character.lorebook != null) {
      _loreEntries = List.from(widget.character.lorebook!.entries);
    } else {
       _loreEntries = [];
    }

    _selectedWorldNames = List.from(widget.character.worldNames);
    _tags = List<String>.from(widget.character.tags);
    _tabController = TabController(length: 3, vsync: this);
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
    // If user picked a new avatar, show that
    if (_newAvatarPath != null) return File(_newAvatarPath!);
    // Otherwise resolve the character's stored path
    final img = widget.character.imagePath;
    if (img == null || img.isEmpty) return null;
    if (p.isAbsolute(img)) return File(img);
    final storage = Provider.of<StorageService>(context, listen: false);
    return File(p.join(storage.charactersDir.path, img));
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final pickedPath = result.files.single.path;
      if (pickedPath == null) return;

      final imageBytes = await File(pickedPath).readAsBytes();
      if (!mounted) return;

      // Show the crop dialog
      final croppedBytes = await ImageCropDialog.show(
        context,
        imageBytes: imageBytes,
      );
      if (croppedBytes == null || !mounted) return;

      // Save cropped image to charactersDir with a timestamped name
      final storage = Provider.of<StorageService>(context, listen: false);
      final charDir = storage.charactersDir;
      await charDir.create(recursive: true);

      final safeName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
              .replaceAll(RegExp(r'[^\w\s-]'), '')
              .replaceAll(RegExp(r'\s+'), '_')
          : 'avatar';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destFilename = '${safeName}_$timestamp.png';
      final destPath = p.join(charDir.path, destFilename);

      await File(destPath).writeAsBytes(croppedBytes);

      setState(() {
        _newAvatarPath = destPath;
      });
    } catch (e) {
      debugPrint('File picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file picker. Please try again.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _openExpandedEditor(String title, TextEditingController controller, {String? hintText}) {
    final expandedController = TextEditingController(text: controller.text);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: Colors.white70, size: 22),
                    const SizedBox(width: 8),
                    Text(title, style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Done'),
                      style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
                      onPressed: () {
                        controller.text = expandedController.text;
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppTextField(
                    controller: expandedController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    // Update avatar if changed
    if (_newAvatarPath != null) {
      widget.character.imagePath = _newAvatarPath!;
    }

    // Always embed V2 card data into the PNG to preserve extensions
    final storage = Provider.of<StorageService>(context, listen: false);
    String? targetPngPath = _newAvatarPath;
    if (targetPngPath == null && widget.character.imagePath != null && widget.character.imagePath!.isNotEmpty) {
      final img = widget.character.imagePath!;
      targetPngPath = p.isAbsolute(img) ? img : p.join(storage.charactersDir.path, img);
    }

    if (targetPngPath != null) {
      try {
        await V2CardService().saveCardAsPng(widget.character, targetPngPath, targetPngPath);
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
      await Provider.of<CharacterRepository>(context, listen: false)
          .updateCharacter(
            widget.character,
            worldRepo: Provider.of<WorldRepository>(context, listen: false),
          );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save character. Please try again.')),
        );
      }
    }
  }

  void _addLoreEntry() {
    setState(() {
      _loreEntries.add(LorebookEntry(key: 'New Key', content: 'New Content'));
    });
  }

  void _removeLoreEntry(int index) {
    setState(() {
      _loreEntries.removeAt(index);
    });
  }

  Future<void> _importLorebookJson() async {
    final result = await FilePicker.platform.pickFiles(
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
      
      final Map<String, dynamic> json = jsonData as Map<String, dynamic>;

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
          SnackBar(content: Text('Imported ${lorebook.entries.length} entries.')),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid file format: ${e.message}')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: An unexpected error occurred')),
        );
      }
    }
  }

void _editLoreEntry(int index) {
  final entry = _loreEntries[index];
  final keyController = TextEditingController(text: entry.key);
  final contentController = TextEditingController(text: entry.content);
  final nameController = TextEditingController(text: entry.name);
  bool isConstant = entry.constant;
  int stickyDepth = entry.stickyDepth;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialog) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.menu_book, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Edit Lorebook Entry',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isConstant
                          ? Colors.amberAccent.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.push_pin,
                        size: 16,
                        color: isConstant
                            ? Colors.amberAccent
                            : Colors.white38,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Always Active',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Spacer(),
                      Switch(
                        value: isConstant,
                        onChanged: (val) =>
                            setStateDialog(() => isConstant = val),
                        activeTrackColor: Colors.amberAccent.withValues(
                          alpha: 0.5,
                        ),
                        activeThumbColor: Colors.amberAccent,
                      ),
                    ],
                  ),
                ),
                if (!isConstant) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.layers,
                        size: 14,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Trigger Depth: $stickyDepth ${stickyDepth == 1 ? "message" : "messages"}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.blueAccent,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.blueAccent,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: stickyDepth.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: stickyDepth.toString(),
                      onChanged: (val) =>
                          setStateDialog(() => stickyDepth = val.toInt()),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyController,
                  enabled: !isConstant,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: isConstant
                        ? 'Keywords (Disabled — Always Active)'
                        : 'Keywords (comma separated)',
                    filled: true,
                    fillColor: isConstant
                        ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                        : const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Content',
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                keyController.dispose();
                contentController.dispose();
                nameController.dispose();
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  entry.name = nameController.text;
                  entry.key = keyController.text;
                  entry.content = contentController.text;
                  entry.constant = isConstant;
                  entry.stickyDepth = stickyDepth;
                });
                keyController.dispose();
                contentController.dispose();
                nameController.dispose();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      }
    ),
  );
}

  @override
  Widget build(BuildContext context) {

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
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
               decoration: const BoxDecoration(
                 border: Border(bottom: BorderSide(color: Colors.white10)),
               ),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text('Edit ${widget.character.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                   IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                 ],
               ),
             ),
             
             // Tabs
             Container(
               color: const Color(0xFF111827),
               child: TabBar(
                 controller: _tabController,
                 labelColor: Colors.blueAccent,
                 unselectedLabelColor: Colors.white54,
                 indicatorColor: Colors.blueAccent,
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
               decoration: const BoxDecoration(
                 border: Border(top: BorderSide(color: Colors.white10)),
               ),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.end,
                 children: [
                   TextButton(
                     onPressed: () => Navigator.pop(context),
                     child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                   ),
                   const SizedBox(width: 16),
                   ElevatedButton.icon(
                     onPressed: _saveCharacter,
                     icon: const Icon(Icons.save),
                     label: const Text('Save Changes'),
                     style: ElevatedButton.styleFrom(
                       backgroundColor: Colors.blueAccent,
                       foregroundColor: Colors.white,
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
          // Avatar
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF374151),
                    backgroundImage: _avatarFile != null && _avatarFile!.existsSync()
                        ? FileImage(_avatarFile!) as ImageProvider
                        : null,
                     child: _avatarFile == null || !_avatarFile!.existsSync()
                         ? const Icon(Icons.person, size: 48, color: Colors.white54)
                         : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1F2937), width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
           Text(
             'Tap to change avatar',
             style: TextStyle(fontSize: 11, color: Colors.white54),
           ),
          const SizedBox(height: 16),
          _buildTextField(controller: _nameController, label: 'Name'),
          const SizedBox(height: 16),
          _buildTextField(controller: _descriptionController, label: 'Description', maxLines: 3, expandable: true),
          const SizedBox(height: 16),
          _buildTextField(controller: _personalityController, label: 'Personality', maxLines: 3, expandable: true),
          const SizedBox(height: 16),
          _buildTextField(controller: _scenarioController, label: 'Scenario', maxLines: 3, expandable: true),
          const SizedBox(height: 16),
          _buildTextField(controller: _firstMessageController, label: 'First Message', maxLines: 5, expandable: true),
          const SizedBox(height: 24),
          // Alternate Greetings
          Row(
            children: [
              const Text('Alternate Greetings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white70)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                label: const Text('Add', style: TextStyle(color: Colors.white70)),
                onPressed: () {
                  setState(() {
                    _altGreetingControllers.add(TextEditingController());
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
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
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
             hintText: '(Examples of chat dialog. Begin each example with <START> on a new line.)',
           ),
          const SizedBox(height: 24),
          // System Prompt
          _buildTextField(
            controller: _systemPromptController,
            label: 'System Prompt (optional)',
            maxLines: 4,
            expandable: true,
            hintText: 'Custom system prompt for this character. If blank, the global system prompt is used.',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _postHistoryController,
            label: 'Post-History Instructions (optional)',
            maxLines: 3,
            expandable: true,
            hintText: 'Instructions injected after chat history (jailbreak/reminder).',
          ),
          const SizedBox(height: 24),
          // Tags editor
          const Text('Tags', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._tags.map((tag) => Chip(
                label: Text(tag, style: const TextStyle(fontSize: 12, color: Colors.white)),
                backgroundColor: Colors.blueAccent.withValues(alpha: 0.25),
                deleteIconColor: Colors.white54,
                onDeleted: () => setState(() => _tags.remove(tag)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInputController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add a tag...',
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                icon: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 22),
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
          const Text('Chat Colors', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 8),
          _buildColorRow(
            'User Bubble',
            widget.character.frontPorchExtensions?.userBubbleColor ?? Provider.of<StorageService>(context, listen: false).globalUserBubbleColor,
            (color) => _updateColor('userBubbleColor', color),
          ),
          _buildColorRow(
            'User Text',
            widget.character.frontPorchExtensions?.userTextColor ?? Provider.of<StorageService>(context, listen: false).globalUserTextColor,
            (color) => _updateColor('userTextColor', color),
          ),
          _buildColorRow(
            'AI Bubble',
            widget.character.frontPorchExtensions?.aiBubbleColor ?? Provider.of<StorageService>(context, listen: false).globalAiBubbleColor,
            (color) => _updateColor('aiBubbleColor', color),
          ),
          _buildColorRow(
            'AI Text',
            widget.character.frontPorchExtensions?.aiTextColor ?? Provider.of<StorageService>(context, listen: false).globalAiTextColor,
            (color) => _updateColor('aiTextColor', color),
          ),
          _buildColorRow(
            'Dialogue (Quoted)',
            widget.character.frontPorchExtensions?.dialogueColor ?? Provider.of<StorageService>(context, listen: false).globalDialogueColor,
            (color) => _updateColor('dialogueColor', color),
          ),
          _buildColorRow(
            'Actions (*text*)',
            widget.character.frontPorchExtensions?.actionColor ?? Provider.of<StorageService>(context, listen: false).globalActionColor,
            (color) => _updateColor('actionColor', color),
          ),
        ],
      ),
    );
  }

  Widget _buildColorRow(String label, Color color, void Function(Color) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: IconButton(
              icon: const Icon(Icons.color_lens, size: 20, color: Colors.white),
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lorebook',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'World lore entries inject context when keywords are detected.',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addLoreEntry,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 40,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No lorebook entries yet',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Add entries manually or import a JSON lorebook.',
                      style: TextStyle(color: Colors.white24, fontSize: 11),
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.constant
              ? Colors.amberAccent.withValues(alpha: 0.3)
              : entry.enabled
                  ? Colors.blueAccent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
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
                        ? Colors.blueAccent
                        : Colors.white38,
              ),
              const SizedBox(width: 6),
              Expanded(
            child: Text(
              entry.displayName,
              style: TextStyle(
                color: entry.enabled ? Colors.white : Colors.white70,
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
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Trigger Depth ${entry.stickyDepth}',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: entry.enabled,
                onChanged: (val) {
                  setState(() {
                    entry.enabled = val;
                  });
                },
                activeTrackColor: Colors.blueAccent.withValues(alpha: 0.5),
                activeThumbColor: Colors.blueAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              children: entry.key
                  .split(',')
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
                color: Colors.white70,
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
          return const Center(child: Text('No worlds found. Create them in the Worlds section.', style: TextStyle(color: Colors.white54)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: repo.worlds.length,
          itemBuilder: (context, index) {
            final world = repo.worlds[index];
            final isSelected = _selectedWorldNames.contains(world.name);
            return CheckboxListTile(
              title: Text(world.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(world.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
              value: isSelected,
              checkColor: Colors.black,
              activeColor: Colors.blueAccent,
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.white54,
              ),
            ),
            if (expandable) ...[
              const SizedBox(width: 6),
            InkWell(
              onTap: () => _openExpandedEditor(label, controller, hintText: hintText),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.open_in_full, size: 14, color: Colors.white54),
              ),
            ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
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

    // Save to PNG so changes persist
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(widget.character);
      // Reload from PNG to ensure extensions are persisted
      final reloaded = await V2CardService().readCard(widget.character.imagePath!);
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
