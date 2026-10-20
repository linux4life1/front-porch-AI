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

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/dialogs/image_crop/image_crop.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_overlay.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Interactive image crop — blank-slate rewrite (2026-08-14) replacing the
/// crop_your_image package after the Discord report; presets, fill choices,
/// the circle guide and unlimited padding landed in the same-day A–E batch.
///
/// The model has NO zoom: the whole image is always visible, and the crop
/// box may be dragged PAST the image edges — the view auto-refits so there
/// is always room to keep pulling (up to the output-size cap), and the
/// overhang previews as, and saves as, the chosen fill. All geometry lives
/// in [crop_geometry.dart] as pure source-space math; this widget is only
/// paint + gestures.
///
/// Returns the cropped PNG bytes on "Crop & Save", or null on cancel.
class ImageCropDialog extends StatefulWidget {
  /// The raw image bytes to crop.
  final Uint8List imageBytes;

  const ImageCropDialog({super.key, required this.imageBytes});

  /// Show the dialog and return cropped bytes, or null if cancelled.
  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
  }) {
    return showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageCropDialog(imageBytes: imageBytes),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  /// Fraction of the viewport's shortest side kept as breathing room around
  /// the fitted content (image ∪ crop box).
  static const _marginFraction = 0.06;
  static const _grabRadius = 14.0;

  Size? _imageSize; // decoded dimensions; null while decoding
  Rect? _cropSrc; // crop rect in SOURCE pixels (may extend beyond the image)
  CropHandle? _activeHandle;
  CropHandle? _hoverHandle;
  double? _aspect;
  bool _circle = false;
  CropFill _fill = CropFill.dark;
  bool _isCropping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decodeDimensions();
  }

  Future<void> _decodeDimensions() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _cropSrc = Offset.zero & size;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not read this image: $e');
    }
  }

  double get _minSizeSrc => 16.0.clamp(1.0, _imageSize!.shortestSide);

  void _selectPreset(double? aspect, {bool circle = false}) {
    setState(() {
      _aspect = aspect;
      _circle = circle;
      if (aspect != null) {
        _cropSrc = aspectFitRect(
          _cropSrc!,
          aspect,
          world: cropWorldRect(_imageSize!),
          minSize: _minSizeSrc,
        );
      }
    });
  }

  Future<void> _onCropAndSave() async {
    final crop = _cropSrc;
    if (crop == null || _isCropping) return;
    setState(() {
      _isCropping = true;
      _error = null;
    });
    final left = crop.left.round();
    final top = crop.top.round();
    final width = (crop.right.round() - left).clamp(1, 1 << 16);
    final height = (crop.bottom.round() - top).clamp(1, 1 << 16);
    try {
      final bytes = await compute(cropCompositeSync, <Object>[
        widget.imageBytes,
        left,
        top,
        width,
        height,
        _fill.r,
        _fill.g,
        _fill.b,
        _fill.a,
      ]);
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCropping = false;
        _error = 'Crop failed: $e';
      });
    }
  }

  // ── Geometry for the current layout ───────────────────────────────────────

  ({Rect imageVp, Rect worldSrc, double scale}) _layout(Size viewportSize) {
    final viewport = Offset.zero & viewportSize;
    final inset = _marginFraction * viewportSize.shortestSide;
    // Fit the UNION of image and crop box, so pulling the box past an edge
    // auto-refits the view — there is always room to keep pulling, up to
    // the world cap. Nothing on screen is ever cut off.
    final unionSrc = (Offset.zero & _imageSize!).expandToInclude(_cropSrc!);
    final fitted = containFitRect(unionSrc.size, viewport.deflate(inset));
    final scale = fitted.width / unionSrc.width;
    final imageVp = Rect.fromLTWH(
      fitted.left - unionSrc.left * scale,
      fitted.top - unionSrc.top * scale,
      _imageSize!.width * scale,
      _imageSize!.height * scale,
    );
    return (
      imageVp: imageVp,
      worldSrc: cropWorldRect(_imageSize!),
      scale: scale,
    );
  }

  Rect _srcToVp(Rect src, Rect imageVp, double scale) => Rect.fromLTWH(
    imageVp.left + src.left * scale,
    imageVp.top + src.top * scale,
    src.width * scale,
    src.height * scale,
  );

  MouseCursor _cursorFor(CropHandle? handle) => switch (handle) {
    CropHandle.topLeft ||
    CropHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    CropHandle.topRight ||
    CropHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    CropHandle.top || CropHandle.bottom => SystemMouseCursors.resizeUpDown,
    CropHandle.left || CropHandle.right => SystemMouseCursors.resizeLeftRight,
    CropHandle.move => SystemMouseCursors.move,
    null => SystemMouseCursors.basic,
  };

  /// Under a locked aspect only corners resize; edge grabs are ignored.
  CropHandle? _filterHandle(CropHandle? h) {
    if (h == null || _aspect == null) return h;
    return switch (h) {
      CropHandle.top ||
      CropHandle.bottom ||
      CropHandle.left ||
      CropHandle.right => null,
      _ => h,
    };
  }

  Widget _buildStage(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layout(constraints.biggest);
        final cropVp = _srcToVp(_cropSrc!, layout.imageVp, layout.scale);
        return MouseRegion(
          cursor: _cursorFor(_activeHandle ?? _hoverHandle),
          onHover: (e) {
            final h = _filterHandle(
              hitTestCropHandle(e.localPosition, cropVp, _grabRadius),
            );
            if (h != _hoverHandle) setState(() => _hoverHandle = h);
          },
          child: GestureDetector(
            key: const ValueKey('crop_stage'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => setState(() {
              _activeHandle = _filterHandle(
                hitTestCropHandle(d.localPosition, cropVp, _grabRadius),
              );
            }),
            onPanUpdate: (d) {
              final handle = _activeHandle;
              if (handle == null) return;
              setState(() {
                _cropSrc = applyCropDrag(
                  _cropSrc!,
                  handle,
                  d.delta / layout.scale,
                  world: layout.worldSrc,
                  minSize: _minSizeSrc,
                  aspect: _circle ? 1.0 : _aspect,
                );
              });
            },
            onPanEnd: (_) => setState(() => _activeHandle = null),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: CropFillBasePainter(_fill)),
                Positioned.fromRect(
                  rect: layout.imageVp,
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: CropOverlayPainter(
                      cropVp: cropVp,
                      accent: AppColors.porchAmberOf(context),
                      scrim: InkColors.dim(0.55),
                      showEdgeHandles: _aspect == null,
                      circleGuide: _circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.7).clamp(400.0, 800.0);
    final dialogHeight = (screenSize.height * 0.8).clamp(500.0, 900.0);
    final crop = _cropSrc;
    final sizeReadout = crop == null
        ? ''
        : '${(crop.right.round() - crop.left.round()).clamp(1, 1 << 16)} × '
              '${(crop.bottom.round() - crop.top.round()).clamp(1, 1 << 16)} px';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isCropping) Navigator.of(context).pop(null);
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderOf(context)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.crop,
                        color: AppColors.porchAmberOf(context),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Crop Your Image',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: AppColors.iconSecondary(context),
                        ),
                        onPressed: () => Navigator.of(context).pop(null),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(
                    'Drag the box or pull its corners. Keep pulling past the '
                    'picture\'s edges to add background around it — what you '
                    'see is exactly what gets saved.',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_imageSize != null)
                  CropPresetRow(
                    aspect: _aspect,
                    circle: _circle,
                    fill: _fill,
                    onSelectPreset: (aspect, circle) =>
                        _selectPreset(aspect, circle: circle),
                    onSelectFill: (fill) => setState(() => _fill = fill),
                  ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _imageSize == null
                        ? Center(
                            child: _error != null
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: SelectableText(
                                      _error!,
                                      style: TextStyle(
                                        color: AppColors.textSecondary(context),
                                      ),
                                    ),
                                  )
                                : CircularProgressIndicator(
                                    color: AppColors.porchAmberOf(context),
                                  ),
                          )
                        : _buildStage(context),
                  ),
                ),
                if (_error != null && _imageSize != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                CropFooterBar(
                  isCropping: _isCropping,
                  ready: _imageSize != null,
                  sizeReadout: sizeReadout,
                  onReset: () =>
                      setState(() => _cropSrc = Offset.zero & _imageSize!),
                  onCancel: () => Navigator.of(context).pop(null),
                  onCropAndSave: _onCropAndSave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
