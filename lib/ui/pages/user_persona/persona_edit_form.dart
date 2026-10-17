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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'persona_text_expand_dialog.dart';

/// The create/edit persona form: avatar picker + title/name/persona fields,
/// birthday row, and Cancel / Save Persona. The page owns the controllers
/// and draft values; this widget only renders them and reports intents.
class PersonaEditForm extends StatelessWidget {
  const PersonaEditForm({
    super.key,
    required this.formKey,
    required this.titleController,
    required this.nameController,
    required this.personaController,
    required this.avatarPath,
    required this.birthday,
    required this.onPickAvatar,
    required this.onBirthdayChanged,
    required this.onCancel,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleController;
  final TextEditingController nameController;
  final TextEditingController personaController;
  final String? avatarPath;
  final String birthday;
  final VoidCallback onPickAvatar;
  final ValueChanged<String> onBirthdayChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: AppColors.resolve(
                  context,
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.08),
                ),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar picker
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: onPickAvatar,
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              context,
                              Colors.white.withValues(alpha: 0.04),
                              Colors.black.withValues(alpha: 0.03),
                            ),
                            shape: BoxShape.circle,
                            image: avatarPath != null
                                ? DecorationImage(
                                    image: FileImage(File(avatarPath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            border: Border.all(
                              color: AppColors.porchAmberOf(
                                context,
                              ).withValues(alpha: 0.25),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.porchAmberOf(
                                  context,
                                ).withValues(alpha: 0.08),
                                blurRadius: 16,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: avatarPath == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo,
                                      size: 28,
                                      color: AppColors.textTertiary(context),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Avatar',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textTertiary(context),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [
                          _buildFormField(
                            context: context,
                            controller: titleController,
                            label: 'Title',
                            hint:
                                'Label to distinguish this persona (optional)',
                          ),
                          const SizedBox(height: 14),
                          _buildFormField(
                            context: context,
                            controller: nameController,
                            label: 'Name',
                            hint: 'Name sent to the AI',
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Name is required' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                BirthdayRow(
                  iso: birthday,
                  onChanged: onBirthdayChanged,
                  ageAsOf: storyDateOf(context),
                  helper:
                      'The story calendar uses this so they know how old '
                      'you are and when your birthday is. February 29 is '
                      'not allowed.',
                ),
                const SizedBox(height: 18),
                // Persona text — expandable
                _buildExpandableFormField(
                  context: context,
                  controller: personaController,
                  label: 'Persona Text (injected into AI context)',
                  hint:
                      'Detailed persona info the AI will know about you — '
                      'appearance, traits, background, preferences...',
                  helperText:
                      'This text is sent to the AI in every conversation. '
                      'Import from SillyTavern or Backyard AI auto-populates this.',
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onCancel,
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: onSave,
                      icon: const Icon(Icons.save, size: 18),
                      label: const Text('Save Persona'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.porchAmberOf(context),
                        foregroundColor: AppColors.onChaosAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
        ),
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        helperText: helperText,
        helperStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 11,
        ),
        helperMaxLines: 2,
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.porchAmberOf(context),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildExpandableFormField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
  }) {
    return Stack(
      children: [
        _buildFormField(
          context: context,
          controller: controller,
          label: label,
          hint: hint,
          maxLines: 5,
          helperText: helperText,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showPersonaTextExpandDialog(context, controller),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.porchAmberOf(
                    context,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.open_in_full,
                  size: 16,
                  color: AppColors.porchAmberOf(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
