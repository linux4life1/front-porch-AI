import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/storage_service.dart';

class BackgroundSettingsDialog extends StatelessWidget {
  const BackgroundSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    final builtInBackgrounds = [
      _buildBgThumbnail(storageService, 'none', 'None', null),
      _buildBgThumbnail(storageService, 'cyberpunk_bedroom', 'Cyberpunk', 'assets/backgrounds/cyberpunk_bedroom.png'),
      _buildBgThumbnail(storageService, 'coffee_shop', 'Coffee Shop', 'assets/backgrounds/coffee_shop.png'),
      _buildBgThumbnail(storageService, 'beach', 'Beach', 'assets/backgrounds/beach.png'),
      _buildBgThumbnail(storageService, 'futuristic_city', 'Neon City', 'assets/backgrounds/futuristic_city.png'),
      _buildBgThumbnail(storageService, 'edm_rave', 'EDM Rave', 'assets/backgrounds/edm_rave.png'),
      _buildBgThumbnail(storageService, 'cozy_library', 'Library', 'assets/backgrounds/cozy_library.png'),
      _buildBgThumbnail(storageService, 'rainy_japan', 'Rainy Japan', 'assets/backgrounds/rainy_japan.png'),
      _buildBgThumbnail(storageService, 'space_station', 'Space', 'assets/backgrounds/space_station.png'),
      _buildBgThumbnail(storageService, 'enchanted_forest', 'Forest', 'assets/backgrounds/enchanted_forest.png'),
      _buildBgThumbnail(storageService, 'anime_cherry_blossom', 'Sakura', 'assets/backgrounds/anime_cherry_blossom.png'),
      _buildBgThumbnail(storageService, 'anime_rooftop', 'Rooftop', 'assets/backgrounds/anime_rooftop.png'),
      _buildBgThumbnail(storageService, 'anime_rooftop_sunset', 'Sunset', 'assets/backgrounds/anime_rooftop_sunset.png'),
      _buildBgThumbnail(storageService, 'cherry_blossom', 'Blossom', 'assets/backgrounds/cherry_blossom.png'),
      _buildBgThumbnail(storageService, 'beach_waves', 'Waves', 'assets/backgrounds/beach_waves.png'),
      _buildBgThumbnail(storageService, 'waifu_gaming_room', 'Waifu Game', 'assets/backgrounds/waifu_gaming_room.png'),
      _buildBgThumbnail(storageService, 'waifu_beach_bar', 'Waifu Bar', 'assets/backgrounds/waifu_beach_bar.png'),
      _buildBgThumbnail(storageService, 'waifu_garden', 'Waifu Garden', 'assets/backgrounds/waifu_garden.png'),
      _buildBgThumbnail(storageService, 'waifu_neon', 'Waifu Neon', 'assets/backgrounds/waifu_neon.png'),
      _buildBgThumbnail(storageService, 'waifu_beach', 'Waifu Beach', 'assets/backgrounds/waifu_beach.png'),
    ];

    final customBackgrounds = storageService.customBackgrounds
        .map((entry) => _buildCustomBgThumbnail(storageService, entry, context))
        .toList();

    final allBackgrounds = [...builtInBackgrounds, ...customBackgrounds];

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Chat Background', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showUploadDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Custom Background'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: allBackgrounds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBgThumbnail(StorageService storageService, String key, String label, String? assetPath) {
    final isSelected = storageService.chatBackground == key;
    return GestureDetector(
      onTap: () => storageService.setChatBackground(key),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (assetPath != null)
              Image.asset(assetPath, fit: BoxFit.cover)
            else
              Container(
                color: const Color(0xFF111827),
                child: const Center(child: Icon(Icons.block, color: Colors.white38, size: 28)),
              ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomBgThumbnail(StorageService storageService, Map<String, String> entry, BuildContext context) {
    final isSelected = storageService.chatBackground == entry['id'];
    final filePath = entry['filePath'] ?? '';
    return GestureDetector(
      onTap: () => storageService.setChatBackground(entry['id']!),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (filePath.isNotEmpty && File(filePath).existsSync())
              Image.file(File(filePath), fit: BoxFit.cover)
            else
              Container(
                color: const Color(0xFF111827),
                child: const Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 28)),
              ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  entry['name'] ?? 'Custom',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _showDeleteConfirmation(
                  entry['id']!,
                  filePath,
                  entry['name'] ?? 'Custom',
                  context,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(String id, String filePath, String name, BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Delete Background', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "$name"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final storageService = Provider.of<StorageService>(context, listen: false);
              storageService.removeCustomBackground(id);
              if (filePath.isNotEmpty) {
                File(filePath).delete();
              }
              if (storageService.chatBackground == id) {
                storageService.setChatBackground('none');
              }
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
          title: const Text('Add Custom Background', style: TextStyle(color: Colors.white)),
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
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isUploading ? null : () async {
                      final result = await FilePicker.platform.pickFiles(type: FileType.image);
                      if (result != null && result.files.single.path != null) {
                        setState(() {
                          selectedImagePath = result.files.single.path!;
                          isUploading = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(selectedImagePath != null ? 'Change Image' : 'Browse'),
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
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final storageService = Provider.of<StorageService>(context, listen: false);

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a name')),
                  );
                  return;
                }

                if (storageService.hasCustomBackgroundWithName(name)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('A background with this name already exists')),
                  );
                  return;
                }

                if (selectedImagePath == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select an image')),
                  );
                  return;
                }

                final extension = path.extension(selectedImagePath!).toLowerCase();
                final allowedExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff'];
                if (!allowedExtensions.contains(extension)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid image format. Allowed: JPG, PNG, WEBP, GIF, BMP, TIFF')),
                  );
                  return;
                }

                setState(() => isUploading = true);

                final key = DateTime.now().millisecondsSinceEpoch.toString();
                final customDir = storageService.customBackgroundDir;
                await customDir.create(recursive: true);
                final destPath = path.join(customDir.path, '$key.png');
                await File(selectedImagePath!).copy(destPath);

                await storageService.addCustomBackground(key, name, destPath);
                await storageService.setChatBackground(key);

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
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : const Text('Upload', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
