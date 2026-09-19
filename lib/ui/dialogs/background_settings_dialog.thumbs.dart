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

extension _BackgroundThumbs on BackgroundSettingsDialog {
  Widget _brokenCustomBgThumb() => Container(
    color: const Color(0xFF111827),
    child: const Center(
      child: Icon(Icons.broken_image, color: Colors.white38, size: 28),
    ),
  );

  Widget _buildBgThumbnail(
    StorageService storageService,
    String key,
    String label,
    String? assetPath,
  ) {
    final isSelected = storageService.uiSettings.chatBackground == key;
    return GestureDetector(
      onTap: () => storageService.uiSettings.setChatBackground(key),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.formMasterAccent : Colors.white24,
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
                child: const Center(
                  child: Icon(Icons.block, color: Colors.white38, size: 28),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomBgThumbnail(
    StorageService storageService,
    Map<String, String> entry,
    BuildContext context,
  ) {
    final isSelected = storageService.uiSettings.chatBackground == entry['id'];
    final filePath = entry['filePath'] ?? '';
    return GestureDetector(
      onTap: () => storageService.uiSettings.setChatBackground(entry['id']!),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.formMasterAccent : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (filePath.isEmpty)
              _brokenCustomBgThumb()
            else
              Image.file(
                File(filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _brokenCustomBgThumb(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  entry['name'] ?? 'Custom',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
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
}
