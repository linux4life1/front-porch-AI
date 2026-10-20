// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A blurred backdrop that is captured and blurred once, then painted as a
/// still, instead of a live [BackdropFilter] that re-blurs the whole window
/// every frame while the child animates.
///
/// On its first frame the widget paints nothing, so the capture of the
/// nearest enclosing [RenderRepaintBoundary] holds only what is behind it.
/// Until the still is ready, [child] is shown over no blur. On a resize the
/// still stretches to fill; it is never recaptured with [child] on top.
class FrozenBackdropBlur extends StatefulWidget {
  const FrozenBackdropBlur({
    super.key,
    required this.sigma,
    required this.child,
    this.captureScale = 0.25,
  });

  /// Blur radius in logical pixels, as a live `ImageFilter.blur` would take.
  final double sigma;

  /// Capture resolution as a fraction of the device pixel ratio.
  final double captureScale;

  final Widget child;

  static const stillKey = ValueKey('frozen-backdrop-still');

  @override
  State<FrozenBackdropBlur> createState() => _FrozenBackdropBlurState();
}

class _FrozenBackdropBlurState extends State<FrozenBackdropBlur> {
  bool _captured = false;
  ui.Image? _still;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  @override
  void dispose() {
    _disposed = true;
    _still?.dispose();
    _still = null;
    super.dispose();
  }

  void _capture() {
    if (!mounted) return;
    try {
      final box = context.findRenderObject() as RenderBox?;
      final boundary = _boundaryCovering(box);
      if (box == null || boundary == null) {
        debugPrint('[FrozenBackdropBlur] no repaint boundary to capture');
        return;
      }
      final origin = box.localToGlobal(Offset.zero, ancestor: boundary);
      final ratio =
          widget.captureScale * MediaQuery.devicePixelRatioOf(context);
      // toImage snapshots the layer tree now; the raster finishes later.
      final pending = boundary.toImage(pixelRatio: ratio);
      _blurInto(pending, (origin & box.size), ratio);
    } catch (e, st) {
      debugPrint('[FrozenBackdropBlur] capture failed: $e\n$st');
    } finally {
      setState(() => _captured = true);
    }
  }

  RenderRepaintBoundary? _boundaryCovering(RenderBox? box) {
    if (box == null || !box.hasSize) return null;
    RenderObject? node = box.parent;
    while (node != null) {
      if (node is RenderRepaintBoundary &&
          node.hasSize &&
          node.size.width >= box.size.width &&
          node.size.height >= box.size.height) {
        return node;
      }
      node = node.parent;
    }
    return null;
  }

  Future<void> _blurInto(
    Future<ui.Image> pending,
    Rect region,
    double ratio,
  ) async {
    ui.Image? shot;
    ui.Picture? picture;
    try {
      shot = await pending;
      final src = Rect.fromLTWH(
        region.left * ratio,
        region.top * ratio,
        region.width * ratio,
        region.height * ratio,
      );
      final width = src.width.round().clamp(1, 1 << 14);
      final height = src.height.round().clamp(1, 1 << 14);
      final sigma = widget.sigma * ratio;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        shot,
        src,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()
          ..filterQuality = FilterQuality.low
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
      picture = recorder.endRecording();
      final still = await picture.toImage(width, height);
      if (_disposed) {
        still.dispose();
        return;
      }
      setState(() {
        _still?.dispose();
        _still = still;
      });
    } catch (e, st) {
      debugPrint('[FrozenBackdropBlur] blur failed: $e\n$st');
    } finally {
      shot?.dispose();
      picture?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = _still;
    return Opacity(
      opacity: _captured ? 1 : 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (still != null)
            RawImage(
              key: FrozenBackdropBlur.stillKey,
              image: still,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
          widget.child,
        ],
      ),
    );
  }
}
