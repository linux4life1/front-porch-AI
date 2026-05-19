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
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/utils/persona_colors.dart';

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
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingPersona = null;
      _titleController.clear();
      _nameController.clear();
      _personaController.clear();
      _avatarPath = null;
    });
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
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
        // Update
        final updated = _editingPersona!.copyWith(
          title: _titleController.text,
          name: _nameController.text,
          persona: _personaController.text,
          avatarPath: _avatarPath,
        );
        await service.updatePersona(updated);
      } else {
        // Create
        await service.createPersona(
          _titleController.text,
          _nameController.text,
          _personaController.text,
          _avatarPath,
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

  Widget _buildList() {
    return Consumer<UserPersonaService>(
      builder: (context, service, child) {
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'User Personas',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
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
                      color: isActive ? Colors.blueAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: isActive ? Border.all(color: Colors.blueAccent) : null,
                    ),
                    child: ListTile(
                      leading: PersonaColors.buildPersonaAvatar(
                        avatarPath: persona.avatarPath,
                        personaId: persona.id,
                        radius: 20,
                      ),
                      title: Text(persona.displayLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        persona.title.isNotEmpty
                            ? persona.name
                            : persona.persona.isNotEmpty
                                ? (persona.persona.length > 40
                                    ? '${persona.persona.substring(0, 37)}...'
                                    : persona.persona)
                                : '',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isActive)
                            TextButton(
                              onPressed: () => service.setActivePersona(persona.id),
                              child: const Text('Select'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.white70),
                            onPressed: () => _startEditing(persona),
                          ),
                          if (service.personas.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                              onPressed: () => _showDeleteConfirmation(context, persona),
                            ),
                        ],
                      ),
                      onTap: () => service.setActivePersona(persona.id),
                    ),
                  );
                },
              ),
            ),
            // Learned facts for active persona
            if (service.persona.learnedFacts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Colors.purpleAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Learned Facts (${service.persona.learnedFacts.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const Spacer(),
                  if (service.persona.learnedFacts.length > 10)
                    TextButton.icon(
                      onPressed: () => _showClearFactsConfirmation(context, service),
                      icon: const Icon(Icons.delete_sweep, size: 14, color: Colors.redAccent),
                      label: const Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Auto-extracted from your conversations:',
                style: TextStyle(fontSize: 11, color: Colors.white30),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: List.generate(service.persona.learnedFacts.length, (i) {
                      return Chip(
                        label: Text(
                          service.persona.learnedFacts[i],
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                        backgroundColor: const Color(0xFF374151),
                        deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white38),
                        onDeleted: () => service.removeLearnedFact(i),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startEditing(null),
                icon: const Icon(Icons.add),
                label: const Text('Add New Persona'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _editingPersona == null ? 'Create Persona' : 'Edit Persona',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: _cancelEditing,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    image: _avatarPath != null
                        ? DecorationImage(
                            image: FileImage(File(_avatarPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: _avatarPath == null
                      ? const Icon(Icons.add_a_photo, size: 32, color: Colors.white54)
                      : null,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Title (optional)',
                        hintText: 'Label to distinguish this persona',
                        hintStyle: TextStyle(color: Colors.white30),
                        labelStyle: TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Color(0xFF374151),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'Name sent to the AI',
                        hintStyle: TextStyle(color: Colors.white30),
                        labelStyle: TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Color(0xFF374151),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value?.isEmpty ?? true ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    // Persona text — expandable
                    Stack(
                      children: [
                        TextFormField(
                          controller: _personaController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Persona Text',
                            hintText: 'Describe who you are — appearance, personality, background...',
                            hintStyle: TextStyle(color: Colors.white30),
                            labelStyle: TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Color(0xFF374151),
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 4,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _showExpandPersonaDialog(),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.open_in_full,
                                  size: 16,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelEditing,
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _savePersona,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showExpandPersonaDialog() {
    final tempController = TextEditingController(text: _personaController.text);
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF1F2937),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'Edit Persona Text',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: tempController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Enter detailed persona info...',
                    hintStyle: TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Color(0xFF374151),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      _personaController.text = tempController.text;
                      Navigator.of(dialogContext).pop();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
               Provider.of<UserPersonaService>(context, listen: false).deletePersona(persona.id);
               Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showClearFactsConfirmation(BuildContext context, UserPersonaService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Clear All Facts'),
        content: Text('Remove all ${service.persona.learnedFacts.length} learned facts? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              while (service.persona.learnedFacts.isNotEmpty) {
                service.removeLearnedFact(0);
              }
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
