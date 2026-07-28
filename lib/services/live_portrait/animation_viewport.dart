import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'shader_renderer.dart';
import 'animation_engine.dart';

class AnimationViewport extends StatefulWidget {
  final ShaderRenderer renderer;
  final AnimationEngine engine;
  final Widget fallback;

  const AnimationViewport({
    super.key,
    required this.renderer,
    required this.engine,
    required this.fallback,
  });

  @override
  State<AnimationViewport> createState() => _AnimationViewportState();
}

class _AnimationViewportState extends State<AnimationViewport>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _elapsedSeconds = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
      _lastTick = elapsed;
      _elapsedSeconds += dt;
      widget.engine.update(_elapsedSeconds);
      widget.renderer.updateAnimation(
        time: _elapsedSeconds,
        breath: widget.engine.breath,
        blink: widget.engine.blink,
        blinkBob: widget.engine.blinkBob,
        drift: widget.engine.drift,
        headTurn: widget.engine.headTurn,
        lookDir: widget.engine.lookDirection,
        mouthOpen: widget.engine.mouthOpen,
        mouthOffsetY: widget.engine.params.mouthOffsetY,
        mouthWidth: widget.engine.mouthWidth,
        mouthRound: widget.engine.mouthRound,
      );
      if (mounted) setState(() {});
    });
    _ticker.start();
    widget.engine.start(0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      assetKey: 'assets/shaders/displacement.frag',
      (BuildContext context, FragmentShader shader, Widget? child) {
        widget.renderer.setShader(shader);
        return LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _ShaderPainter(widget.renderer),
            );
          },
        );
      },
      child: widget.fallback,
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final ShaderRenderer renderer;

  _ShaderPainter(this.renderer);

  @override
  void paint(Canvas canvas, Size size) {
    renderer.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter oldDelegate) => true;
}
