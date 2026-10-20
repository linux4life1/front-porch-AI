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

import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The "Speak as…" create / edit form: avatar, title, name, birthday and
/// persona text, with Cancel and Save.
class PersonaEditForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isNew;
  final TextEditingController titleController;
  final TextEditingController nameController;
  final TextEditingController personaController;
  final String? avatarPath;
  final String birthday;
  final ValueChanged<String> onBirthdayChanged;
  final VoidCallback onPickAvatar;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const PersonaEditForm({
    super.key,
    required this.formKey,
    required this.isNew,
    required this.titleController,
    required this.nameController,
    required this.personaController,
    required this.avatarPath,
    required this.birthday,
    required this.onBirthdayChanged,
    required this.onPickAvatar,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isNew ? 'Create Persona' : 'Edit Persona',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: AppColors.textSecondary(context),
                ),
                onPressed: onCancel,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: onPickAvatar,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: InkColors.washOf(context, 0.05, 0.04),
                            shape: BoxShape.circle,
                            image: avatarPath != null
                                ? DecorationImage(
                                    image: FileImage(File(avatarPath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            border: Border.all(
                              color: InkColors.fieldEdgeOf(context),
                            ),
                          ),
                          child: avatarPath == null
                              ? Icon(
                                  Icons.add_a_photo,
                                  size: 32,
                                  color: AppColors.textSecondary(context),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: titleController,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                              ),
                              decoration: InputDecoration(
                                labelText: 'Title (optional)',
                                hintText: 'Label to distinguish this persona',
                                hintStyle: TextStyle(
                                  color: AppColors.textTertiary(context),
                                ),
                                labelStyle: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                                filled: true,
                                fillColor: AppColors.surfaceContainerOf(
                                  context,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: nameController,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                              ),
                              decoration: InputDecoration(
                                labelText: 'Name',
                                hintText: 'Name sent to the AI',
                                hintStyle: TextStyle(
                                  color: AppColors.textTertiary(context),
                                ),
                                labelStyle: TextStyle(
                                  color: AppColors.textSecondary(context),
                                ),
                                filled: true,
                                fillColor: AppColors.surfaceContainerOf(
                                  context,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Name is required'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  BirthdayRow(
                    iso: birthday,
                    onChanged: onBirthdayChanged,
                    ageAsOf: storyDateOf(context),
                    helper:
                        'The story calendar uses this so they know how old '
                        'you are and when your birthday is. February 29 is '
                        'not allowed.',
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    children: [
                      TextFormField(
                        controller: personaController,
                        style: TextStyle(color: AppColors.textPrimary(context)),
                        decoration: InputDecoration(
                          labelText: 'Persona Text',
                          hintText:
                              'Describe who you are — appearance, personality, background...',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(context),
                          ),
                          labelStyle: TextStyle(
                            color: AppColors.textSecondary(context),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerOf(context),
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
                            onTap: () => showExpandPersonaTextDialog(
                              context,
                              personaController,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.formAccentOf(
                                  context,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.open_in_full,
                                size: 16,
                                color: AppColors.formAccentOf(context),
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
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formAccentOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-size editor for the persona text; Save writes back into
/// [personaController].
void showExpandPersonaTextDialog(
  BuildContext context,
  TextEditingController personaController,
) {
  final tempController = TextEditingController(text: personaController.text);
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.surfaceOf(dialogContext),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Edit Persona Text',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(dialogContext),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.textSecondary(dialogContext),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: tempController,
                style: TextStyle(color: AppColors.textPrimary(dialogContext)),
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Enter detailed persona info...',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary(dialogContext),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(dialogContext),
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
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.textSecondary(dialogContext),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    personaController.text = tempController.text;
                    Navigator.of(dialogContext).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.formAccentOf(context),
                    foregroundColor: AppColors.onAccentOf(context),
                  ),
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
