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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'user_persona_dialog.edit_form.dart';

class UserPersonaDialog extends StatefulWidget {
  const UserPersonaDialog({super.key});

  @override
  State<UserPersonaDialog> createState() => _UserPersonaDialogState();
}

class _UserPersonaDialogState extends State<UserPersonaDialog> {
  bool _isEditing = false;
  UserPersona? _editingPersona;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _nameController;
  late TextEditingController _personaController;
  String? _avatarPath;
  String _birthday = '';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _nameController = TextEditingController();
    _personaController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    _personaController.dispose();
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

    if (result != null && result.files.single.path != null) {
      setState(() {
        _avatarPath = result.files.single.path;
      });
    }
  }

  Future<void> _savePersona() async {
    if (_formKey.currentState!.validate()) {
      final service = Provider.of<UserPersonaService>(context, listen: false);

      if (_editingPersona != null) {
        final updated = _editingPersona!.copyWith(
          title: _titleController.text,
          name: _nameController.text,
          persona: _personaController.text,
          avatarPath: _avatarPath,
          birthday: _birthday,
        );
        await service.updatePersona(updated);
      } else {
        await service.createPersona(
          _titleController.text,
          _nameController.text,
          _personaController.text,
          _avatarPath,
          birthday: _birthday,
        );
      }

      _cancelEditing();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: _isEditing ? _buildEditForm() : _buildList(),
      ),
    );
  }

  /// Switch the OPEN CHAT to [personaId] and bind the session to it. Does not
  /// touch the default for new chats — that lives on the Persona page. The
  /// immediate save is what makes "switch, then close the app" stick.
  Future<void> _useInThisChat(
    BuildContext context,
    UserPersonaService service,
    String personaId,
  ) async {
    final chat = Provider.of<ChatService>(context, listen: false);
    await service.setActivePersona(personaId);
    await chat.persistSessionPersona();
  }

  Widget _buildList() {
    return Consumer<UserPersonaService>(
      builder: (context, service, child) {
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Speak as…',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: service.personas.length,
                itemBuilder: (context, index) {
                  final persona = service.personas[index];
                  final isActive = persona.id == service.persona.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.formMasterAccent.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: isActive
                          ? Border.all(color: AppColors.formMasterAccent)
                          : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: PersonaColors.buildPersonaAvatar(
                          avatarPath: persona.avatarPath,
                          personaId: persona.id,
                          radius: 20,
                        ),
                        title: Text(
                          persona.displayLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          persona.title.isNotEmpty
                              ? persona.name
                              : persona.persona.isNotEmpty
                              ? (persona.persona.length > 40
                                    ? '${persona.persona.substring(0, 37)}...'
                                    : persona.persona)
                              : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isActive)
                              TextButton(
                                onPressed: () => _useInThisChat(
                                  context,
                                  service,
                                  persona.id,
                                ),
                                child: const Text('Use in this chat'),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 20,
                                color: Colors.white70,
                              ),
                              onPressed: () => _startEditing(persona),
                            ),
                            if (service.personas.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  size: 20,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () =>
                                    _showDeleteConfirmation(context, persona),
                              ),
                          ],
                        ),
                        onTap: () =>
                            _useInThisChat(context, service, persona.id),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startEditing(null),
                icon: const Icon(Icons.add),
                label: const Text('Add New Persona'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formMasterAccent,
                  foregroundColor: AppColors.onChaosAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, UserPersona persona) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Delete Persona'),
        content: Text('Are you sure you want to delete "${persona.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<UserPersonaService>(
                context,
                listen: false,
              ).deletePersona(persona.id);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
