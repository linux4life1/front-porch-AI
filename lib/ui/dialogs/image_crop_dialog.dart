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

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:crop_your_image/crop_your_image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A reusable dialog that lets the user interactively crop an image.
///
/// Returns the cropped image bytes (`Uint8List`) on "Crop & Save",
/// or `null` if the user cancels.
class ImageCropDialog extends StatefulWidget {
  /// The raw image bytes to crop.
  final Uint8List imageBytes;

  /// Optional aspect ratio width. If null, free-form cropping is allowed.
  final double? aspectRatioWidth;

  /// Optional aspect ratio height. If null, free-form cropping is allowed.
  final double? aspectRatioHeight;

  const ImageCropDialog({
    super.key,
    required this.imageBytes,
    this.aspectRatioWidth,
    this.aspectRatioHeight,
  });

  /// Show the dialog and return cropped bytes, or null if cancelled.
  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    double? aspectRatioWidth,
    double? aspectRatioHeight,
  }) {
    return showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageCropDialog(
        imageBytes: imageBytes,
        aspectRatioWidth: aspectRatioWidth,
        aspectRatioHeight: aspectRatioHeight,
      ),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final _cropController = CropController();
  late Uint8List _currentImageBytes;
  bool _isCropping = false;
  bool _isPadding = false;

  @override
  void initState() {
    super.initState();
    _currentImageBytes = widget.imageBytes;
  }

  Future<void> _padImage() async {
    setState(() => _isPadding = true);
    // Yield to let UI show loading spinner
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final decoded = img.decodeImage(_currentImageBytes);
      if (decoded != null) {
        // Increase canvas size by 25%
        final newWidth = (decoded.width * 1.25).toInt();
        final newHeight = (decoded.height * 1.25).toInt();

        final padded = img.Image(width: newWidth, height: newHeight);
        // Fill with app background color
        img.fill(padded, color: img.ColorRgb8(26, 26, 46));

        // Center the original image on the new padded canvas
        img.compositeImage(
          padded,
          decoded,
          dstX: (newWidth - decoded.width) ~/ 2,
          dstY: (newHeight - decoded.height) ~/ 2,
        );

        final newBytes = img.encodePng(padded);
        if (mounted) {
          setState(() {
            _currentImageBytes = newBytes;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to pad image: $e');
    } finally {
      if (mounted) setState(() => _isPadding = false);
    }
  }

  void _onCropAndSave() {
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  void _onCropped(CropResult result) {
    // Default to empty bytes in case of failure.
    Uint8List bytes = Uint8List(0);
    // If the crop was successful, extract the image bytes.
    if (result is CropSuccess) {
      bytes = result.croppedImage;
    }
    if (mounted) {
      Navigator.of(context).pop(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.7).clamp(400.0, 800.0);
    final dialogHeight = (screenSize.height * 0.8).clamp(500.0, 900.0);

    return Dialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.crop,
                    color: AppColors.formMasterAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Crop Your Image',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Drag to reposition and resize the crop area. The image will be saved at the selected region.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ),

            // Crop area
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: Crop(
                  controller: _cropController,
                  image: _currentImageBytes,
                  aspectRatio:
                      (widget.aspectRatioWidth != null &&
                          widget.aspectRatioHeight != null)
                      ? widget.aspectRatioWidth! / widget.aspectRatioHeight!
                      : null,
                  onCropped: _onCropped,
                  baseColor: const Color(0xFF111827),
                  maskColor: Colors.black.withValues(alpha: 0.6),
                  cornerDotBuilder: (size, edgeAlignment) =>
                      DotControl(color: AppColors.formMasterAccent),
                  interactive: true,
                  fixCropRect: false,
                ),
              ),
            ),

            // Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: (_isCropping || _isPadding) ? null : _padImage,
                    icon: _isPadding
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.formMasterAccent,
                            ),
                          )
                        : const Icon(
                            Icons.zoom_out_map,
                            size: 16,
                            color: AppColors.formMasterAccent,
                          ),
                    label: Text(
                      _isPadding ? 'Zooming...' : 'Zoom Out (Pad Canvas)',
                      style: const TextStyle(color: AppColors.formMasterAccent),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: (_isCropping || _isPadding)
                        ? null
                        : () => Navigator.of(context).pop(null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: (_isCropping || _isPadding)
                        ? null
                        : _onCropAndSave,
                    icon: _isCropping
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onChaosAccent,
                            ),
                          )
                        : const Icon(Icons.crop_sharp, size: 18),
                    label: Text(_isCropping ? 'Cropping...' : 'Crop & Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
