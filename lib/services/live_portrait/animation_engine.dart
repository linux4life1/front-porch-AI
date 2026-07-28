import 'dart:math';
import 'package:flutter/material.dart';

class AnimationParams {
  double breathIntensity = 1.0;
  double blinkFrequency = 1.0;
  double driftAmount = 0.2;
  double headTurnAmount = 0.1;
  double mouthOffsetY = 0.0;
  bool enabled = true;
}

class AnimationEngine {
  final Random _random = Random();
  final AnimationParams params = AnimationParams();

  double _startTime = 0;
  double _lastTime = 0;

  double _breathCycle = 0;

  double _blinkTimer = 0;
  double _nextBlinkIn = 0;
  double _blinkProgress = 0;
  bool _isBlinking = false;

  Offset _driftVelocity = Offset.zero;
  Offset _driftPosition = Offset.zero;
  double _driftChangeTimer = 0;

  double _saccadeTimer = 0;
  Offset _saccadeTarget = Offset.zero;
  Offset _saccadeCurrent = Offset.zero;
  double _saccadeHoldTime = 0;

  void start(double initialTime) {
    _startTime = initialTime;
    _lastTime = initialTime;
    _nextBlinkIn = _randomDouble(1.5, 4.0);
    _driftChangeTimer = _randomDouble(1.0, 3.0);
    _pickNewDriftVelocity();
    _pickNewSaccadeTarget();
  }

  void reset() {
    _startTime = _lastTime;
    _breathCycle = 0;
    _blinkTimer = 0;
    _nextBlinkIn = _randomDouble(1.5, 4.0);
    _blinkProgress = 0;
    _isBlinking = false;
    _driftVelocity = Offset.zero;
    _driftPosition = Offset.zero;
    _driftChangeTimer = _randomDouble(1.0, 3.0);
    _pickNewDriftVelocity();
    _saccadeTimer = 0;
    _saccadeCurrent = Offset.zero;
    _saccadeHoldTime = 0;
    _pickNewSaccadeTarget();
  }

  void update(double time) {
    if (!params.enabled) return;

    final dt = (time - _lastTime).clamp(0.0, 0.1);
    _lastTime = time;
    final elapsed = time - _startTime;

    _breathCycle = sin(elapsed * 0.8) * 0.5 + 0.5;

    _updateBlink(dt);
    _updateDrift(dt);
    _updateSaccades(dt);
  }

  void _updateBlink(double dt) {
    final freq = params.blinkFrequency;
    _blinkTimer += dt;

    if (!_isBlinking && _blinkTimer >= _nextBlinkIn / freq) {
      _isBlinking = true;
      _blinkProgress = 0;
      _blinkTimer = 0;
    }

    if (_isBlinking) {
      _blinkProgress += dt * 6.25;
      if (_blinkProgress >= 1.0) {
        _isBlinking = false;
        _blinkProgress = 0;
        _nextBlinkIn = _randomDouble(1.5, 4.0);
      }
    }
  }

  void _updateDrift(double dt) {
    _driftChangeTimer -= dt;
    if (_driftChangeTimer <= 0) {
      _pickNewDriftVelocity();
      _driftChangeTimer = _randomDouble(2.0, 5.0);
    }

    _driftPosition += _driftVelocity * dt * params.driftAmount;
    final dist = _driftPosition.distance;
    if (dist > 12.0) {
      _driftPosition = _driftPosition * (12.0 / dist);
    }
  }

  void _updateSaccades(double dt) {
    _saccadeTimer -= dt;

    if (_saccadeTimer <= 0) {
      _saccadeHoldTime = _randomDouble(0.2, 0.5);
      _pickNewSaccadeTarget();
      _saccadeTimer = _saccadeHoldTime;
    }

    final t = (1.0 - (_saccadeTimer / _saccadeHoldTime)).clamp(0.0, 1.0);
    final snapT = t * t * (3.0 - 2.0 * t);
    _saccadeCurrent = Offset(
      _saccadeCurrent.dx + (_saccadeTarget.dx - _saccadeCurrent.dx) * snapT * 0.3,
      _saccadeCurrent.dy + (_saccadeTarget.dy - _saccadeCurrent.dy) * snapT * 0.3,
    );
  }

  void _pickNewSaccadeTarget() {
    _saccadeTarget = Offset(
      _randomDouble(-0.3, 0.3),
      _randomDouble(-0.15, 0.15),
    );
  }

  void _pickNewDriftVelocity() {
    final angle = _random.nextDouble() * 2 * pi;
    final speed = _randomDouble(1.0, 4.0);
    _driftVelocity = Offset(cos(angle) * speed, sin(angle) * speed);
  }

  double _randomDouble(double min, double max) {
    return min + _random.nextDouble() * (max - min);
  }

  double get breath => _breathCycle * params.breathIntensity;

  double get blink {
    if (!_isBlinking) return 0.0;
    double raw;
    if (_blinkProgress < 0.5) {
      raw = _blinkProgress * 2.0;
    } else {
      raw = (1.0 - _blinkProgress) * 2.0;
    }
    return raw;
  }

  double get blinkBob => blink * 0.003;

  Offset get drift => _driftPosition;

  double get headTurn => sin(_lastTime * 0.15) * 0.4 * params.headTurnAmount;

  Offset get lookDirection {
    final baseX = -sin(_lastTime * 0.15) * 0.4;
    final baseY = sin(_lastTime * 0.1) * 0.2;

    final saccX = _saccadeCurrent.dx;
    final saccY = _saccadeCurrent.dy;

    return Offset(
      (baseX + saccX).clamp(-0.8, 0.8),
      (baseY + saccY).clamp(-0.4, 0.4),
    );
  }

  double get mouthOpen => 0;
  double get mouthWidth => 0;
  double get mouthRound => 0;
}
