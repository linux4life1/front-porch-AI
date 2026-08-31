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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// The main view, list-card, edit-form, and hover-card builders live in these
// `part of` files (extensions on _UserPersonaPageState, plus one library-
// private StatefulWidget) to keep every file under the 500-LOC cap — same
// pattern chat_service.dart / settings_page.dart use. They share this
// library's imports and access the page's private state directly, so
// behavior is unchanged.
part 'user_persona_page.main_view.dart';
part 'user_persona_page.list_cards.dart';
part 'user_persona_page.edit_form.dart';
part 'user_persona_page.hover_card.dart';

class UserPersonaPage extends StatefulWidget {
  const UserPersonaPage({super.key});

  @override
  State<UserPersonaPage> createState() => _UserPersonaPageState();
}

class _UserPersonaPageState extends State<UserPersonaPage>
    with SingleTickerProviderStateMixin {
  bool _isEditing = false;
  UserPersona? _editingPersona;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _nameController;
  late TextEditingController _personaController;
  String? _avatarPath;
  String _birthday = '';

  late AnimationController _headerAnimController;
  late Animation<double> _headerGlowAnimation;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _nameController = TextEditingController();
    _personaController = TextEditingController();

    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _headerGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    _personaController.dispose();
    _headerAnimController.dispose();
    super.dispose();
  }

  void _startEditing(UserPersona? persona) {
    setState(() {
      _isEditing = true;
      _editingPersona = persona;
      _titleController.text = persona?.title ?? '';
      _nameController.text = persona?.name ?? '';
      _personaController.text = persona?.persona ?? '';
      _avatarPath = persona?.avatarPath;
      _birthday = persona?.birthday ?? '';
    });
  }

  void _setBirthday(String v) => setState(() => _birthday = v);

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingPersona = null;
      _titleController.clear();
      _nameController.clear();
      _personaController.clear();
      _avatarPath = null;
      _birthday = '';
    });
  }

  Future<void> _pickAvatar() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImage,
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = await PickerPrefs.localPathOrTemp(result.files.single);
      if (path == null) return;
      setState(() {
        _avatarPath = path;
      });
    }
  }

  Future<void> _savePersona() async {
    if (_formKey.currentState!.validate()) {
      final service = Provider.of<UserPersonaService>(context, listen: false);
      final personaText = _personaController.text;

      if (_editingPersona != null) {
        final updated = _editingPersona!.copyWith(
          title: _titleController.text,
          name: _nameController.text,
          persona: personaText,
          avatarPath: _avatarPath,
          birthday: _birthday,
        );
        await service.updatePersona(updated);
      } else {
        await service.createPersona(
          _titleController.text,
          _nameController.text,
          personaText,
          _avatarPath,
          birthday: _birthday,
        );
      }

      _cancelEditing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Colors.greenAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Persona saved successfully',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
              ],
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importPersona() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.isNotEmpty) {
      final jsonPath = await PickerPrefs.localPathOrTemp(result.files.single);
      if (jsonPath == null) return;
      final service = Provider.of<UserPersonaService>(context, listen: false);
      final storage = Provider.of<StorageService>(context, listen: false);
      final avatarDir = storage.rootPath != null
          ? '${storage.rootPath}/persona_avatars'
          : null;

      final imported = await service.importFromJsonFile(
        jsonPath,
        avatarSaveDir: avatarDir,
      );

      if (mounted) {
        if (imported != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.download_done,
                    color: Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Imported "${imported.name}" successfully',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ],
              ),
              backgroundColor: AppColors.surfaceContainerOf(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Import failed — unrecognized format',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ],
              ),
              backgroundColor: AppColors.surfaceContainerOf(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _exportPersona(UserPersona persona) async {
    final service = Provider.of<UserPersonaService>(context, listen: false);
    String? outputFile = await PickerPrefs.saveFromBuilder(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export Persona',
      fileName:
          '${persona.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}_FPAIpersona.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      writeTemp: (path) => service.exportPersonasToSTFormat([persona.id], path),
    );

    if (outputFile != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported to $outputFile',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showExportDialog() {
    final service = Provider.of<UserPersonaService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => ExportPersonaDialog(personas: service.personas),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: Text(
          _isEditing
              ? (_editingPersona == null ? 'Create Persona' : 'Edit Persona')
              : 'User Personas',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _cancelEditing,
              )
            : null,
        actions: _isEditing
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.cyanAccent),
                  tooltip: 'Import Persona (JSON)',
                  onPressed: _importPersona,
                ),
                IconButton(
                  icon: const Icon(Icons.upload, color: Colors.amberAccent),
                  tooltip: 'Export Personas (JSON)',
                  onPressed: _showExportDialog,
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Persona'),
                  onPressed: () => _startEditing(null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onChaosAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _isEditing
            ? _buildEditForm(context, key: const ValueKey('edit'))
            : _buildMainView(key: const ValueKey('list')),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────

  void _showDeleteConfirmation(BuildContext context, UserPersona persona) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Persona',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
            children: [
              TextSpan(text: 'Are you sure you want to delete '),
              TextSpan(
                text: '"${persona.name}"',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              TextSpan(text: '? This cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<UserPersonaService>(
                context,
                listen: false,
              ).deletePersona(persona.id);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
