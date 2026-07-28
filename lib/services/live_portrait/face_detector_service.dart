import 'dart:math';
import 'dart:ui';
import 'package:face_detection_tflite/face_detection_tflite.dart';

class FaceLandmarks {
  final Offset leftEye;
  final Offset rightEye;
  final Offset nose;
  final Offset mouth;
  final double mouthAngle;
  final double eyeTiltAngle;

  final Offset leftEyebrowCenter;
  final Offset rightEyebrowCenter;
  final Offset leftMouthCorner;
  final Offset rightMouthCorner;

  final double browInnerUp;
  final double browOuterUpLeft;
  final double browOuterUpRight;
  final double browDownLeft;
  final double browDownRight;
  final double smileLeft;
  final double smileRight;
  final double frownLeft;
  final double frownRight;
  final double cheekSquintLeft;
  final double cheekSquintRight;
  final double jawOpen;

  const FaceLandmarks({
    required this.leftEye,
    required this.rightEye,
    required this.nose,
    required this.mouth,
    required this.mouthAngle,
    required this.eyeTiltAngle,
    required this.leftEyebrowCenter,
    required this.rightEyebrowCenter,
    required this.leftMouthCorner,
    required this.rightMouthCorner,
    required this.browInnerUp,
    required this.browOuterUpLeft,
    required this.browOuterUpRight,
    required this.browDownLeft,
    required this.browDownRight,
    required this.smileLeft,
    required this.smileRight,
    required this.frownLeft,
    required this.frownRight,
    required this.cheekSquintLeft,
    required this.cheekSquintRight,
    required this.jawOpen,
  });
}

class FaceDetectorService {
  FaceDetector? _detector;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _detector = await FaceDetector.create(
      model: FaceDetectionModel.full,
    );
    _initialized = true;
  }

  Future<FaceLandmarks?> detectFromFile(String path) async {
    if (!_initialized || _detector == null) return null;

    try {
      final faces = await _detector!.detectFacesFromFilepath(
        path,
        mode: FaceDetectionMode.full,
      );

      if (faces.isEmpty) return null;

      final face = faces.first;
      final lm = face.landmarks;
      final mesh = face.mesh;
      final bs = face.blendshapes;

      final leftEye = lm.leftEye;
      final rightEye = lm.rightEye;
      final nose = lm.noseTip;

      if (leftEye == null || rightEye == null) return null;

      final eyeTiltAngle = atan2(
        rightEye.y - leftEye.y,
        rightEye.x - leftEye.x,
      );

      Offset mouth;
      double mouthAngle = 0.0;
      Offset leftMouthCorner = const Offset(0.42, 0.65);
      Offset rightMouthCorner = const Offset(0.58, 0.65);
      Offset leftEyebrowCenter = Offset(
        (leftEye.x + rightEye.x) * 0.25 + leftEye.x * 0.75,
        leftEye.y - 0.05,
      );
      Offset rightEyebrowCenter = Offset(
        (leftEye.x + rightEye.x) * 0.25 + rightEye.x * 0.75,
        rightEye.y - 0.05,
      );

      if (mesh != null) {
        final upperLip = mesh[13];
        final lowerLip = mesh[14];
        mouth = Offset(
          (upperLip.x + lowerLip.x) * 0.5,
          (upperLip.y + lowerLip.y) * 0.5,
        );

        final lc = mesh[61];
        final rc = mesh[291];
        leftMouthCorner = Offset(lc.x, lc.y);
        rightMouthCorner = Offset(rc.x, rc.y);
        mouthAngle = atan2(
          rc.y - lc.y,
          rc.x - lc.x,
        );

        leftEyebrowCenter = Offset(mesh[70].x, mesh[70].y);
        rightEyebrowCenter = Offset(mesh[300].x, mesh[300].y);
      } else {
        final mouthLm = lm.mouth;
        mouth = mouthLm != null
            ? Offset(mouthLm.x, mouthLm.y)
            : const Offset(0.5, 0.65);
      }

      double bIU = 0, bOUL = 0, bOUR = 0, bDL = 0, bDR = 0;
      double sL = 0, sR = 0, fL = 0, fR = 0, cSL = 0, cSR = 0, jO = 0;
      if (bs != null) {
        bIU = bs[Blendshape.browInnerUp];
        bOUL = bs[Blendshape.browOuterUpLeft];
        bOUR = bs[Blendshape.browOuterUpRight];
        bDL = bs[Blendshape.browDownLeft];
        bDR = bs[Blendshape.browDownRight];
        sL = bs[Blendshape.mouthSmileLeft];
        sR = bs[Blendshape.mouthSmileRight];
        fL = bs[Blendshape.mouthFrownLeft];
        fR = bs[Blendshape.mouthFrownRight];
        cSL = bs[Blendshape.cheekSquintLeft];
        cSR = bs[Blendshape.cheekSquintRight];
        jO = bs[Blendshape.jawOpen];
      }

      return FaceLandmarks(
        leftEye: Offset(leftEye.x, leftEye.y),
        rightEye: Offset(rightEye.x, rightEye.y),
        nose: nose != null ? Offset(nose.x, nose.y) : const Offset(0.5, 0.5),
        mouth: mouth,
        mouthAngle: mouthAngle,
        eyeTiltAngle: eyeTiltAngle,
        leftEyebrowCenter: leftEyebrowCenter,
        rightEyebrowCenter: rightEyebrowCenter,
        leftMouthCorner: leftMouthCorner,
        rightMouthCorner: rightMouthCorner,
        browInnerUp: bIU,
        browOuterUpLeft: bOUL,
        browOuterUpRight: bOUR,
        browDownLeft: bDL,
        browDownRight: bDR,
        smileLeft: sL,
        smileRight: sR,
        frownLeft: fL,
        frownRight: fR,
        cheekSquintLeft: cSL,
        cheekSquintRight: cSR,
        jawOpen: jO,
      );
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _detector?.dispose();
    _detector = null;
    _initialized = false;
  }
}
