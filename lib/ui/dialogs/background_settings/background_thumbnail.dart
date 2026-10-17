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

/// A built-in chat background tile. [assetPath] null is the "None" tile.
class BackgroundThumbnail extends StatelessWidget {
  const BackgroundThumbnail({
    super.key,
    required this.label,
    required this.assetPath,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String? assetPath;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              Image.asset(assetPath!, fit: BoxFit.cover)
            else
              Container(
                color: AppColors.sunkenSurfaceOf(context),
                child: Center(
                  child: Icon(
                    Icons.block,
                    color: AppColors.textTertiary(context),
                    size: 28,
                  ),
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
}

/// A user-uploaded chat background tile with a delete button.
class CustomBackgroundThumbnail extends StatelessWidget {
  const CustomBackgroundThumbnail({
    super.key,
    required this.name,
    required this.filePath,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final String name;
  final String filePath;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Widget _brokenThumb(BuildContext context) => Container(
    color: AppColors.sunkenSurfaceOf(context),
    child: Center(
      child: Icon(
        Icons.broken_image,
        color: AppColors.textTertiary(context),
        size: 28,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              _brokenThumb(context)
            else
              Image.file(
                File(filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _brokenThumb(context),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  name,
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
                onTap: onDelete,
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
