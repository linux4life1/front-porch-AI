import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

part 'background_settings_dialog.thumbs.dart';
part 'background_settings_dialog.upload.dart';

class BackgroundSettingsDialog extends StatelessWidget {
  const BackgroundSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    final builtInBackgrounds = [
      _buildBgThumbnail(storageService, 'none', 'None', null),
      _buildBgThumbnail(
        storageService,
        'noir',
        'Noir',
        'assets/backgrounds/noir.png',
      ),
      _buildBgThumbnail(
        storageService,
        'fantasy',
        'Fantasy',
        'assets/backgrounds/fantasy.png',
      ),
      _buildBgThumbnail(
        storageService,
        'grid',
        'Grid',
        'assets/backgrounds/grid.png',
      ),
      _buildBgThumbnail(
        storageService,
        'roman_market',
        'Roman Market',
        'assets/backgrounds/roman_market.png',
      ),
      _buildBgThumbnail(
        storageService,
        'enchanted_wood',
        'Enchanted Wood',
        'assets/backgrounds/enchanted_wood.png',
      ),
      _buildBgThumbnail(
        storageService,
        'ocean_depth',
        'Ocean Depth',
        'assets/backgrounds/ocean_depth.png',
      ),
      _buildBgThumbnail(
        storageService,
        'steampunk_bg',
        'Steampunk',
        'assets/backgrounds/steampunk_bg.png',
      ),
      _buildBgThumbnail(
        storageService,
        'cyberpunk_bedroom',
        'Cyberpunk',
        'assets/backgrounds/cyberpunk_bedroom.png',
      ),
      _buildBgThumbnail(
        storageService,
        'coffee_shop',
        'Coffee Shop',
        'assets/backgrounds/coffee_shop.png',
      ),
      _buildBgThumbnail(
        storageService,
        'beach',
        'Beach',
        'assets/backgrounds/beach.png',
      ),
      _buildBgThumbnail(
        storageService,
        'futuristic_city',
        'Neon City',
        'assets/backgrounds/futuristic_city.png',
      ),
      _buildBgThumbnail(
        storageService,
        'edm_rave',
        'EDM Rave',
        'assets/backgrounds/edm_rave.png',
      ),
      _buildBgThumbnail(
        storageService,
        'cozy_library',
        'Library',
        'assets/backgrounds/cozy_library.png',
      ),
      _buildBgThumbnail(
        storageService,
        'rainy_japan',
        'Rainy Japan',
        'assets/backgrounds/rainy_japan.png',
      ),
      _buildBgThumbnail(
        storageService,
        'space_station',
        'Space',
        'assets/backgrounds/space_station.png',
      ),
      _buildBgThumbnail(
        storageService,
        'enchanted_forest',
        'Forest',
        'assets/backgrounds/enchanted_forest.png',
      ),
      _buildBgThumbnail(
        storageService,
        'anime_cherry_blossom',
        'Sakura',
        'assets/backgrounds/anime_cherry_blossom.png',
      ),
      _buildBgThumbnail(
        storageService,
        'anime_rooftop',
        'Rooftop',
        'assets/backgrounds/anime_rooftop.png',
      ),
      _buildBgThumbnail(
        storageService,
        'anime_rooftop_sunset',
        'Sunset',
        'assets/backgrounds/anime_rooftop_sunset.png',
      ),
      _buildBgThumbnail(
        storageService,
        'cherry_blossom',
        'Blossom',
        'assets/backgrounds/cherry_blossom.png',
      ),
      _buildBgThumbnail(
        storageService,
        'beach_waves',
        'Waves',
        'assets/backgrounds/beach_waves.png',
      ),
      _buildBgThumbnail(
        storageService,
        'waifu_gaming_room',
        'Waifu Game',
        'assets/backgrounds/waifu_gaming_room.png',
      ),
      _buildBgThumbnail(
        storageService,
        'waifu_beach_bar',
        'Waifu Bar',
        'assets/backgrounds/waifu_beach_bar.png',
      ),
      _buildBgThumbnail(
        storageService,
        'waifu_garden',
        'Waifu Garden',
        'assets/backgrounds/waifu_garden.png',
      ),
      _buildBgThumbnail(
        storageService,
        'waifu_neon',
        'Waifu Neon',
        'assets/backgrounds/waifu_neon.png',
      ),
      _buildBgThumbnail(
        storageService,
        'waifu_beach',
        'Waifu Beach',
        'assets/backgrounds/waifu_beach.png',
      ),
    ];

    final customBackgrounds = storageService.uiSettings.customBackgrounds
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
                const Text(
                  'Chat Background',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
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
}
