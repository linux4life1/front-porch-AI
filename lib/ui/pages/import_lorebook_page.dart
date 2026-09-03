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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/models/lorebook_analysis.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'import_lorebook/import_destination_step.dart';
import 'import_lorebook/import_review_step.dart';

/// The one Import Lorebook flow: pick a file → review what was detected →
/// choose where it lives (World / character(s) / this group / this chat).
/// Follows the mandatory create-wizard chrome (step dots in the AppBar,
/// AnimatedSwitcher steps, bottom nav buttons) in warm-porch colors.
class ImportLorebookPage extends StatefulWidget {
  const ImportLorebookPage({super.key});

  @override
  State<ImportLorebookPage> createState() => _ImportLorebookPageState();
}

class _ImportLorebookPageState extends State<ImportLorebookPage> {
  int _currentStep = 0;

  String? _fileName;
  Lorebook? _book;
  LorebookImportSummary? _summary;
  String? _pickError;

  LoreImportDestination _destination = LoreImportDestination.world;
  final _worldNameCtrl = TextEditingController();
  final _worldDescCtrl = TextEditingController();
  final Set<String> _selectedCharacterIds = {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // The Import button's enabled state is computed from this field's text
    // (_canProceed), so the nav bar has to rebuild as it is typed in or
    // cleared — otherwise an emptied name leaves the button enabled.
    _worldNameCtrl.addListener(_onWorldNameChanged);
  }

  void _onWorldNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _worldNameCtrl.removeListener(_onWorldNameChanged);
    _worldNameCtrl.dispose();
    _worldDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final pickedName = result.files.single.name;
    try {
      final raw = jsonDecode(utf8.decode(await result.files.single.readAsBytes()));
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Not a JSON object');
      }
      final book = Lorebook.fromJson(raw);
      setState(() {
        _fileName = pickedName;
        _book = book;
        _summary = LorebookImportSummary.analyze(raw, book);
        _worldNameCtrl.text = _summary!.suggestedName;
        _worldDescCtrl.text = _summary!.suggestedDescription;
        _pickError = null;
        if (book.entries.isNotEmpty) _currentStep = 1;
      });
    } catch (e) {
      setState(() {
        _fileName = pickedName;
        _book = null;
        _summary = null;
        _pickError =
            'Could not read this file as a lorebook. Supported formats: '
            'SillyTavern, Chub, NovelAI, AgnAI, RisuAI, Front Porch.';
      });
    }
  }

  bool get _canProceed {
    if (_currentStep == 0) return _book != null && _book!.entries.isNotEmpty;
    if (_currentStep == 2) {
      return switch (_destination) {
        LoreImportDestination.world => _worldNameCtrl.text.trim().isNotEmpty,
        LoreImportDestination.characters => _selectedCharacterIds.isNotEmpty,
        _ => true,
      };
    }
    return true;
  }

  List<LorebookEntry> _clonedEntries() =>
      [for (final e in _book!.entries) e.clone()];

  Lorebook _clonedBook() => Lorebook(
        entries: _clonedEntries(),
        scanDepth: _book!.scanDepth,
        tokenBudget: _book!.tokenBudget,
        recursiveScanning: _book!.recursiveScanning,
        extensions: Map<String, dynamic>.from(_book!.extensions),
      );

  Future<void> _runImport() async {
    if (_importing) return;
    setState(() => _importing = true);
    final chat = Provider.of<ChatService>(context, listen: false);
    final worlds = Provider.of<WorldRepository>(context, listen: false);
    final chars = Provider.of<CharacterRepository>(context, listen: false);
    final groups = Provider.of<GroupChatRepository>(context, listen: false);

    String where;
    try {
      switch (_destination) {
        case LoreImportDestination.world:
          var name = _worldNameCtrl.text.trim();
          final taken = worlds.worlds.map((w) => w.name).toSet();
          var candidate = name;
          var i = 2;
          while (taken.contains(candidate)) {
            candidate = '$name ($i)';
            i++;
          }
          await worlds.saveWorld(World(
            name: candidate,
            description: _worldDescCtrl.text.trim(),
            lorebook: _clonedBook(),
          ));
          where = 'the world "$candidate"';
        case LoreImportDestination.characters:
          var count = 0;
          for (final c in chars.characters) {
            if (c.dbId == null || !_selectedCharacterIds.contains(c.dbId)) {
              continue;
            }
            final existing = c.lorebook;
            if (existing == null) {
              c.lorebook = _clonedBook();
            } else {
              existing.entries.addAll(_clonedEntries());
            }
            await chars.updateCharacter(c);
            count++;
          }
          where = '$count character${count == 1 ? '' : 's'}';
        case LoreImportDestination.group:
          final g = chat.activeGroup!;
          final existing = g.groupLorebook.isEmpty
              ? Lorebook(entries: [])
              : Lorebook.fromJson(
                  jsonDecode(g.groupLorebook) as Map<String, dynamic>,
                );
          existing.entries.addAll(_clonedEntries());
          g.groupLorebook = jsonEncode(existing.toJson());
          await groups.save(g);
          where = 'the group "${g.name}"';
        case LoreImportDestination.chat:
          chat.chatLorebook.entries.addAll(_clonedEntries());
          await chat.commitChatLorebookEdit();
          where = 'this chat';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${_book!.entries.length} entries into $where.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = Provider.of<ChatService>(context, listen: false);
    final honey = AppColors.porchHoneyOf(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.auto_stories, color: honey, size: 22),
            const SizedBox(width: 8),
            const Text('Import Lorebook'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _currentStep == 0
                  ? _buildPickStep()
                  : _currentStep == 1
                  ? ImportReviewStep(summary: _summary!, book: _book!)
                  : ImportDestinationStep(
                      selected: _destination,
                      onSelect: (d) => setState(() => _destination = d),
                      worldNameCtrl: _worldNameCtrl,
                      worldDescCtrl: _worldDescCtrl,
                      allCharacters:
                          Provider.of<CharacterRepository>(context).characters,
                      selectedCharacterIds: _selectedCharacterIds,
                      onToggleCharacter: (id, sel) => setState(() {
                        sel
                            ? _selectedCharacterIds.add(id)
                            : _selectedCharacterIds.remove(id);
                      }),
                      activeGroupName: chat.activeGroup?.name,
                      chatAvailable: chat.currentSessionId != null,
                    ),
            ),
          ),
          _buildNavButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(0, 'Pick a file'),
        _stepLine(),
        _stepDot(1, 'Review'),
        _stepLine(),
        _stepDot(2, 'Destination'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    final amber = AppColors.porchAmberOf(context);
    final dotColor = isActive ? amber : AppColors.surfaceContainerOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: isCurrent
                ? Border.all(color: AppColors.textPrimary(context), width: 2)
                : Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? Colors.white
                          : AppColors.textTertiary(context),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive
                ? AppColors.textSecondary(context)
                : AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  Widget _buildPickStep() {
    final amber = AppColors.porchAmberOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              WarmCard(
                accent: amber,
                padding: const EdgeInsets.all(28),
                onTap: _pickFile,
                child: Column(
                  children: [
                    Icon(Icons.upload_file, size: 40, color: amber),
                    const SizedBox(height: 12),
                    Text(
                      _fileName ?? 'Choose a lorebook file',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JSON from SillyTavern, Chub, NovelAI, AgnAI, RisuAI, '
                      'or Front Porch — the format is detected automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (_pickError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _pickError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.negativeAccentOf(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButtons() {
    final amber = AppColors.porchAmberOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: _importing
                  ? null
                  : () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
            ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: !_canProceed || _importing
                ? null
                : _currentStep < 2
                ? () => setState(() => _currentStep++)
                : _runImport,
            style: ElevatedButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: Colors.white,
            ),
            icon: Icon(
              _currentStep < 2 ? Icons.arrow_forward : Icons.download_done,
              size: 16,
            ),
            label: Text(
              _currentStep < 2
                  ? 'Next'
                  : _importing
                  ? 'Importing…'
                  : 'Import ${_book?.entries.length ?? 0} entries',
            ),
          ),
        ],
      ),
    );
  }
}
