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
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Asks before deleting the custom background [id]; on yes removes it (and
/// its file), falls back to no background if it was selected, and closes
/// both this prompt and the background dialog under [context].
void showDeleteBackgroundConfirmation(
  BuildContext context, {
  required String id,
  required String filePath,
  required String name,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(ctx),
      title: Text(
        'Delete Background',
        style: TextStyle(color: AppColors.textPrimary(ctx)),
      ),
      content: Text(
        'Are you sure you want to delete "$name"? This action cannot be undone.',
        style: TextStyle(color: AppColors.textSecondary(ctx)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(ctx)),
          ),
        ),
        TextButton(
          onPressed: () {
            final storageService = Provider.of<StorageService>(
              context,
              listen: false,
            );
            storageService.uiSettings.removeCustomBackground(id);
            if (filePath.isNotEmpty) {
              File(filePath).delete();
            }
            if (storageService.uiSettings.chatBackground == id) {
              storageService.uiSettings.setChatBackground('none');
            }
            Navigator.pop(ctx);
            Navigator.pop(context);
          },
          child: const Text(
            'Delete',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    ),
  );
}

/// Lets the user name and pick an image, copies it into the custom
/// background folder, selects it, and closes the background dialog.
Future<void> showAddCustomBackgroundDialog(BuildContext context) async {
  final nameController = TextEditingController();
  String? selectedImagePath;
  bool isUploading = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(
          'Add Custom Background',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(
                    color: AppColors.textSecondary(context),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.formMasterAccent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () async {
                          final result = await GuardedPicker.pickFiles(
                            context,
                            category: PickerPrefs.catImage,
                            type: FileType.image,
                          );
                          if (result != null && result.files.isNotEmpty) {
                            final path = await PickerPrefs.localPathOrTemp(
                              result.files.single,
                            );
                            if (path == null) return;
                            setState(() {
                              selectedImagePath = path;
                              isUploading = false;
                            });
                          }
                        },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(
                    selectedImagePath != null ? 'Change Image' : 'Browse',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary(context),
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (selectedImagePath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(selectedImagePath!),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final storageService = Provider.of<StorageService>(
                context,
                listen: false,
              );

              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }

              if (storageService.uiSettings.hasCustomBackgroundWithName(name)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('A background with this name already exists'),
                  ),
                );
                return;
              }

              if (selectedImagePath == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select an image')),
                );
                return;
              }

              final extension = path
                  .extension(selectedImagePath!)
                  .toLowerCase();
              final allowedExtensions = [
                '.jpg',
                '.jpeg',
                '.png',
                '.webp',
                '.gif',
                '.bmp',
                '.tiff',
              ];
              if (!allowedExtensions.contains(extension)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invalid image format. Allowed: JPG, PNG, WEBP, GIF, BMP, TIFF',
                    ),
                  ),
                );
                return;
              }

              setState(() => isUploading = true);

              final key = DateTime.now().millisecondsSinceEpoch.toString();
              final customDir = storageService.customBackgroundDir;
              await customDir.create(recursive: true);
              final destPath = path.join(customDir.path, '$key.png');
              await File(selectedImagePath!).copy(destPath);

              await storageService.uiSettings.addCustomBackground(
                key,
                name,
                destPath,
              );
              await storageService.uiSettings.setChatBackground(key);

              if (Navigator.of(ctx).canPop()) {
                Navigator.pop(ctx);
              }
              if (Navigator.of(context).canPop()) {
                Navigator.pop(context);
              }
            },
            child: isUploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.textPrimary(context),
                      ),
                    ),
                  )
                : Text(
                    'Upload',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
          ),
        ],
      ),
    ),
  );
}
