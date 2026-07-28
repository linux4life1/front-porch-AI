import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

class ShaderRenderer {
  ui.Image? _image;
  double _time = 0.0;
  double _breathAmount = 0.0;
  double _blinkAmount = 0.0;
  double _blinkBob = 0.0;
  Offset _drift = Offset.zero;
  double _headTurn = 0.0;
  Offset _lookDir = Offset.zero;
  double _mouthOpen = 0.0;
  double _mouthAngle = 0.0;
  double _eyeTiltAngle = 0.0;
  double _mouthOffsetY = 0.0;

  Offset _anchorLeftEye = const Offset(0.38, 0.35);
  Offset _anchorRightEye = const Offset(0.62, 0.35);
  Offset _anchorMouth = const Offset(0.5, 0.65);
  Offset _anchorNose = const Offset(0.5, 0.5);

  Offset _anchorLeftBrow = const Offset(0.38, 0.28);
  Offset _anchorRightBrow = const Offset(0.62, 0.28);

  Offset _anchorLeftMouthCorner = const Offset(0.42, 0.65);
  Offset _anchorRightMouthCorner = const Offset(0.58, 0.65);
  double _mouthWidth = 0.0;
  double _mouthRound = 0.0;

  FragmentShader? _shader;

  bool get isReady => _shader != null && _image != null;

  void setShader(FragmentShader shader) {
    _shader = shader;
  }

  void setImage(ui.Image image) {
    _image = image;
  }

  void updateAnimation({
    required double time,
    required double breath,
    required double blink,
    required double blinkBob,
    required Offset drift,
    required double headTurn,
    required Offset lookDir,
    required double mouthOpen,
    required double mouthOffsetY,
    required double mouthWidth,
    required double mouthRound,
  }) {
    _time = time;
    _breathAmount = breath;
    _blinkAmount = blink;
    _blinkBob = blinkBob;
    _drift = drift;
    _headTurn = headTurn;
    _lookDir = lookDir;
    _mouthOpen = mouthOpen;
    _mouthOffsetY = mouthOffsetY;
    _mouthWidth = mouthWidth;
    _mouthRound = mouthRound;
  }

  void setAnchors({
    required Offset leftEye,
    required Offset rightEye,
    required Offset mouth,
    required Offset nose,
    required double mouthAngle,
    required double eyeTiltAngle,
    required Offset leftBrow,
    required Offset rightBrow,
    required Offset leftMouthCorner,
    required Offset rightMouthCorner,
  }) {
    _anchorLeftEye = leftEye;
    _anchorRightEye = rightEye;
    _anchorMouth = mouth;
    _anchorNose = nose;
    _mouthAngle = mouthAngle;
    _eyeTiltAngle = eyeTiltAngle;
    _anchorLeftBrow = leftBrow;
    _anchorRightBrow = rightBrow;
    _anchorLeftMouthCorner = leftMouthCorner;
    _anchorRightMouthCorner = rightMouthCorner;
  }

  void paint(Canvas canvas, Size size) {
    if (_shader == null || _image == null) return;

    final shader = _shader!;
    final image = _image!;

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, _time);
    shader.setFloat(3, _breathAmount);
    shader.setFloat(4, _blinkAmount);
    shader.setFloat(5, _drift.dx);
    shader.setFloat(6, _drift.dy);
    shader.setFloat(7, _anchorLeftEye.dx);
    shader.setFloat(8, _anchorLeftEye.dy);
    shader.setFloat(9, _anchorRightEye.dx);
    shader.setFloat(10, _anchorRightEye.dy);
    shader.setFloat(11, _anchorMouth.dx);
    shader.setFloat(12, _anchorMouth.dy);
    shader.setFloat(13, _anchorNose.dx);
    shader.setFloat(14, _anchorNose.dy);
    shader.setFloat(15, _headTurn);
    shader.setFloat(16, _lookDir.dx);
    shader.setFloat(17, _lookDir.dy);
    shader.setFloat(18, _mouthOpen);
    shader.setFloat(19, _mouthAngle);
    shader.setFloat(20, _eyeTiltAngle);
    shader.setFloat(21, _mouthOffsetY);
    shader.setFloat(22, _anchorLeftBrow.dx);
    shader.setFloat(23, _anchorLeftBrow.dy);
    shader.setFloat(24, _anchorRightBrow.dx);
    shader.setFloat(25, _anchorRightBrow.dy);
    shader.setFloat(26, _anchorLeftMouthCorner.dx);
    shader.setFloat(27, _anchorLeftMouthCorner.dy);
    shader.setFloat(28, _anchorRightMouthCorner.dx);
    shader.setFloat(29, _anchorRightMouthCorner.dy);
    shader.setFloat(30, _mouthWidth);
    shader.setFloat(31, _mouthRound);
    shader.setFloat(32, _blinkBob);
    shader.setImageSampler(0, image);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = shader,
    );
  }
}
