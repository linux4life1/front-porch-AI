import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/background_settings/background_settings.dart';

/// (key, label, asset) for each built-in background; a null asset is None.
const _builtInBackgrounds = <(String, String, String?)>[
  ('none', 'None', null),
  ('noir', 'Noir', 'assets/backgrounds/noir.png'),
  ('fantasy', 'Fantasy', 'assets/backgrounds/fantasy.png'),
  ('grid', 'Grid', 'assets/backgrounds/grid.png'),
  ('roman_market', 'Roman Market', 'assets/backgrounds/roman_market.png'),
  ('enchanted_wood', 'Enchanted Wood', 'assets/backgrounds/enchanted_wood.png'),
  ('ocean_depth', 'Ocean Depth', 'assets/backgrounds/ocean_depth.png'),
  ('steampunk_bg', 'Steampunk', 'assets/backgrounds/steampunk_bg.png'),
  (
    'cyberpunk_bedroom',
    'Cyberpunk',
    'assets/backgrounds/cyberpunk_bedroom.png',
  ),
  ('coffee_shop', 'Coffee Shop', 'assets/backgrounds/coffee_shop.png'),
  ('beach', 'Beach', 'assets/backgrounds/beach.png'),
  ('futuristic_city', 'Neon City', 'assets/backgrounds/futuristic_city.png'),
  ('edm_rave', 'EDM Rave', 'assets/backgrounds/edm_rave.png'),
  ('cozy_library', 'Library', 'assets/backgrounds/cozy_library.png'),
  ('rainy_japan', 'Rainy Japan', 'assets/backgrounds/rainy_japan.png'),
  ('space_station', 'Space', 'assets/backgrounds/space_station.png'),
  ('enchanted_forest', 'Forest', 'assets/backgrounds/enchanted_forest.png'),
  (
    'anime_cherry_blossom',
    'Sakura',
    'assets/backgrounds/anime_cherry_blossom.png',
  ),
  ('anime_rooftop', 'Rooftop', 'assets/backgrounds/anime_rooftop.png'),
  (
    'anime_rooftop_sunset',
    'Sunset',
    'assets/backgrounds/anime_rooftop_sunset.png',
  ),
  ('cherry_blossom', 'Blossom', 'assets/backgrounds/cherry_blossom.png'),
  ('beach_waves', 'Waves', 'assets/backgrounds/beach_waves.png'),
  (
    'waifu_gaming_room',
    'Waifu Game',
    'assets/backgrounds/waifu_gaming_room.png',
  ),
  ('waifu_beach_bar', 'Waifu Bar', 'assets/backgrounds/waifu_beach_bar.png'),
  ('waifu_garden', 'Waifu Garden', 'assets/backgrounds/waifu_garden.png'),
  ('waifu_neon', 'Waifu Neon', 'assets/backgrounds/waifu_neon.png'),
  ('waifu_beach', 'Waifu Beach', 'assets/backgrounds/waifu_beach.png'),
];

class BackgroundSettingsDialog extends StatelessWidget {
  const BackgroundSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    Widget thumb(String key, String label, String? assetPath) =>
        BackgroundThumbnail(
          label: label,
          assetPath: assetPath,
          isSelected: storageService.uiSettings.chatBackground == key,
          onTap: () => storageService.uiSettings.setChatBackground(key),
        );

    final builtInBackgrounds = [
      for (final (key, label, assetPath) in _builtInBackgrounds)
        thumb(key, label, assetPath),
    ];

    final customBackgrounds = storageService.uiSettings.customBackgrounds
        .map(
          (entry) => CustomBackgroundThumbnail(
            name: entry['name'] ?? 'Custom',
            filePath: entry['filePath'] ?? '',
            isSelected: storageService.uiSettings.chatBackground == entry['id'],
            onTap: () =>
                storageService.uiSettings.setChatBackground(entry['id']!),
            onDelete: () => showDeleteBackgroundConfirmation(
              context,
              id: entry['id']!,
              filePath: entry['filePath'] ?? '',
              name: entry['name'] ?? 'Custom',
            ),
          ),
        )
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
                  onPressed: () => showAddCustomBackgroundDialog(context),
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
