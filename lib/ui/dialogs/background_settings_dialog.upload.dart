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

part of 'background_settings_dialog.dart';

extension _BackgroundUpload on BackgroundSettingsDialog {
  void _showDeleteConfirmation(
    String id,
    String filePath,
    String name,
    BuildContext context,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Delete Background',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$name"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
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

  Future<void> _showUploadDialog(BuildContext context) async {
    final nameController = TextEditingController();
    String? selectedImagePath;
    bool isUploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Add Custom Background',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    labelStyle: TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Color(0xFF374151),
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
                            final result = await PickerPrefs.pickFiles(
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
                      foregroundColor: Colors.white,
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
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
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

                if (storageService.uiSettings.hasCustomBackgroundWithName(
                  name,
                )) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'A background with this name already exists',
                      ),
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
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Upload', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
