import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'shader_renderer.dart';
import 'animation_engine.dart';
import 'face_detector_service.dart';
import 'animation_viewport.dart';

class LivePortraitAvatar extends StatefulWidget {
  final File imageFile;
  final double size;
  final BoxFit fit;

  const LivePortraitAvatar({
    super.key,
    required this.imageFile,
    required this.size,
    this.fit = BoxFit.cover,
  });

  @override
  State<LivePortraitAvatar> createState() => _LivePortraitAvatarState();
}

class _LivePortraitAvatarState extends State<LivePortraitAvatar> {
  final ShaderRenderer _renderer = ShaderRenderer();
  final AnimationEngine _engine = AnimationEngine();
  final FaceDetectorService _faceDetector = FaceDetectorService();

  bool _ready = false;
  ui.Image? _loadedImage;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(LivePortraitAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path) {
      _reloadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      await _faceDetector.initialize();

      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _loadedImage = frame.image;
      _renderer.setImage(frame.image);

      if (!mounted) return;

      final landmarks = await _faceDetector.detectFromFile(
        widget.imageFile.path,
      );

      if (!mounted) return;

      if (landmarks != null) {
        final w = frame.image.width.toDouble();
        final h = frame.image.height.toDouble();

        _renderer.setAnchors(
          leftEye: Offset(landmarks.leftEye.dx / w, landmarks.leftEye.dy / h),
          rightEye: Offset(landmarks.rightEye.dx / w, landmarks.rightEye.dy / h),
          mouth: Offset(landmarks.mouth.dx / w, landmarks.mouth.dy / h),
          nose: Offset(landmarks.nose.dx / w, landmarks.nose.dy / h),
          mouthAngle: landmarks.mouthAngle,
          eyeTiltAngle: landmarks.eyeTiltAngle,
          leftBrow: Offset(
            landmarks.leftEyebrowCenter.dx / w,
            landmarks.leftEyebrowCenter.dy / h,
          ),
          rightBrow: Offset(
            landmarks.rightEyebrowCenter.dx / w,
            landmarks.rightEyebrowCenter.dy / h,
          ),
          leftMouthCorner: Offset(
            landmarks.leftMouthCorner.dx / w,
            landmarks.leftMouthCorner.dy / h,
          ),
          rightMouthCorner: Offset(
            landmarks.rightMouthCorner.dx / w,
            landmarks.rightMouthCorner.dy / h,
          ),
        );
        _engine.params.faceDetected = true;
      } else {
        _engine.params.faceDetected = false;
      }

      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _reloadImage() async {
    _ready = false;
    _engine.reset();
    await _loadImage();
  }

  @override
  void dispose() {
    _faceDetector.dispose();
    _engine.params.enabled = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _loadedImage == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Image.file(
          widget.imageFile,
          width: widget.size,
          fit: widget.fit,
          alignment: Alignment.topCenter,
          errorBuilder: (_, _, _) => const Icon(Icons.person, size: 64),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRect(
        child: AnimationViewport(
          renderer: _renderer,
          engine: _engine,
          fallback: Image.file(
            widget.imageFile,
            width: widget.size,
            fit: widget.fit,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const Icon(Icons.person, size: 64),
          ),
        ),
      ),
    );
  }
}
