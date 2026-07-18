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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Optional img2img reference-image control for the Image Studio.
///
/// Shows a "Reference image (optional)" picker; once an image is set it reveals
/// a thumbnail, a clear button, and the **Denoise** slider (0.2–0.9) that only
/// exists while a reference is present — because denoise is meaningless without
/// one. The denoise value is the shared `StorageService.imageGenDenoise` setting
/// (single source of truth across all three local backends).
///
/// img2img is a local-backend feature only: the remote-API paths have no
/// img2img endpoint, so this widget renders nothing when the configured backend
/// is `remote` (it reads the backend live via Provider so switching backends in
/// the Generation Settings tab hides/shows it without extra wiring).
class ReferenceImagePicker extends StatelessWidget {
  final Uint8List? referenceBytes;
  final bool isBusy;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const ReferenceImagePicker({
    super.key,
    required this.referenceBytes,
    required this.isBusy,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    // Only the local backends (A1111, Draw Things, ComfyUI) support img2img.
    final backend = context.select<StorageService, String>(
      (s) => s.imageGenBackend,
    );
    if (backend == 'remote') return const SizedBox.shrink();

    final hasRef = referenceBytes != null && referenceBytes!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Reference image (optional)',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasRef)
                TextButton.icon(
                  onPressed: isBusy ? null : onClear,
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textTertiary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasRef)
            OutlinedButton.icon(
              onPressed: isBusy ? null : onPick,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('Choose image…'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.formMasterAccent,
                side: BorderSide(color: AppColors.borderOf(context)),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    referenceBytes!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'This photo is a starting point — the slider below sets '
                        'how far the result can drift from it.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: isBusy ? null : onPick,
                        icon: const Icon(Icons.swap_horiz, size: 14),
                        label: const Text('Replace'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.formMasterAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DenoiseSlider(isBusy: isBusy),
          ],
        ],
      ),
    );
  }
}

/// The img2img denoise slider — kept private to this file since it is only ever
/// shown alongside a chosen reference image. Reads/writes the shared
/// `imageGenDenoise` setting so every local backend uses the same value.
class _DenoiseSlider extends StatelessWidget {
  final bool isBusy;
  const _DenoiseSlider({required this.isBusy});

  @override
  Widget build(BuildContext context) {
    final denoise = context.select<StorageService, double>(
      (s) => s.imageGenDenoise,
    );
    // The setting clamps to 0–1; the slider offers the usable img2img window.
    final display = denoise.clamp(0.2, 0.9);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'How different from the photo?',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Slider(
          value: display.toDouble(),
          min: 0.2,
          max: 0.9,
          divisions: 14,
          label: display.toStringAsFixed(2),
          activeColor: AppColors.formMasterAccent,
          onChanged: isBusy
              ? null
              : (v) => context.read<StorageService>().setImageGenDenoise(v),
        ),
        Text(
          'Left keeps it close to your photo; right lets the prompt take over.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
