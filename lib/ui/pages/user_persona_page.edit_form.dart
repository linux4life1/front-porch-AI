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

part of 'user_persona_page.dart';

/// The create/edit persona form for [_UserPersonaPageState]: the avatar
/// picker + title/name/persona fields, plus the full-screen "expand persona
/// text" dialog. Extracted verbatim from the inline _buildEditForm and its
/// field helpers; direct state access preserves behavior. AppColors +
/// warm-porch accents.
extension _UserPersonaEditForm on _UserPersonaPageState {
  // ── Edit Form ─────────────────────────────────────────────────────────

  Widget _buildEditForm(BuildContext context, {Key? key}) {
    return Center(
      key: key,
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              const Color(0xFF1E293B).withValues(alpha: 0.85),
              AppColors.lightSurface.withValues(alpha: 0.95),
            ),
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
            key: _formKey,
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
                        onTap: _pickAvatar,
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
                            image: _avatarPath != null
                                ? DecorationImage(
                                    image: FileImage(File(_avatarPath!)),
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
                          child: _avatarPath == null
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
                            controller: _titleController,
                            label: 'Title',
                            hint:
                                'Label to distinguish this persona (optional)',
                          ),
                          const SizedBox(height: 14),
                          _buildFormField(
                            context: context,
                            controller: _nameController,
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
                  iso: _birthday,
                  onChanged: _setBirthday,
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
                  controller: _personaController,
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
                      onPressed: _cancelEditing,
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _savePersona,
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
              onTap: () => _showExpandPersonaDialog(controller),
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

  void _showExpandPersonaDialog(TextEditingController controller) {
    final tempController = TextEditingController(text: controller.text);
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(dialogContext),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(dialogContext)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
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
              ),
              Divider(height: 1, color: AppColors.borderOf(dialogContext)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: tempController,
                    style: TextStyle(
                      color: AppColors.textPrimary(dialogContext),
                      fontSize: 14,
                    ),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Enter detailed persona info...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(dialogContext),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(dialogContext),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.borderOf(dialogContext),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.borderOf(dialogContext),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.porchAmberOf(dialogContext),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
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
                        controller.text = tempController.text;
                        Navigator.of(dialogContext).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.porchAmberOf(dialogContext),
                        foregroundColor: AppColors.onChaosAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
