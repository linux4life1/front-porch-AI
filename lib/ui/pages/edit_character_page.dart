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
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/ui/dialogs/character_avatars_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

// ═══════════════════════════════════════════════════════════════
//  DESIGN TOKENS — Slate / Indigo dark theme
// ═══════════════════════════════════════════════════════════════

const _bgDeep = Color(0xFF0F172A);
const _bgSurface = Color(0xFF1E293B);
const _bgInput = Color(0xFF0F172A);
const _borderSubtle = Color(0x14FFFFFF); // white 8%
const _borderFocus = Colors.blueAccent;

class EditCharacterPage extends StatefulWidget {
  final CharacterCard character;

  const EditCharacterPage({super.key, required this.character});

  @override
  State<EditCharacterPage> createState() => _EditCharacterPageState();
}

class _EditCharacterPageState extends State<EditCharacterPage>
    with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _personalityController;
  late TextEditingController _scenarioController;
  late TextEditingController _firstMessageController;
  late TextEditingController _mesExampleController;
  late TextEditingController _systemPromptController;
  late TextEditingController _postHistoryController;

  late TabController _tabController;
  List<LorebookEntry> _loreEntries = [];
  List<String> _selectedWorldNames = [];
  List<TextEditingController> _altGreetingControllers = [];
  List<String> _tags = [];
  final _tagController = TextEditingController();
  int _estimatedTokens = 0;
  String? _newAvatarPath;

  // ── Realism Engine state ──
  bool _realismEnabled = false;
  bool _realismSettingsModified = false;
  String _realismTimeOfDay = 'morning';
  int _realismDayCount = 1;
  int _realismShortTermBond = 0;
  int _realismLongTermBond = 0;
  int _realismTrustLevel = 0;
  String _realismEmotion = '';
  String _realismEmotionIntensity = 'mild';
  bool _realismNsfwCooldown = false;
  bool _realismPassageOfTime = true;
  bool _realismChaosMode = false;
  String _realismCurrentTask = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _descriptionController = TextEditingController(
      text: widget.character.description,
    );
    _personalityController = TextEditingController(
      text: widget.character.personality,
    );
    _scenarioController = TextEditingController(
      text: widget.character.scenario,
    );
    _firstMessageController = TextEditingController(
      text: widget.character.firstMessage,
    );
    _mesExampleController = TextEditingController(
      text: widget.character.mesExample,
    );
    _systemPromptController = TextEditingController(
      text: widget.character.systemPrompt,
    );
    _postHistoryController = TextEditingController(
      text: widget.character.postHistoryInstructions,
    );

    if (widget.character.lorebook != null) {
      _loreEntries = List.from(widget.character.lorebook!.entries);
    } else {
      widget.character.lorebook = Lorebook(entries: []);
      _loreEntries = widget.character.lorebook!.entries;
    }

    _selectedWorldNames = List.from(widget.character.worldNames);

    _altGreetingControllers = widget.character.alternateGreetings
        .map((g) => TextEditingController(text: g))
        .toList();

    _tags = List.from(widget.character.tags);

    // Seed realism state from existing extensions (or keep defaults)
    final ext = widget.character.frontPorchExtensions;
    if (ext != null) {
      _realismEnabled = ext.realismEnabled;
      _realismTimeOfDay = ext.timeOfDay;
      _realismDayCount = ext.dayCount;
      _realismShortTermBond = ext.shortTermBond;
      _realismLongTermBond = ext.longTermBond;
      _realismTrustLevel = ext.trustLevel;
      _realismEmotion = ext.characterEmotion;
      _realismEmotionIntensity = ext.emotionIntensity;
      _realismNsfwCooldown = ext.nsfwCooldownEnabled;
      _realismPassageOfTime = ext.passageOfTimeEnabled;
      _realismChaosMode = ext.chaosModeEnabled;
      _realismCurrentTask = ext.currentTask;
    }

    _tabController = TabController(length: 4, vsync: this);

    // Listen for token count updates
    for (final c in [
      _nameController,
      _descriptionController,
      _personalityController,
      _scenarioController,
      _firstMessageController,
      _mesExampleController,
      _systemPromptController,
      _postHistoryController,
    ]) {
      c.addListener(_updateTokenCount);
    }
    for (final c in _altGreetingControllers) {
      c.addListener(_updateTokenCount);
    }
    _updateTokenCount();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _mesExampleController.dispose();
    _systemPromptController.dispose();
    _postHistoryController.dispose();
    for (final c in _altGreetingControllers) {
      c.dispose();
    }
    _tagController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOKEN COUNTER
  // ═══════════════════════════════════════════════════════════════

  void _updateTokenCount() {
    int totalChars =
        _nameController.text.length +
        _descriptionController.text.length +
        _personalityController.text.length +
        _scenarioController.text.length +
        _firstMessageController.text.length +
        _mesExampleController.text.length +
        _systemPromptController.text.length +
        _postHistoryController.text.length;
    for (final c in _altGreetingControllers) {
      totalChars += c.text.length;
    }
    setState(() {
      _estimatedTokens = (totalChars / 4).ceil();
    });
  }

  Color _tokenColor() {
    if (_estimatedTokens > 4000) return Colors.redAccent;
    if (_estimatedTokens > 2000) return Colors.orangeAccent;
    return Colors.blueAccent;
  }

  // ═══════════════════════════════════════════════════════════════
  //  AVATAR
  // ═══════════════════════════════════════════════════════════════

  File? get _avatarFile {
    if (_newAvatarPath != null) return File(_newAvatarPath!);
    final img = widget.character.imagePath;
    if (img == null || img.isEmpty) return null;
    if (p.isAbsolute(img)) return File(img);
    final storage = Provider.of<StorageService>(context, listen: false);
    return File(p.join(storage.charactersDir.path, img));
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final pickedPath = result.files.single.path;
    if (pickedPath == null) return;

    final imageBytes = await File(pickedPath).readAsBytes();
    if (!mounted) return;

    final croppedBytes = await ImageCropDialog.show(
      context,
      imageBytes: imageBytes,
    );
    if (croppedBytes == null || !mounted) return;

    final storage = Provider.of<StorageService>(context, listen: false);
    final charDir = storage.charactersDir;
    await charDir.create(recursive: true);

    final safeName = _nameController.text.trim().isNotEmpty
        ? _nameController.text
              .trim()
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
  }

  // ═══════════════════════════════════════════════════════════════
  //  EXPANDED EDITOR DIALOG
  // ═══════════════════════════════════════════════════════════════

  void _openExpandedEditor(String title, TextEditingController controller) {
    final expandedController = TextEditingController(text: controller.text);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: _bgDeep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: _bgSurface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_note,
                      color: Colors.white70,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Apply'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () {
                        controller.text = expandedController.text;
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              // Editor body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppTextField(
                    controller: expandedController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter $title...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: _bgSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _borderFocus),
                      ),
                      contentPadding: const EdgeInsets.all(16),
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

  // ═══════════════════════════════════════════════════════════════
  //  SAVE
  // ═══════════════════════════════════════════════════════════════

  Future<void> _saveCharacter() async {
    // Update model
    widget.character.name = _nameController.text;
    widget.character.description = _descriptionController.text;
    widget.character.personality = _personalityController.text;
    widget.character.scenario = _scenarioController.text;
    widget.character.firstMessage = _firstMessageController.text;
    widget.character.mesExample = _mesExampleController.text;
    widget.character.systemPrompt = _systemPromptController.text;
    widget.character.postHistoryInstructions = _postHistoryController.text;
    widget.character.alternateGreetings = _altGreetingControllers
        .map((c) => c.text)
        .where((t) => t.isNotEmpty)
        .toList();
    widget.character.tags = List.from(_tags);
    widget.character.worldNames = _selectedWorldNames;

    // Always persist extensions — even when realism is disabled — so that
    // configured-but-disabled values survive the PNG round-trip.
    if (_realismEnabled ||
        _realismSettingsModified ||
        widget.character.frontPorchExtensions != null) {
      debugPrint(
        '[_saveCharacter] Saving realism: enabled=$_realismEnabled, modified=$_realismSettingsModified',
      );
      widget.character.frontPorchExtensions = FrontPorchExtensions(
        realismEnabled: _realismEnabled,
        shortTermBond: _realismShortTermBond,
        longTermBond: _realismLongTermBond,
        trustLevel: _realismTrustLevel,
        dayCount: _realismDayCount,
        timeOfDay: _realismTimeOfDay,
        characterEmotion: _realismEmotion,
        emotionIntensity: _realismEmotionIntensity,
        nsfwCooldownEnabled: _realismNsfwCooldown,
        passageOfTimeEnabled: _realismPassageOfTime,
        chaosModeEnabled: _realismChaosMode,
        currentTask: _realismCurrentTask,
      );
    }

    // Update avatar if changed
    if (_newAvatarPath != null) {
      widget.character.imagePath = p.basename(_newAvatarPath!);
    }

    // Always embed V2 card data into the PNG to preserve extensions
    final storage = Provider.of<StorageService>(context, listen: false);
    String? targetPngPath = _newAvatarPath;
    if (targetPngPath == null &&
        widget.character.imagePath != null &&
        widget.character.imagePath!.isNotEmpty) {
      final img = widget.character.imagePath!;
      targetPngPath = p.isAbsolute(img)
          ? img
          : p.join(storage.charactersDir.path, img);
    }

    if (targetPngPath != null) {
      try {
        debugPrint(
          '[_saveCharacter] About to save PNG with extensions: ${widget.character.frontPorchExtensions != null}',
        );
        await V2CardService().saveCardAsPng(
          widget.character,
          targetPngPath,
          targetPngPath,
        );
        debugPrint(
          '[_saveCharacter] PNG saved successfully for ${widget.character.name} to $targetPngPath',
        );
        
        // Verify PNG was written by reading it back immediately
        try {
          final reloaded = await V2CardService().readCard(targetPngPath);
          if (reloaded?.frontPorchExtensions != null) {
            debugPrint(
              '[_saveCharacter] ✓ PNG verification successful: extensions found in saved file',
            );
          } else {
            debugPrint(
              '[_saveCharacter] ✗ PNG verification FAILED: no extensions in saved file!',
            );
          }
        } catch (verifyError) {
          debugPrint('[_saveCharacter] PNG verification read failed: $verifyError');
        }
      } catch (e) {
        debugPrint('Failed to embed V2 card data: $e');
      }
    } else {
      debugPrint(
        '[_saveCharacter] WARNING: targetPngPath is null, skipping PNG save!',
      );
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
        worldRepo: Provider.of<WorldRepository>(context, listen: false),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text('Character updated successfully!'),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating character: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  LOREBOOK CRUD
  // ═══════════════════════════════════════════════════════════════

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

  void _editLoreEntry(int index) {
    final entry = _loreEntries[index];
    final keyController = TextEditingController(text: entry.key);
    final contentController = TextEditingController(text: entry.content);
    bool isConstant = entry.constant;
    int stickyDepth = entry.stickyDepth;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: _bgDeep,
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
                  // Always Active toggle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isConstant
                            ? Colors.amberAccent.withValues(alpha: 0.3)
                            : _borderSubtle,
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
                  _styledField(
                    controller: keyController,
                    label: isConstant
                        ? 'Keywords (Disabled — Always Active)'
                        : 'Keywords (comma separated)',
                    enabled: !isConstant,
                  ),
                  const SizedBox(height: 12),
                  _styledField(
                    controller: contentController,
                    label: 'Content',
                    maxLines: 5,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Colors.white38),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    entry.key = keyController.text;
                    entry.content = contentController.text;
                    entry.constant = isConstant;
                    entry.stickyDepth = stickyDepth;
                  });
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
        },
      ),
    );
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
          SnackBar(content: Text('Imported ${lorebook.entries.length} entries.')),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid file format: ${e.message}')),
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed. Please try again.')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD — MAIN SCAFFOLD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      appBar: AppBar(
        backgroundColor: _bgSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: Colors.blueAccent, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Edit ${widget.character.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _saveCharacter,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.white38,
          indicatorColor: Colors.blueAccent,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
            Tab(
              icon: Icon(Icons.chat_bubble_outline, size: 18),
              text: 'Dialogue',
            ),
            Tab(
              icon: Icon(Icons.menu_book_outlined, size: 18),
              text: 'Lorebook',
            ),
            Tab(icon: Icon(Icons.public, size: 18), text: 'Worlds'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildDetailsTab(),
              _buildDialogueTab(),
              _buildLorebookTab(),
              _buildWorldsTab(),
            ],
          ),
          // Floating token counter
          Positioned(right: 24, bottom: 24, child: _buildTokenBadge()),
        ],
      ),
    );
  }

  Widget _buildTokenBadge() {
    final color = _tokenColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _bgSurface,
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
            '~$_estimatedTokens tokens',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 1: DETAILS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar Section ──
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Stack(
                      children: [
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: _bgSurface,
                            border: Border.all(color: _borderSubtle),
                            image:
                                _avatarFile != null && _avatarFile!.existsSync()
                                ? DecorationImage(
                                    image: FileImage(_avatarFile!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child:
                              (_avatarFile == null ||
                                  !_avatarFile!.existsSync())
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 56,
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'No avatar',
                                      style: TextStyle(
                                        color: Colors.white24,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _bgDeep, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Tap to change avatar',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final storage = Provider.of<StorageService>(
                      context,
                      listen: false,
                    );
                    final repo = Provider.of<CharacterRepository>(
                      context,
                      listen: false,
                    );
                    final result = await CharacterAvatarsDialog.show(
                      context: context,
                      character: widget.character,
                      repository: repo,
                      storage: storage,
                    );
                    if (result == true) {
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.mood, size: 18),
                  label: const Text('Expression Images'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Identity Section ──
              _sectionCard(
                icon: Icons.badge_outlined,
                title: 'Identity',
                color: Colors.blueAccent,
                children: [
                  _styledField(controller: _nameController, label: 'Name'),
                  const SizedBox(height: 16),
                  // Tags
                  _fieldLabel('Tags'),
                  const SizedBox(height: 8),
                  if (_tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags
                          .map(
                            (tag) => Chip(
                              label: Text(
                                tag,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: const Color(0xFF374151),
                              side: BorderSide.none,
                              deleteIcon: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white38,
                              ),
                              onDeleted: () =>
                                  setState(() => _tags.remove(tag)),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (_tags.isNotEmpty) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration('Add a tag...'),
                          onSubmitted: (value) {
                            final trimmed = value.trim().toLowerCase();
                            if (trimmed.isNotEmpty &&
                                !_tags.contains(trimmed)) {
                              setState(() {
                                _tags.add(trimmed);
                                _tagController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.blueAccent,
                        ),
                        tooltip: 'Add tag',
                        onPressed: () {
                          final trimmed = _tagController.text
                              .trim()
                              .toLowerCase();
                          if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
                            setState(() {
                              _tags.add(trimmed);
                              _tagController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Personality & World ──
              _sectionCard(
                icon: Icons.psychology_outlined,
                title: 'Personality & World',
                color: const Color(0xFF0EA5E9),
                children: [
                  _styledField(
                    controller: _descriptionController,
                    label: 'Description',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Physical appearance, backstory, key traits...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _personalityController,
                    label: 'Personality',
                    maxLines: 3,
                    expandable: true,
                    hint: 'How they act, speak, think...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                     controller: _scenarioController,
                     label: 'Scenario',
                     maxLines: 3,
                     expandable: true,
                     hint: 'The setting, situation, or context...',
                   ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Advanced Prompts ──
              _sectionCard(
                icon: Icons.settings_suggest_outlined,
                title: 'Advanced Prompts',
                color: Colors.white38,
                collapsed: true,
                children: [
                  _styledField(
                    controller: _systemPromptController,
                    label: 'System Prompt',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Custom system prompt for this character...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _postHistoryController,
                    label: 'Post-History Instructions',
                    maxLines: 3,
                    expandable: true,
                    hint: 'Injected after chat history (jailbreak/reminder)...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Realism Engine Summary ──
              _buildRealismSection(),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 2: DIALOGUE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDialogueTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── First Message ──
              _sectionCard(
                icon: Icons.chat_bubble_outline,
                title: 'First Message',
                color: Colors.blueAccent,
                children: [
                  _styledField(
                    controller: _firstMessageController,
                    label: 'Opening Message',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        'The character\'s opening line when a conversation starts...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Alternate Greetings ──
              _sectionCard(
                icon: Icons.swap_horiz,
                title: 'Alternate Greetings',
                color: const Color(0xFF0EA5E9),
                trailing: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      final c = TextEditingController();
                      c.addListener(_updateTokenCount);
                      _altGreetingControllers.add(c);
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blueAccent,
                  ),
                ),
                children: [
                  if (_altGreetingControllers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No alternate greetings yet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._altGreetingControllers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: idx < _altGreetingControllers.length - 1
                              ? 12
                              : 0,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _styledField(
                                controller: ctrl,
                                label: 'Greeting ${idx + 2}',
                                maxLines: 4,
                                expandable: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 26),
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _altGreetingControllers[idx].dispose();
                                    _altGreetingControllers.removeAt(idx);
                                  });
                                },
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                tooltip: 'Remove greeting',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 20),

              // ── Example Dialogue ──
              _sectionCard(
                icon: Icons.format_quote_outlined,
                title: 'Example Dialogue',
                color: const Color(0xFF10B981),
                children: [
                  _styledField(
                    controller: _mesExampleController,
                    label: 'Example Conversations',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
                  ),
                ],
              ),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 3: LOREBOOK
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLorebookTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lorebook',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'World lore entries inject context when keywords are detected.',
                          style: TextStyle(fontSize: 13, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _importLorebookJson,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: const Text('Import'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF374151),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addLoreEntry,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_loreEntries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No lorebook entries yet',
                          style: TextStyle(color: Colors.white38, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add entries to inject context-aware world lore.',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
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

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoreCard(int index, LorebookEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.constant
              ? Colors.amberAccent.withValues(alpha: 0.3)
              : Colors.blueAccent.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book,
                size: 16,
                color: entry.constant ? Colors.amberAccent : Colors.blueAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Always Active',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Depth ${entry.stickyDepth}',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _editLoreEntry(index),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.white38,
                ),
                tooltip: 'Edit entry',
                visualDensity: VisualDensity.compact,
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
              ),
            ],
          ),
          if (entry.key.isNotEmpty && !entry.constant) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: entry.key
                  .split(',')
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        k.trim(),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            entry.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 4: WORLDS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWorldsTab() {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Linked Worlds',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Attach worlds to include their lorebooks in this character\'s conversations.',
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                  const SizedBox(height: 20),

                  if (repo.worlds.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: _bgSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.public,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No worlds found',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create worlds in the Worlds section.',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...repo.worlds.map((world) {
                      final isLinked = _selectedWorldNames.contains(world.name);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: _bgSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLinked
                                ? Colors.blueAccent.withValues(alpha: 0.4)
                                : _borderSubtle,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isLinked
                                  ? Colors.blueAccent.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.public,
                              size: 20,
                              color: isLinked
                                  ? Colors.blueAccent
                                  : Colors.white38,
                            ),
                          ),
                          title: Text(
                            world.name,
                            style: TextStyle(
                              color: isLinked ? Colors.white : Colors.white70,
                              fontWeight: isLinked
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            world.description.isNotEmpty
                                ? world.description
                                : '${world.lorebook.entries.length} entries',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Switch(
                            value: isLinked,
                            onChanged: (val) {
                              setState(() {
                                if (val) {
                                  _selectedWorldNames.add(world.name);
                                } else {
                                  _selectedWorldNames.remove(world.name);
                                }
                              });
                            },
                            activeTrackColor: Colors.blueAccent.withValues(
                              alpha: 0.5,
                            ),
                            activeThumbColor: Colors.blueAccent,
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  REALISM ENGINE SUMMARY (read-only)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRealismSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playful disclaimer note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('😉', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These settings only affect new conversations with this character — '
                  'your existing chats won\'t be changed. No cheating with the relationship values!',
                  style: TextStyle(
                    color: Colors.blueAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Full editable Realism Engine form
        RealismFormSection(
          enabled: _realismEnabled,
          onEnabledChanged: (v) => setState(() {
            _realismEnabled = v;
            _realismSettingsModified = true;
          }),
          timeOfDay: _realismTimeOfDay,
          onTimeOfDayChanged: (v) => setState(() {
            _realismTimeOfDay = v;
            _realismSettingsModified = true;
          }),
          dayCount: _realismDayCount,
          onDayCountChanged: (v) => setState(() {
            _realismDayCount = v;
            _realismSettingsModified = true;
          }),
          shortTermBond: _realismShortTermBond,
          onShortTermBondChanged: (v) => setState(() {
            _realismShortTermBond = v;
            _realismSettingsModified = true;
          }),
          longTermBond: _realismLongTermBond,
          onLongTermBondChanged: (v) => setState(() {
            _realismLongTermBond = v;
            _realismSettingsModified = true;
          }),
          trustLevel: _realismTrustLevel,
          onTrustLevelChanged: (v) => setState(() {
            _realismTrustLevel = v;
            _realismSettingsModified = true;
          }),
          emotion: _realismEmotion,
          onEmotionChanged: (v) => setState(() {
            _realismEmotion = v;
            _realismSettingsModified = true;
          }),
          emotionIntensity: _realismEmotionIntensity,
          onEmotionIntensityChanged: (v) => setState(() {
            _realismEmotionIntensity = v;
            _realismSettingsModified = true;
          }),
          nsfwCooldownEnabled: _realismNsfwCooldown,
          onNsfwCooldownChanged: (v) => setState(() {
            _realismNsfwCooldown = v;
            _realismSettingsModified = true;
          }),
          chaosModeEnabled: _realismChaosMode,
          onChaosModeChanged: (v) => setState(() {
            _realismChaosMode = v;
            _realismSettingsModified = true;
          }),
          currentTask: _realismCurrentTask,
          onCurrentTaskChanged: (v) => setState(() {
            _realismCurrentTask = v;
            _realismSettingsModified = true;
          }),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════

  /// Glassmorphic section card with icon header.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
    Widget? trailing,
    bool collapsed = false,
  }) {
    final header = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );

    if (collapsed) {
      return Container(
        decoration: BoxDecoration(
          color: _bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderSubtle),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: Colors.white38,
            collapsedIconColor: Colors.white24,
            children: children,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 16), ...children],
      ),
    );
  }

  /// Styled text field matching the manual creator design.
  Widget _styledField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool expandable = false,
    bool enabled = true,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel(label),
            if (expandable) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _openExpandedEditor(label, controller),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Tooltip(
                    message: 'Open fullscreen editor',
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          enabled: enabled,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white38,
            fontSize: 14,
          ),
          decoration: _inputDecoration(hint ?? 'Enter $label...'),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      filled: true,
      fillColor: _bgInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderFocus),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }
}
